import 'package:flutter/material.dart';

import 'explore_tab.dart';
import 'home_tab.dart';
import 'profile_tab.dart';
import 'wedding_tab.dart';
import 'wishlist_tab.dart';

class ExploreRequest {
  final String? category;
  final String? query;
  const ExploreRequest({this.category, this.query});
}

/// Set this to open the Explore tab with a category or search.
final exploreRequest = ValueNotifier<ExploreRequest?>(null);

/// Set this to switch the customer's bottom tab.
final customerTab = ValueNotifier<int>(0);

void openExplore({String? category, String? query}) {
  exploreRequest.value = ExploreRequest(category: category, query: query);
  customerTab.value = 1;
}

class CustomerShell extends StatefulWidget {
  const CustomerShell({super.key});
  @override
  State<CustomerShell> createState() => _CustomerShellState();
}

class _CustomerShellState extends State<CustomerShell> {
  @override
  void initState() {
    super.initState();
    customerTab.value = 0;
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: customerTab,
      builder: (context, index, _) {
        return PopScope(
          canPop: index == 0,
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop) customerTab.value = 0;
          },
          child: Scaffold(
            body: IndexedStack(index: index, children: const [
              HomeTab(),
              ExploreTab(),
              WeddingTab(),
              WishlistTab(),
              ProfileTab(),
            ]),
            bottomNavigationBar: NavigationBar(
              selectedIndex: index,
              onDestinationSelected: (i) => customerTab.value = i,
              destinations: const [
                NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home), label: 'Home'),
                NavigationDestination(icon: Icon(Icons.search), label: 'Explore'),
                NavigationDestination(
                    icon: Icon(Icons.event_note_outlined), selectedIcon: Icon(Icons.event_note), label: 'My Wedding'),
                NavigationDestination(
                    icon: Icon(Icons.favorite_border), selectedIcon: Icon(Icons.favorite), label: 'Wishlist'),
                NavigationDestination(icon: Icon(Icons.person_outline), selectedIcon: Icon(Icons.person), label: 'Profile'),
              ],
            ),
          ),
        );
      },
    );
  }
}
