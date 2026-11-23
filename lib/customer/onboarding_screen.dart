import 'package:flutter/material.dart';

import '../auth/auth_gate.dart';
import '../core/constants.dart';
import '../core/data.dart';
import '../core/theme.dart';
import '../core/utils.dart';
import '../core/widgets.dart';

/// Asks the wedding questions one by one. Everything except the name can be skipped.
class CustomerOnboardingScreen extends StatefulWidget {
  const CustomerOnboardingScreen({super.key});
  @override
  State<CustomerOnboardingScreen> createState() => _CustomerOnboardingScreenState();
}

class _CustomerOnboardingScreenState extends State<CustomerOnboardingScreen> {
  final _pages = PageController();
  final _name = TextEditingController();
  final _city = TextEditingController();
  final _budget = TextEditingController();
  final _guests = TextEditingController();
  DateTime? _date;
  final Set<String> _events = {'Biye', 'Bou Bhat'};
  int _step = 0;
  bool _busy = false;
  bool _loaded = false;

  static const _total = 6;

  @override
  void initState() {
    super.initState();
    _prefill();
  }

  Future<void> _prefill() async {
    try {
      final p = await fetchMyProfile();
      final c = await fetchCustomerProfile();
      _name.text = str(p['full_name']);
      _city.text = str(c['wedding_city']);
      if (c['budget'] != null) _budget.text = toD(c['budget']).toStringAsFixed(0);
      if (c['guest_count'] != null) _guests.text = toI(c['guest_count']).toString();
      _date = parseDate(c['wedding_date']);
      final ev = asStrings(c['planned_events']);
      if (ev.isNotEmpty) {
        _events
          ..clear()
          ..addAll(ev);
      }
    } catch (_) {}
    if (mounted) setState(() => _loaded = true);
  }

  @override
  void dispose() {
    _pages.dispose();
    for (final c in [_name, _city, _budget, _guests]) {
      c.dispose();
    }
    super.dispose();
  }

  void _next() {
    if (_step == 0 && _name.text.trim().isEmpty) {
      showSnack(context, 'Please tell us your name.', error: true);
      return;
    }
    FocusScope.of(context).unfocus();
    if (_step == _total - 1) {
      _finish();
      return;
    }
    setState(() => _step++);
    _pages.animateToPage(_step, duration: const Duration(milliseconds: 280), curve: Curves.easeOut);
  }

  void _back() {
    if (_step == 0) return;
    setState(() => _step--);
    _pages.animateToPage(_step, duration: const Duration(milliseconds: 280), curve: Curves.easeOut);
  }

  void _skip() {
    switch (_step) {
      case 1:
        _city.clear();
      case 2:
        _date = null;
      case 3:
        _budget.clear();
      case 4:
        _guests.clear();
      case 5:
        _events.clear();
    }
    _next();
  }

  Future<void> _finish() async {
    setState(() => _busy = true);
    final ok = await runAction(context, () async {
      await supa.from('profiles').update({'full_name': _name.text.trim()}).eq('id', myId);
      await supa.from('customer_profiles').upsert({
        'user_id': myId,
        'wedding_city': nullIfEmpty(_city.text),
        'wedding_date': _date == null ? null : ymd(_date!),
        'budget': double.tryParse(_budget.text.trim()),
        'guest_count': int.tryParse(_guests.text.trim()),
        'planned_events': _events.toList(),
        'onboarding_completed': true,
      }, onConflict: 'user_id');
      if (_events.isNotEmpty) {
        await supa.rpc('create_wedding_plan', params: {'p_events': _events.toList()});
        if (_date != null) {
          // The main ceremony gets the wedding date by default.
          await supa
              .from('wedding_events')
              .update({'event_date': ymd(_date!)})
              .eq('customer_id', myId)
              .eq('name', 'Biye')
              .isFilter('event_date', null);
        }
      }
    });
    if (!mounted) return;
    setState(() => _busy = false);
    if (ok) gateRefresh.value++;
  }

  Widget _question(String title, String hint, Widget input) {
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Text(title, style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 8),
        Text(hint, style: const TextStyle(color: kMuted)),
        const SizedBox(height: 24),
        input,
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) return const Scaffold(body: LoadingView());
    return Scaffold(
      appBar: AppBar(
        leading: _step > 0 ? IconButton(icon: const Icon(Icons.arrow_back), onPressed: _back) : null,
        title: Text('Step ${_step + 1} of $_total'),
        actions: [
          if (_step > 0) TextButton(onPressed: _busy ? null : _skip, child: const Text('Skip')),
          if (_step == 0) TextButton(onPressed: () => supa.auth.signOut(), child: const Text('Sign out')),
        ],
      ),
      body: SafeArea(
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: ProgressBar((_step + 1) / _total, color: kGold),
          ),
          Expanded(
            child: PageView(
              controller: _pages,
              physics: const NeverScrollableScrollPhysics(),
              children: [
                _question('What is your name?', 'We will use it to personalise your planner.',
                    TextField(
                      controller: _name,
                      textCapitalization: TextCapitalization.words,
                      decoration: inputDeco('Your name', icon: Icons.person_outline),
                    )),
                _question('Where are you planning your wedding?', 'City or area, e.g. Kolkata, Howrah, Siliguri.',
                    TextField(
                      controller: _city,
                      textCapitalization: TextCapitalization.words,
                      decoration: inputDeco('City / location', icon: Icons.place_outlined),
                    )),
                _question('What is your expected wedding date?', 'You can change this any time.',
                    OutlinedButton.icon(
                      icon: const Icon(Icons.calendar_month),
                      label: Text(_date == null ? 'Choose date' : fmtDate(_date)),
                      onPressed: () async {
                        final d = await pickDate(context, initial: _date);
                        if (d != null) setState(() => _date = d);
                      },
                    )),
                _question('What is your estimated budget?', 'Total budget for all events, in rupees.',
                    TextField(
                      controller: _budget,
                      keyboardType: TextInputType.number,
                      decoration: inputDeco('Budget (₹)', icon: Icons.currency_rupee),
                    )),
                _question('How many guests are expected?', 'An approximate number is fine.',
                    TextField(
                      controller: _guests,
                      keyboardType: TextInputType.number,
                      decoration: inputDeco('Guests', icon: Icons.groups_outlined),
                    )),
                _question('Which wedding events are you planning?',
                    'Each event gets its own checklist. You can add more later.',
                    Wrap(spacing: 8, runSpacing: 8, children: [
                      for (final e in weddingEvents)
                        FilterChip(
                          label: Text(e),
                          selected: _events.contains(e),
                          selectedColor: kCream,
                          checkmarkColor: kMaroon,
                          onSelected: (v) => setState(() => v ? _events.add(e) : _events.remove(e)),
                        ),
                    ])),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(24),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _busy ? null : _next,
                child: _busy
                    ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : Text(_step == _total - 1 ? 'Start planning' : 'Continue'),
              ),
            ),
          ),
        ]),
      ),
    );
  }
}
