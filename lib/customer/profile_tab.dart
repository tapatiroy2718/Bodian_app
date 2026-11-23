import 'package:flutter/material.dart';

import '../core/data.dart';
import '../core/theme.dart';
import '../core/utils.dart';
import '../core/widgets.dart';
import '../shared/account.dart';
import '../shared/notifications_screen.dart';
import 'bookings_screen.dart';

class ProfileTab extends StatelessWidget {
  const ProfileTab({super.key});

  Future<(Map<String, dynamic>, Map<String, dynamic>)> _load() async {
    return (await fetchMyProfile(), await fetchCustomerProfile());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Profile')),
      body: Loader<(Map<String, dynamic>, Map<String, dynamic>)>(
        load: _load,
        builder: (context, d, reload) {
          final p = d.$1;
          final c = d.$2;
          return RefreshIndicator(
            onRefresh: reload,
            child: ListView(padding: const EdgeInsets.all(16), children: [
              AppCard(
                child: Row(children: [
                  AvatarPicker(url: p['avatar_url'] as String?, name: str(p['full_name'])),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(str(p['full_name'], 'Your name'), style: Theme.of(context).textTheme.titleLarge),
                      Text(str(p['email']), style: const TextStyle(color: kMuted)),
                      if (str(p['phone']).isNotEmpty) Text(str(p['phone']), style: const TextStyle(color: kMuted)),
                    ]),
                  ),
                ]),
              ),
              const SizedBox(height: 12),
              AppCard(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Text('Wedding details', style: Theme.of(context).textTheme.titleMedium),
                    const Spacer(),
                    TextButton(
                      onPressed: () => Navigator.push(
                          context, MaterialPageRoute(builder: (_) => WeddingDetailsScreen(customer: c))),
                      child: const Text('Edit'),
                    ),
                  ]),
                  InfoRow(Icons.calendar_today, 'Date', fmtDate(c['wedding_date'])),
                  InfoRow(Icons.place_outlined, 'Location', str(c['wedding_city'], 'Not set')),
                  InfoRow(Icons.currency_rupee, 'Budget', c['budget'] == null ? 'Not set' : money(c['budget'])),
                  InfoRow(Icons.groups_outlined, 'Guests', c['guest_count'] == null ? 'Not set' : '${toI(c['guest_count'])}'),
                ]),
              ),
              const SizedBox(height: 12),
              AppCard(
                padding: EdgeInsets.zero,
                child: Column(children: [
                  _tile(context, Icons.person_outline, 'Edit profile',
                      () => Navigator.push(context, MaterialPageRoute(builder: (_) => EditProfileScreen(profile: p)))),
                  _tile(context, Icons.receipt_long, 'My bookings',
                      () => Navigator.push(context, MaterialPageRoute(builder: (_) => const MyBookingsScreen()))),
                  _tile(
                      context,
                      Icons.notifications_outlined,
                      'Notifications',
                      () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => NotificationsScreen(
                                onOpenBooking: (ctx, id) => Navigator.push(
                                    ctx, MaterialPageRoute(builder: (_) => BookingDetailScreen(bookingId: id))),
                              ),
                            ),
                          )),
                ]),
              ),
              const SizedBox(height: 12),
              const AccountSection(),
            ]),
          );
        },
      ),
    );
  }

  Widget _tile(BuildContext context, IconData icon, String title, VoidCallback onTap) => ListTile(
        leading: Icon(icon, color: kMaroon),
        title: Text(title),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      );
}

class WeddingDetailsScreen extends StatefulWidget {
  final Map<String, dynamic> customer;
  const WeddingDetailsScreen({super.key, required this.customer});
  @override
  State<WeddingDetailsScreen> createState() => _WeddingDetailsScreenState();
}

class _WeddingDetailsScreenState extends State<WeddingDetailsScreen> {
  late final _city = TextEditingController(text: str(widget.customer['wedding_city']));
  late final _location = TextEditingController(text: str(widget.customer['wedding_location']));
  late final _budget = TextEditingController(
      text: widget.customer['budget'] == null ? '' : toD(widget.customer['budget']).toStringAsFixed(0));
  late final _guests = TextEditingController(
      text: widget.customer['guest_count'] == null ? '' : toI(widget.customer['guest_count']).toString());
  late DateTime? _date = parseDate(widget.customer['wedding_date']);
  bool _busy = false;

  @override
  void dispose() {
    for (final c in [_city, _location, _budget, _guests]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _busy = true);
    final ok = await runAction(context, () async {
      await supa.from('customer_profiles').update({
        'wedding_city': nullIfEmpty(_city.text),
        'wedding_location': nullIfEmpty(_location.text),
        'wedding_date': _date == null ? null : ymd(_date!),
        'budget': double.tryParse(_budget.text.trim()),
        'guest_count': int.tryParse(_guests.text.trim()),
      }).eq('user_id', myId);
    }, success: 'Wedding details saved');
    if (!mounted) return;
    setState(() => _busy = false);
    if (ok) {
      bumpData();
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Wedding details')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        OutlinedButton.icon(
          icon: const Icon(Icons.calendar_month),
          label: Text(_date == null ? 'Choose wedding date' : 'Wedding date: ${fmtDate(_date)}'),
          onPressed: () async {
            final d = await pickDate(context, initial: _date, first: DateTime(2020));
            if (d != null) setState(() => _date = d);
          },
        ),
        if (_date != null) TextButton(onPressed: () => setState(() => _date = null), child: const Text('Clear date')),
        const SizedBox(height: 12),
        TextField(controller: _city, decoration: inputDeco('City', icon: Icons.location_city)),
        const SizedBox(height: 12),
        TextField(controller: _location, decoration: inputDeco('Area / venue location', icon: Icons.place_outlined)),
        const SizedBox(height: 12),
        TextField(
            controller: _budget,
            keyboardType: TextInputType.number,
            decoration: inputDeco('Budget (₹)', icon: Icons.currency_rupee)),
        const SizedBox(height: 12),
        TextField(
            controller: _guests,
            keyboardType: TextInputType.number,
            decoration: inputDeco('Expected guests', icon: Icons.groups_outlined)),
        const SizedBox(height: 20),
        ElevatedButton(onPressed: _busy ? null : _save, child: const Text('Save')),
      ]),
    );
  }
}
