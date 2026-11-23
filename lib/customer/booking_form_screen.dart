import 'package:flutter/material.dart';

import '../core/constants.dart';
import '../core/data.dart';
import '../core/theme.dart';
import '../core/utils.dart';
import '../core/widgets.dart';
import 'bookings_screen.dart';

class BookingFormScreen extends StatefulWidget {
  final Map<String, dynamic> service;
  final Map<DateTime, String> unavailable;
  final Map<String, dynamic>? initialPackage;
  const BookingFormScreen({super.key, required this.service, required this.unavailable, this.initialPackage});
  @override
  State<BookingFormScreen> createState() => _BookingFormScreenState();
}

class _BookingFormScreenState extends State<BookingFormScreen> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _guests = TextEditingController();
  final _requirements = TextEditingController();
  final _message = TextEditingController();
  String? _packageId;
  String? _eventType;
  DateTime? _date;
  List<String> _eventOptions = [...weddingEvents];
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _packageId = widget.initialPackage?['id'] as String?;
    _prefill();
  }

  Future<void> _prefill() async {
    try {
      final p = await fetchMyProfile();
      final c = await fetchCustomerProfile();
      final events = await supa.from('wedding_events').select('name, event_date').eq('customer_id', myId).order('sort');
      if (!mounted) return;
      setState(() {
        _name.text = str(p['full_name']);
        _phone.text = str(p['phone']);
        if (c['guest_count'] != null) _guests.text = toI(c['guest_count']).toString();
        final names = events.map((e) => str(e['name'])).where((n) => n.isNotEmpty).toList();
        _eventOptions = {...names, ...weddingEvents}.toList();
        if (names.isNotEmpty) {
          _eventType = names.contains('Biye') ? 'Biye' : names.first;
          final ev = events.firstWhere((e) => e['name'] == _eventType, orElse: () => <String, dynamic>{});
          final d = parseDate(ev['event_date']) ?? parseDate(c['wedding_date']);
          if (d != null && _selectable(d)) _date = DateTime(d.year, d.month, d.day);
        }
      });
    } catch (_) {}
  }

  @override
  void dispose() {
    for (final c in [_name, _phone, _guests, _requirements, _message]) {
      c.dispose();
    }
    super.dispose();
  }

  bool _selectable(DateTime d) {
    final key = DateTime(d.year, d.month, d.day);
    return !key.isBefore(today()) && !widget.unavailable.containsKey(key);
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    if (_eventType == null) {
      showSnack(context, 'Please choose the event.', error: true);
      return;
    }
    if (_date == null) {
      showSnack(context, 'Please choose the event date.', error: true);
      return;
    }
    setState(() => _busy = true);
    String? bookingId;
    final ok = await runAction(context, () async {
      final res = await supa.rpc('create_booking', params: {
        'p_service_id': widget.service['id'],
        'p_event_date': ymd(_date!),
        'p_package_id': _packageId,
        'p_event_type': _eventType,
        'p_guest_count': int.tryParse(_guests.text.trim()),
        'p_customer_name': _name.text.trim(),
        'p_customer_phone': _phone.text.trim(),
        'p_requirements': nullIfEmpty(_requirements.text),
        'p_message': nullIfEmpty(_message.text),
      });
      bookingId = res?.toString();
    });
    if (!mounted) return;
    setState(() => _busy = false);
    if (!ok) return;
    bumpData();
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.check_circle, color: kSuccess, size: 48),
        title: const Text('Request sent'),
        content: const Text('The vendor has been notified. You will get a notification when they accept or decline.'),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              if (bookingId != null) {
                Navigator.pushReplacement(
                    context, MaterialPageRoute(builder: (_) => BookingDetailScreen(bookingId: bookingId!)));
              }
            },
            child: const Text('View booking'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              Navigator.pop(context);
            },
            child: const Text('Done'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.service;
    final v = asMap(s['vendor_profiles']);
    final packages = activePackages(s);
    return Scaffold(
      appBar: AppBar(title: const Text('Booking request')),
      body: Form(
        key: _form,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            AppCard(
              color: kCream,
              child: Row(children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: NetImage(serviceCover(s), width: 56, height: 56),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(str(s['title']), style: const TextStyle(fontWeight: FontWeight.w600)),
                    Text(str(v['business_name']), style: const TextStyle(color: kMuted)),
                  ]),
                ),
              ]),
            ),
            const SizedBox(height: 16),
            SelectField<String>(
              label: 'Event',
              icon: Icons.celebration_outlined,
              value: _eventType,
              options: [for (final e in _eventOptions) (e, e)],
              onChanged: (v) => setState(() => _eventType = v),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              icon: const Icon(Icons.calendar_month),
              label: Text(_date == null ? 'Choose event date' : 'Event date: ${fmtDate(_date)}'),
              onPressed: () async {
                final d = await pickDate(context, initial: _date, selectable: _selectable);
                if (d != null) setState(() => _date = d);
              },
            ),
            if (widget.unavailable.isNotEmpty)
              const Padding(
                padding: EdgeInsets.only(top: 4, left: 4),
                child: Text('Dates already booked are greyed out.', style: TextStyle(fontSize: 12, color: kMuted)),
              ),
            const SizedBox(height: 12),
            SelectField<String?>(
              label: 'Package',
              icon: Icons.inventory_2_outlined,
              value: packages.any((p) => p['id'] == _packageId) ? _packageId : null,
              placeholder: 'No package – ask for a quote',
              options: [
                (null, 'No package – ask for a quote'),
                for (final p in packages) (p['id'] as String?, '${str(p['name'])} · ${money(p['price'])}'),
              ],
              onChanged: (v) => setState(() => _packageId = v),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _guests,
              keyboardType: TextInputType.number,
              decoration: inputDeco('Number of guests', icon: Icons.groups_outlined),
              validator: (v) {
                if ((v ?? '').trim().isEmpty) return null;
                final n = int.tryParse(v!.trim());
                return (n == null || n < 0) ? 'Enter a valid number' : null;
              },
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _name,
              textCapitalization: TextCapitalization.words,
              decoration: inputDeco('Your name', icon: Icons.person_outline),
              validator: (v) => (v ?? '').trim().isEmpty ? 'Enter your name' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _phone,
              keyboardType: TextInputType.phone,
              decoration: inputDeco('Contact number', icon: Icons.phone_outlined,
                  helper: 'Shared with this vendor so they can reach you'),
              validator: (v) =>
                  (v ?? '').replaceAll(RegExp(r'[^0-9]'), '').length < 10 ? 'Enter a valid phone number' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _requirements,
              maxLines: 3,
              decoration: inputDeco('Requirements', hint: 'e.g. AC hall, 300 guests, Bengali menu, evening event'),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _message,
              maxLines: 3,
              decoration: inputDeco('Message to vendor (optional)'),
            ),
            const SizedBox(height: 8),
            const Text(
              'This is a booking request, not a payment. The vendor will confirm availability and pricing with you.',
              style: TextStyle(fontSize: 12, color: kMuted),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _busy ? null : _submit,
              child: _busy
                  ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Text('Send request'),
            ),
          ],
        ),
      ),
    );
  }
}
