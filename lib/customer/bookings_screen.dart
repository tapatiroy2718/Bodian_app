import 'package:flutter/material.dart';

import '../core/constants.dart';
import '../core/theme.dart';
import '../core/utils.dart';
import '../core/widgets.dart';

const bookingDetailSelect = '*, '
    'vendor_profiles!bookings_vendor_id_fkey(business_name, phone, whatsapp, city, logo_url), '
    'reviews(id, rating, comment, created_at), '
    'booking_status_history(*)';

/// Customer: list of their booking requests.
class MyBookingsScreen extends StatelessWidget {
  const MyBookingsScreen({super.key});

  Future<List<Map<String, dynamic>>> _load() async {
    return await supa
        .from('bookings')
        .select('*, vendor_profiles!bookings_vendor_id_fkey(business_name, logo_url)')
        .eq('customer_id', myId)
        .order('created_at', ascending: false);
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('My bookings'),
          bottom: const TabBar(
            labelColor: kMaroon,
            indicatorColor: kMaroon,
            tabs: [Tab(text: 'Active'), Tab(text: 'Completed'), Tab(text: 'Closed')],
          ),
        ),
        body: Loader<List<Map<String, dynamic>>>(
          load: _load,
          builder: (context, all, reload) {
            List<Map<String, dynamic>> by(List<String> s) => all.where((b) => s.contains(b['status'])).toList();
            return TabBarView(children: [
              _BookingList(items: by(['pending', 'accepted']), reload: reload, empty: 'No active booking requests'),
              _BookingList(items: by(['completed']), reload: reload, empty: 'No completed bookings yet'),
              _BookingList(items: by(['rejected', 'cancelled']), reload: reload, empty: 'Nothing here'),
            ]);
          },
        ),
      ),
    );
  }
}

class _BookingList extends StatelessWidget {
  final List<Map<String, dynamic>> items;
  final Future<void> Function() reload;
  final String empty;
  const _BookingList({required this.items, required this.reload, required this.empty});
  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: reload,
      child: items.isEmpty
          ? ListView(children: [EmptyView(icon: Icons.receipt_long, title: empty, subtitle: 'Find vendors in Explore and send a request.')])
          : ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: items.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (context, i) => BookingCard(
                booking: items[i],
                title: str(items[i]['service_title'], 'Service'),
                subtitle: str(asMap(items[i]['vendor_profiles'])['business_name']),
                onTap: () => Navigator.push(context,
                    MaterialPageRoute(builder: (_) => BookingDetailScreen(bookingId: items[i]['id'] as String))),
              ),
            ),
    );
  }
}

class BookingCard extends StatelessWidget {
  final Map<String, dynamic> booking;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  const BookingCard({super.key, required this.booking, required this.title, required this.subtitle, required this.onTap});
  @override
  Widget build(BuildContext context) {
    return AppCard(
      onTap: onTap,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text(title, style: Theme.of(context).textTheme.titleMedium, maxLines: 1, overflow: TextOverflow.ellipsis)),
          StatusChip(str(booking['status'])),
        ]),
        const SizedBox(height: 4),
        Text(subtitle, style: const TextStyle(color: kMuted)),
        const SizedBox(height: 8),
        Wrap(spacing: 14, runSpacing: 4, children: [
          _meta(Icons.celebration_outlined, str(booking['event_type'], 'Event')),
          _meta(Icons.calendar_today, fmtDate(booking['event_date'])),
          if (booking['guest_count'] != null) _meta(Icons.groups_outlined, '${toI(booking['guest_count'])} guests'),
          if (str(booking['package_name']).isNotEmpty) _meta(Icons.inventory_2_outlined, str(booking['package_name'])),
        ]),
        const SizedBox(height: 6),
        Text('Requested ${timeAgo(booking['created_at'])}', style: const TextStyle(fontSize: 11, color: kMuted)),
      ]),
    );
  }

  Widget _meta(IconData icon, String text) => Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 14, color: kMaroon),
        const SizedBox(width: 4),
        Text(text, style: const TextStyle(fontSize: 12)),
      ]);
}

/// Booking detail for both sides. Vendors see accept / reject / complete actions,
/// customers see cancel / review actions.
class BookingDetailScreen extends StatelessWidget {
  final String bookingId;
  final bool asVendor;
  const BookingDetailScreen({super.key, required this.bookingId, this.asVendor = false});

  Future<Map<String, dynamic>> _load() async {
    final b = await supa.from('bookings').select(bookingDetailSelect).eq('id', bookingId).maybeSingle();
    if (b == null) throw Exception('Booking not found.');
    return b;
  }

