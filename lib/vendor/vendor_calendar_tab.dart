import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../core/theme.dart';
import '../core/utils.dart';
import '../core/widgets.dart';
import '../customer/bookings_screen.dart';
import 'vendor_overview_tab.dart';

class _CalData {
  final Map<DateTime, Map<String, dynamic>> availability;
  final Map<DateTime, List<Map<String, dynamic>>> bookings;
  _CalData(this.availability, this.bookings);
}

DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);

/// Availability calendar: confirmed bookings, pending requests and manual blocks.
class VendorCalendarTab extends StatefulWidget {
  const VendorCalendarTab({super.key});
  @override
  State<VendorCalendarTab> createState() => _VendorCalendarTabState();
}

class _VendorCalendarTabState extends State<VendorCalendarTab> {
  DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);

  Future<_CalData> _load() async {
    final from = DateTime(_month.year, _month.month - 1, 1);
    final to = DateTime(_month.year, _month.month + 2, 0);
    final avail = await supa
        .from('vendor_availability')
        .select()
        .eq('vendor_id', myId)
        .gte('date', ymd(from))
        .lte('date', ymd(to));
    final bookings = await supa
        .from('bookings')
        .select()
        .eq('vendor_id', myId)
        .inFilter('status', ['pending', 'accepted', 'completed'])
        .gte('event_date', ymd(from))
        .lte('event_date', ymd(to));
    final a = <DateTime, Map<String, dynamic>>{};
    for (final r in avail) {
      final d = DateTime.tryParse(str(r['date']));
      if (d != null) a[_day(d)] = r;
    }
    final b = <DateTime, List<Map<String, dynamic>>>{};
    for (final r in bookings) {
      final d = DateTime.tryParse(str(r['event_date']));
      if (d != null) b.putIfAbsent(_day(d), () => []).add(r);
    }
    return _CalData(a, b);
  }

  Future<void> _setDay(DateTime day, String? status) async {
    final ok = await runAction(context, () async {
      if (status == null) {
        await supa.from('vendor_availability').delete().eq('vendor_id', myId).eq('date', ymd(day));
      } else {
        await supa.from('vendor_availability').upsert(
          {'vendor_id': myId, 'date': ymd(day), 'status': status},
          onConflict: 'vendor_id,date',
        );
      }
    }, success: 'Calendar updated');
    if (ok) bumpData();
  }

  Future<void> _openDay(DateTime day, _CalData d) async {
    final avail = d.availability[day];
    final list = d.bookings[day] ?? const [];
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(DateFormat('EEEE, d MMMM yyyy').format(day), style: Theme.of(ctx).textTheme.titleLarge),
            const SizedBox(height: 4),
            Text(avail == null ? 'No status set' : 'Marked ${str(avail['status'])}', style: const TextStyle(color: kMuted)),
            const SizedBox(height: 12),
            if (list.isNotEmpty) ...[
              Text('Bookings', style: Theme.of(ctx).textTheme.titleSmall),
              for (final b in list)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text('${str(b['customer_name'], 'Customer')} · ${str(b['event_type'], 'Event')}'),
                  subtitle: Text(str(b['service_title'])),
                  trailing: StatusChip(str(b['status'])),
                  onTap: () => Navigator.pop(ctx, 'booking:${b['id']}'),
                ),
              const Divider(),
            ],
            if (!day.isBefore(today())) ...[
              Wrap(spacing: 8, runSpacing: 8, children: [
                ActionChip(
                  avatar: const Icon(Icons.check_circle_outline, size: 18, color: kSuccess),
                  label: const Text('Available'),
                  onPressed: () => Navigator.pop(ctx, 'available'),
                ),
                ActionChip(
                  avatar: const Icon(Icons.block, size: 18, color: Color(0xFFB3261E)),
                  label: const Text('Unavailable'),
                  onPressed: () => Navigator.pop(ctx, 'unavailable'),
                ),
                ActionChip(
                  avatar: const Icon(Icons.pause_circle_outline, size: 18, color: kGold),
                  label: const Text('Hold date'),
                  onPressed: () => Navigator.pop(ctx, 'held'),
                ),
                if (avail != null)
                  ActionChip(
                    avatar: const Icon(Icons.clear, size: 18),
                    label: const Text('Clear'),
                    onPressed: () => Navigator.pop(ctx, 'clear'),
                  ),
              ]),
              const SizedBox(height: 8),
              const Text(
                'Unavailable dates cannot be requested by customers. Holding a date is a private reminder and does not block requests.',
                style: TextStyle(fontSize: 12, color: kMuted),
              ),
            ],
          ]),
        ),
      ),
    );
    if (action == null || !mounted) return;
    if (action.startsWith('booking:')) {
      Navigator.push(context,
          MaterialPageRoute(builder: (_) => BookingDetailScreen(bookingId: action.substring(8), asVendor: true)));
      return;
    }
    await _setDay(day, action == 'clear' ? null : action);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Availability')),
      body: Loader<_CalData>(
        key: ValueKey(_month),
        load: _load,
        builder: (context, d, reload) {
          final first = DateTime(_month.year, _month.month, 1);
          final daysInMonth = DateTime(_month.year, _month.month + 1, 0).day;
          final leading = first.weekday % 7; // Sunday first
          final cells = leading + daysInMonth;
          final rows = (cells / 7).ceil();
          final monthBookings = d.bookings.entries
              .where((e) => e.key.month == _month.month && e.key.year == _month.year)
              .expand((e) => e.value)
              .toList()
            ..sort((a, b) => str(a['event_date']).compareTo(str(b['event_date'])));

          return RefreshIndicator(
            onRefresh: reload,
            child: ListView(padding: const EdgeInsets.all(16), children: [
              Row(children: [
                IconButton(
                  icon: const Icon(Icons.chevron_left),
                  onPressed: () => setState(() => _month = DateTime(_month.year, _month.month - 1)),
                ),
                Expanded(
                  child: Text(DateFormat('MMMM yyyy').format(_month),
                      textAlign: TextAlign.center, style: Theme.of(context).textTheme.titleLarge),
                ),
                IconButton(
                  icon: const Icon(Icons.chevron_right),
                  onPressed: () => setState(() => _month = DateTime(_month.year, _month.month + 1)),
                ),
              ]),
              const SizedBox(height: 8),
              AppCard(
                padding: const EdgeInsets.all(8),
                child: Column(children: [
                  Row(children: [
                    for (final w in const ['S', 'M', 'T', 'W', 'T', 'F', 'S'])
                      Expanded(
                        child: Center(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 6),
                            child: Text(w, style: const TextStyle(color: kMuted, fontWeight: FontWeight.w600)),
                          ),
                        ),
                      ),
                  ]),
                  for (var r = 0; r < rows; r++)
                    Row(children: [
                      for (var c = 0; c < 7; c++) _cell(r * 7 + c - leading + 1, daysInMonth, d),
                    ]),
                ]),
              ),
              const SizedBox(height: 12),
              const Wrap(spacing: 14, runSpacing: 6, children: [
                _Legend(color: kMaroon, label: 'Confirmed'),
                _Legend(color: kWarning, label: 'Pending request'),
                _Legend(color: Color(0xFFB3261E), label: 'Unavailable'),
                _Legend(color: kGold, label: 'On hold'),
                _Legend(color: kSuccess, label: 'Available'),
              ]),
              const SizedBox(height: 16),
              Text('This month', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              if (monthBookings.isEmpty)
                const Text('No bookings this month.', style: TextStyle(color: kMuted)),
              for (final b in monthBookings)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: CircleAvatar(
                    backgroundColor: kCream,
                    child: Text(DateFormat('d').format(DateTime.parse(str(b['event_date']))),
                        style: const TextStyle(color: kMaroon, fontWeight: FontWeight.w700)),
                  ),
                  title: Text('${str(b['customer_name'], 'Customer')} · ${str(b['event_type'], 'Event')}'),
                  subtitle: Text(str(b['service_title'])),
                  trailing: StatusChip(str(b['status'])),
                  onTap: () => openVendorBooking(context, b['id'] as String),
                ),
            ]),
          );
        },
      ),
    );
  }

  Widget _cell(int dayNum, int daysInMonth, _CalData d) {
    if (dayNum < 1 || dayNum > daysInMonth) return const Expanded(child: SizedBox(height: 48));
    final day = DateTime(_month.year, _month.month, dayNum);
    final avail = str(d.availability[day]?['status']);
    final list = d.bookings[day] ?? const [];
    final confirmed = list.any((b) => b['status'] == 'accepted' || b['status'] == 'completed');
    final pending = list.any((b) => b['status'] == 'pending');
    final isToday = day == today();
    final past = day.isBefore(today());

    Color? bg;
    Color fg = past ? kMuted : kInk;
    if (confirmed) {
      bg = kMaroon;
      fg = Colors.white;
    } else if (avail == 'unavailable') {
      bg = const Color(0xFFB3261E).withAlpha(40);
    } else if (avail == 'held') {
      bg = kGold.withAlpha(70);
    } else if (avail == 'available') {
      bg = kSuccess.withAlpha(35);
    }

    return Expanded(
      child: GestureDetector(
        onTap: () => _openDay(day, d),
        child: Container(
          height: 48,
          margin: const EdgeInsets.all(2),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(10),
            border: isToday ? Border.all(color: kMaroon, width: 1.5) : null,
          ),
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Text('$dayNum', style: TextStyle(color: fg, fontWeight: isToday ? FontWeight.w700 : FontWeight.w500)),
            if (pending)
              Container(
                margin: const EdgeInsets.only(top: 2),
                width: 6,
                height: 6,
                decoration: const BoxDecoration(color: kWarning, shape: BoxShape.circle),
              ),
          ]),
        ),
      ),
    );
  }
}

class _Legend extends StatelessWidget {
  final Color color;
  final String label;
  const _Legend({required this.color, required this.label});
  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 12, height: 12, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(3))),
        const SizedBox(width: 4),
        Text(label, style: const TextStyle(fontSize: 12)),
      ]);
}
