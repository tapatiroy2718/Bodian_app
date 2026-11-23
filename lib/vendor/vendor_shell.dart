import 'package:flutter/material.dart';

import 'vendor_bookings_tab.dart';
import 'vendor_calendar_tab.dart';
import 'vendor_more_tab.dart';
import 'vendor_overview_tab.dart';
import 'vendor_services_tab.dart';

/// Switches the vendor's bottom tab from anywhere.
final vendorTab = ValueNotifier<int>(0);

class VendorShell extends StatefulWidget {
  const VendorShell({super.key});
  @override
  State<VendorShell> createState() => _VendorShellState();
}

class _VendorShellState extends State<VendorShell> {
  @override
  void initState() {
    super.initState();
    vendorTab.value = 0;
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: vendorTab,
      builder: (context, index, _) => PopScope(
        canPop: index == 0,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) vendorTab.value = 0;
        },
        child: Scaffold(
          body: IndexedStack(index: index, children: const [
            VendorOverviewTab(),
            VendorBookingsTab(),
            VendorServicesTab(),
            VendorCalendarTab(),
            VendorMoreTab(),
          ]),
          bottomNavigationBar: NavigationBar(
            selectedIndex: index,
            onDestinationSelected: (i) => vendorTab.value = i,
            destinations: const [
              NavigationDestination(icon: Icon(Icons.dashboard_outlined), selectedIcon: Icon(Icons.dashboard), label: 'Overview'),
              NavigationDestination(icon: Icon(Icons.inbox_outlined), selectedIcon: Icon(Icons.inbox), label: 'Requests'),
              NavigationDestination(
                  icon: Icon(Icons.storefront_outlined), selectedIcon: Icon(Icons.storefront), label: 'Services'),
              NavigationDestination(
                  icon: Icon(Icons.calendar_month_outlined), selectedIcon: Icon(Icons.calendar_month), label: 'Calendar'),
              NavigationDestination(icon: Icon(Icons.menu), label: 'More'),
            ],
          ),
        ),
      ),
    );
  }
}
