import 'package:flutter/material.dart';

import '../core/theme.dart';
import '../core/utils.dart';
import '../core/widgets.dart';

Stream<List<Map<String, dynamic>>> _notificationStream() => supa
    .from('notifications')
    .stream(primaryKey: ['id'])
    .eq('user_id', myId)
    .order('created_at', ascending: false)
    .limit(100);

/// App-bar bell with a live unread badge.
class NotificationBell extends StatefulWidget {
  final VoidCallback onOpen;
  final Color color;
  const NotificationBell({super.key, required this.onOpen, this.color = kMaroon});
  @override
  State<NotificationBell> createState() => _NotificationBellState();
}

class _NotificationBellState extends State<NotificationBell> {
  late final Stream<List<Map<String, dynamic>>> _stream = _notificationStream();

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: _stream,
      builder: (context, snap) {
        final unread = (snap.data ?? const []).where((n) => n['is_read'] != true).length;
        return IconButton(
          tooltip: 'Notifications',
          onPressed: widget.onOpen,
          icon: Badge(
            isLabelVisible: unread > 0,
            label: Text(unread > 99 ? '99+' : '$unread'),
            backgroundColor: kRoyalRed,
            child: Icon(Icons.notifications_outlined, color: widget.color),
          ),
        );
      },
    );
  }
}

class NotificationsScreen extends StatefulWidget {
  /// Called when a notification linked to a booking is tapped.
  final void Function(BuildContext context, String bookingId)? onOpenBooking;
  const NotificationsScreen({super.key, this.onOpenBooking});
  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  late final Stream<List<Map<String, dynamic>>> _stream = _notificationStream();

  Future<void> _markAllRead() async {
    await runAction(context, () async {
      await supa.from('notifications').update({'is_read': true}).eq('user_id', myId).eq('is_read', false);
    });
  }

  Future<void> _open(Map<String, dynamic> n) async {
    if (n['is_read'] != true) {
      try {
        await supa.from('notifications').update({'is_read': true}).eq('id', n['id'] as String);
      } catch (_) {}
    }
    final bookingId = n['booking_id'] as String?;
    if (bookingId != null && widget.onOpenBooking != null && mounted) {
      widget.onOpenBooking!(context, bookingId);
    }
  }

  IconData _icon(String type) => switch (type) {
        'booking_new' => Icons.mark_email_unread_outlined,
        'booking_accepted' => Icons.check_circle_outline,
        'booking_rejected' => Icons.cancel_outlined,
        'booking_cancelled' => Icons.event_busy,
        'booking_completed' => Icons.task_alt,
        'review_new' => Icons.star_outline,
        'verification' => Icons.verified_outlined,
        _ => Icons.notifications_none,
      };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Notifications'),
        actions: [TextButton(onPressed: _markAllRead, child: const Text('Mark all read'))],
      ),
      body: StreamBuilder<List<Map<String, dynamic>>>(
        stream: _stream,
        builder: (context, snap) {
          if (snap.hasError) return ErrorView(message: friendlyError(snap.error));
          if (!snap.hasData) return const LoadingView();
          final items = snap.data!;
          if (items.isEmpty) {
            return const Center(
              child: EmptyView(
                icon: Icons.notifications_none,
                title: 'No notifications yet',
                subtitle: 'Booking updates and messages will appear here.',
              ),
            );
          }
          return ListView.separated(
            itemCount: items.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, i) {
              final n = items[i];
              final unread = n['is_read'] != true;
              return ListTile(
                tileColor: unread ? kCream.withAlpha(120) : null,
                leading: Icon(_icon(str(n['type'])), color: kMaroon),
                title: Text(str(n['title']), style: TextStyle(fontWeight: unread ? FontWeight.w700 : FontWeight.w500)),
                subtitle: Text(str(n['body'])),
                trailing: Text(timeAgo(n['created_at']), style: const TextStyle(fontSize: 11, color: kMuted)),
                onTap: () => _open(n),
              );
            },
          );
        },
      ),
    );
  }
}