  Future<void> _setStatus(BuildContext context, String status, {bool needReason = false, String? title}) async {
    String? reason;
    if (needReason || status == 'cancelled') {
      reason = await promptText(context, title ?? 'Reason', required: needReason || asVendor);
      if (reason == null) return;
    } else {
      final label = bookingStatusLabels[status] ?? status;
      final ok = await confirmDialog(context, 'Mark as ${label.toLowerCase()}?', 'The other party will be notified.',
          confirm: 'Yes, continue');
      if (!ok) return;
    }
    if (!context.mounted) return;
    final ok = await runAction(context, () async {
      await supa.rpc('update_booking_status', params: {
        'p_booking_id': bookingId,
        'p_status': status,
        'p_reason': nullIfEmpty(reason),
      });
    }, success: 'Booking updated');
    if (ok) bumpData();
  }

  Future<void> _review(BuildContext context) async {
    final result = await showModalBottomSheet<(int, String)>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => const _ReviewSheet(),
    );
    if (result == null || !context.mounted) return;
    final ok = await runAction(context, () async {
      await supa.rpc('submit_review', params: {'p_booking_id': bookingId, 'p_rating': result.$1, 'p_comment': result.$2});
    }, success: 'Thank you for your review!');
    if (ok) bumpData();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Booking details')),
      body: Loader<Map<String, dynamic>>(
        load: _load,
        builder: (context, b, reload) {
          final status = str(b['status']);
          final vendor = asMap(b['vendor_profiles']);
          final review = asMapOrNull(b['reviews']);
          final history = asList(b['booking_status_history'])
            ..sort((x, y) => str(x['created_at']).compareTo(str(y['created_at'])));
          final eventDate = parseDate(b['event_date']);
          final eventPassed = eventDate != null && eventDate.isBefore(today());

          return RefreshIndicator(
            onRefresh: reload,
            child: ListView(padding: const EdgeInsets.all(16), children: [
              AppCard(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Expanded(child: Text(str(b['service_title'], 'Service'), style: Theme.of(context).textTheme.titleLarge)),
                    StatusChip(status),
                  ]),
                  const SizedBox(height: 4),
                  Text(asVendor ? 'Request from ${str(b['customer_name'], 'customer')}' : str(vendor['business_name']),
                      style: const TextStyle(color: kMuted)),
                  if (str(b['status_reason']).isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(color: kCream, borderRadius: BorderRadius.circular(12)),
                      child: Text('Reason: ${str(b['status_reason'])}'),
                    ),
                  ],
                ]),
              ),
              const SizedBox(height: 12),
              AppCard(
                child: Column(children: [
                  InfoRow(Icons.celebration_outlined, 'Event', str(b['event_type'], '—')),
                  InfoRow(Icons.calendar_today, 'Event date', fmtDate(b['event_date'])),
                  InfoRow(Icons.groups_outlined, 'Guests', b['guest_count'] == null ? '—' : '${toI(b['guest_count'])}'),
                  InfoRow(Icons.inventory_2_outlined, 'Package',
                      str(b['package_name']).isEmpty ? 'Quote requested' : '${str(b['package_name'])} · ${money(b['package_price'])}'),
                  InfoRow(Icons.person_outline, 'Customer', str(b['customer_name'], '—')),
                  if (asVendor) InfoRow(Icons.phone_outlined, 'Phone', str(b['customer_phone'], '—')),
                  InfoRow(Icons.schedule, 'Requested on', fmtDateTime(b['created_at'])),
                ]),
              ),
              if (str(b['requirements']).isNotEmpty || str(b['message']).isNotEmpty) ...[
                const SizedBox(height: 12),
                AppCard(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    if (str(b['requirements']).isNotEmpty) ...[
                      const Text('Requirements', style: TextStyle(fontWeight: FontWeight.w600)),
                      const SizedBox(height: 4),
                      Text(str(b['requirements'])),
                      const SizedBox(height: 10),
                    ],
                    if (str(b['message']).isNotEmpty) ...[
                      const Text('Message', style: TextStyle(fontWeight: FontWeight.w600)),
                      const SizedBox(height: 4),
                      Text(str(b['message'])),
                    ],
                  ]),
                ),
              ],
              const SizedBox(height: 16),
              // Contact
              Row(children: [
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.call_outlined),
                    label: const Text('Call'),
                    onPressed: () => callPhone(context, asVendor ? b['customer_phone'] as String? : vendor['phone'] as String?),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.chat_outlined),
                    label: const Text('WhatsApp'),
                    onPressed: () => openWhatsApp(
                      context,
                      asVendor ? b['customer_phone'] as String? : str(vendor['whatsapp'], str(vendor['phone'])),
                      text: asVendor
                          ? 'Hello ${str(b['customer_name'])}, this is ${str(b['service_title'])} regarding your Bodiana booking request for ${fmtDate(b['event_date'])}.'
                          : 'Hello, I sent a Bodiana booking request for ${str(b['service_title'])} on ${fmtDate(b['event_date'])}.',
                    ),
                  ),
                ),
              ]),
              const SizedBox(height: 16),
              // Actions
              if (asVendor && status == 'pending') ...[
                ElevatedButton.icon(
                  icon: const Icon(Icons.check),
                  label: const Text('Accept booking'),
                  onPressed: () => _setStatus(context, 'accepted'),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  icon: const Icon(Icons.close),
                  label: const Text('Reject with reason'),
                  onPressed: () => _setStatus(context, 'rejected', needReason: true, title: 'Why are you declining?'),
                ),
              ],
              if (asVendor && status == 'accepted') ...[
                ElevatedButton.icon(
                  icon: const Icon(Icons.task_alt),
                  label: const Text('Mark completed'),
                  onPressed: () => _setStatus(context, 'completed'),
                ),
                if (!eventPassed) const Padding(
                  padding: EdgeInsets.only(top: 4),
                  child: Text('Usually marked after the event has taken place.', style: TextStyle(fontSize: 12, color: kMuted)),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  icon: const Icon(Icons.event_busy),
                  label: const Text('Cancel with reason'),
                  onPressed: () => _setStatus(context, 'cancelled', needReason: true, title: 'Why are you cancelling?'),
                ),
              ],
              if (!asVendor && (status == 'pending' || status == 'accepted'))
                OutlinedButton.icon(
                  icon: const Icon(Icons.event_busy),
                  label: Text(status == 'pending' ? 'Cancel request' : 'Cancel booking'),
                  onPressed: () => _setStatus(context, 'cancelled', title: 'Reason for cancelling (optional)'),
                ),
              if (!asVendor && status == 'completed' && review == null)
                ElevatedButton.icon(
                  icon: const Icon(Icons.star_outline),
                  label: const Text('Write a review'),
                  onPressed: () => _review(context),
                ),
              if (review != null) ...[
                const SizedBox(height: 8),
                AppCard(
                  color: kCream,
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Text(asVendor ? 'Customer review' : 'Your review', style: const TextStyle(fontWeight: FontWeight.w600)),
                      const Spacer(),
                      for (var i = 1; i <= 5; i++)
                        Icon(i <= toI(review['rating']) ? Icons.star_rounded : Icons.star_outline_rounded, size: 18, color: kGold),
                    ]),
                    if (str(review['comment']).isNotEmpty) ...[const SizedBox(height: 6), Text(str(review['comment']))],
                  ]),
                ),
              ],
              const SizedBox(height: 20),
              Text('Status history', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              for (final h in history)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Container(
                      margin: const EdgeInsets.only(top: 4),
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(color: StatusChip.colorFor(str(h['to_status'])), shape: BoxShape.circle),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(
                          '${bookingStatusLabels[str(h['to_status'])] ?? str(h['to_status'])}'
                          '${str(h['actor_role']).isEmpty ? '' : ' by ${str(h['actor_role'])}'}',
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        if (str(h['reason']).isNotEmpty) Text(str(h['reason'])),
                        Text(fmtDateTime(h['created_at']), style: const TextStyle(fontSize: 11, color: kMuted)),
                      ]),
                    ),
                  ]),
                ),
            ]),
          );
        },
      ),
    );
  }
}

class _ReviewSheet extends StatefulWidget {
  const _ReviewSheet();
  @override
  State<_ReviewSheet> createState() => _ReviewSheetState();
}

class _ReviewSheetState extends State<_ReviewSheet> {
  int _rating = 5;
  final _comment = TextEditingController();

  @override
  void dispose() {
    _comment.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.of(context).viewInsets.bottom),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text('Rate your experience', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 12),
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          for (var i = 1; i <= 5; i++)
            IconButton(
              iconSize: 36,
              onPressed: () => setState(() => _rating = i),
              icon: Icon(i <= _rating ? Icons.star_rounded : Icons.star_outline_rounded, color: kGold),
            ),
        ]),
        const SizedBox(height: 8),
        TextField(controller: _comment, maxLines: 4, decoration: inputDeco('Tell others about the service (optional)')),
        const SizedBox(height: 16),
        FilledButton(
          onPressed: () => Navigator.pop(context, (_rating, _comment.text.trim())),
          child: const Text('Submit review'),
        ),
      ]),
    );
  }
}
