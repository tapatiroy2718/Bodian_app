import 'package:flutter/material.dart';

import '../core/theme.dart';
import '../core/utils.dart';
import '../core/widgets.dart';
import '../customer/bookings_screen.dart';
import 'vendor_overview_tab.dart';

class VendorBookingsTab extends StatelessWidget {
  const VendorBookingsTab({super.key});

  Future<List<Map<String, dynamic>>> _load() async {
    return await supa.from('bookings').select().eq('vendor_id', myId).order('event_date', ascending: true);
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 4,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Booking requests'),
          bottom: const TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            labelColor: kMaroon,
            indicatorColor: kMaroon,
            tabs: [Tab(text: 'Pending'), Tab(text: 'Accepted'), Tab(text: 'Completed'), Tab(text: 'Closed')],
          ),
        ),
        body: Loader<List<Map<String, dynamic>>>(
          load: _load,
          builder: (context, all, reload) {
            Widget list(List<String> statuses, String empty) {
              final items = all.where((b) => statuses.contains(b['status'])).toList();
              if (statuses.contains('completed') || statuses.contains('rejected')) {
                items.sort((a, b) => str(b['event_date']).compareTo(str(a['event_date'])));
              }
              return RefreshIndicator(
                onRefresh: reload,
                child: items.isEmpty
                    ? ListView(children: [EmptyView(icon: Icons.inbox_outlined, title: empty)])
                    : ListView.separated(
                        padding: const EdgeInsets.all(16),
                        itemCount: items.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 10),
                        itemBuilder: (context, i) => BookingCard(
                          booking: items[i],
                          title: str(items[i]['customer_name'], 'Customer'),
                          subtitle: str(items[i]['service_title']),
                          onTap: () => openVendorBooking(context, items[i]['id'] as String),
                        ),
                      ),
              );
            }

            return TabBarView(children: [
              list(['pending'], 'No pending requests'),
              list(['accepted'], 'No upcoming confirmed bookings'),
              list(['completed'], 'No completed bookings yet'),
              list(['rejected', 'cancelled'], 'No rejected or cancelled bookings'),
            ]);
          },
        ),
      ),
    );
  }
}
