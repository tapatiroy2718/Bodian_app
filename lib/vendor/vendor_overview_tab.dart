import 'package:flutter/material.dart';

import '../core/theme.dart';
import '../core/utils.dart';
import '../core/widgets.dart';
import '../customer/bookings_screen.dart';
import '../shared/notifications_screen.dart';
import 'vendor_more_tab.dart';
import 'vendor_shell.dart';

class _Overview {
  final Map<String, dynamic> vendor;
  final List<Map<String, dynamic>> bookings;
  final int services;
  final int documents;
  _Overview(this.vendor, this.bookings, this.services, this.documents);
}

Future<Map<String, dynamic>> fetchMyVendor() async {
  final v = await supa.from('vendor_profiles').select().eq('id', myId).maybeSingle();
  if (v == null) throw Exception('Business profile not found.');
  return v;
}

/// Simple profile completeness score shown on the dashboard.
(int, List<String>) profileCompletion(Map<String, dynamic> v, int services, int documents) {
  final checks = <String, bool>{
    'Add a logo': str(v['logo_url']).isNotEmpty,
    'Add a cover photo': str(v['cover_url']).isNotEmpty,
    'Write a business description': str(v['description']).length >= 30,
    'Add your business address': str(v['address']).isNotEmpty,
    'Add a contact number': str(v['phone']).isNotEmpty,
    'Add at least 3 portfolio photos': asStrings(v['gallery']).length >= 3,
    'Create your first service': services > 0,
    'Upload a verification document': documents > 0,
  };
  final done = checks.values.where((e) => e).length;
  final missing = checks.entries.where((e) => !e.value).map((e) => e.key).toList();
  return ((done * 100 / checks.length).round(), missing);
}

void openVendorBooking(BuildContext context, String id) {
  Navigator.push(context, MaterialPageRoute(builder: (_) => BookingDetailScreen(bookingId: id, asVendor: true)));
}

class VendorOverviewTab extends StatelessWidget {
  const VendorOverviewTab({super.key});

  Future<_Overview> _load() async {
    final v = await fetchMyVendor();
    final bookings = await supa.from('bookings').select().eq('vendor_id', myId).order('created_at', ascending: false);
    final services = await supa.from('services').select('id').eq('vendor_id', myId);
    final docs = await supa.from('vendor_documents').select('id').eq('vendor_id', myId);
    return _Overview(v, bookings, services.length, docs.length);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Dashboard'),
        actions: [
          NotificationBell(
            onOpen: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const NotificationsScreen(onOpenBooking: openVendorBooking)),
            ),
          ),
        ],
      ),
      body: Loader<_Overview>(
        load: _load,
        builder: (context, d, reload) {
          int count(String s) => d.bookings.where((b) => b['status'] == s).length;
          final (pct, missing) = profileCompletion(d.vendor, d.services, d.documents);
          final status = str(d.vendor['verification_status'], 'pending');
          final pending = d.bookings.where((b) => b['status'] == 'pending').take(5).toList();

          return RefreshIndicator(
            onRefresh: reload,
            child: ListView(padding: const EdgeInsets.all(16), children: [
              Text(str(d.vendor['business_name']), style: Theme.of(context).textTheme.headlineSmall),
              const SizedBox(height: 4),
              VerifiedBadge(status),
              const SizedBox(height: 12),
              if (status != 'verified')
                AppCard(
                  color: status == 'rejected' ? const Color(0xFFFBE9E7) : kCream,
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const VerificationScreen())),
                  child: Row(children: [
                    Icon(status == 'rejected' ? Icons.error_outline : Icons.hourglass_top, color: kMaroon),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(status == 'rejected'
                          ? 'Verification was not approved${str(d.vendor['verification_note']).isEmpty ? '' : ': ${str(d.vendor['verification_note'])}'}. Tap to update documents.'
                          : 'Your business is waiting for verification. Customers will see your listings once verified. Tap to upload documents.'),
                    ),
                  ]),
                ),
              const SizedBox(height: 12),
              GridView.count(
                crossAxisCount: 2,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: 10,
                crossAxisSpacing: 10,
                childAspectRatio: 2.1,
                children: [
                  StatTile(label: 'Total enquiries', value: '${d.bookings.length}', icon: Icons.inbox),
                  StatTile(label: 'Pending requests', value: '${count('pending')}', icon: Icons.hourglass_top, color: kWarning),
                  StatTile(label: 'Accepted bookings', value: '${count('accepted')}', icon: Icons.check_circle, color: kSuccess),
                  StatTile(label: 'Completed', value: '${count('completed')}', icon: Icons.task_alt, color: kRoyalRed),
                  StatTile(label: 'Total services', value: '${d.services}', icon: Icons.storefront),
                  StatTile(label: 'Rating', value: toI(d.vendor['rating_count']) == 0 ? '—' : toD(d.vendor['rating_avg']).toStringAsFixed(1), icon: Icons.star, color: kGold),
                ],
              ),
              const SizedBox(height: 12),
              AppCard(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Text('Profile completion', style: Theme.of(context).textTheme.titleMedium),
                    const Spacer(),
                    Text('$pct%', style: const TextStyle(fontWeight: FontWeight.w700, color: kMaroon)),
                  ]),
                  const SizedBox(height: 8),
                  ProgressBar(pct / 100),
                  if (missing.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    for (final m in missing.take(4))
                      Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Row(children: [
                          const Icon(Icons.radio_button_unchecked, size: 14, color: kMuted),
                          const SizedBox(width: 6),
                          Text(m, style: const TextStyle(fontSize: 13)),
                        ]),
                      ),
                  ],
                ]),
              ),
              SectionHeader('New requests', actionLabel: 'View all', onAction: () => vendorTab.value = 1),
              if (pending.isEmpty)
                const AppCard(child: Text('No pending requests right now.', style: TextStyle(color: kMuted))),
              for (final b in pending)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: BookingCard(
                    booking: b,
                    title: str(b['customer_name'], 'Customer'),
                    subtitle: str(b['service_title']),
                    onTap: () => openVendorBooking(context, b['id'] as String),
                  ),
                ),
            ]),
          );
        },
      ),
    );
  }
}
