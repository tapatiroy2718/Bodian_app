import 'package:flutter/material.dart';

import '../core/constants.dart';
import '../core/data.dart';
import '../core/theme.dart';
import '../core/utils.dart';
import '../core/widgets.dart';
import '../shared/notifications_screen.dart';
import 'bookings_screen.dart';
import 'customer_shell.dart';
import 'service_detail_screen.dart';

class _HomeData {
  final Map<String, dynamic> profile;
  final Map<String, dynamic> customer;
  final List<Map<String, dynamic>> events;
  final List<Map<String, dynamic>> tasks;
  final List<Map<String, dynamic>> recommended;
  final List<Map<String, dynamic>> venues;
  final List<Map<String, dynamic>> activity;
  final int wishlistCount;
  final int activeBookings;
  _HomeData(this.profile, this.customer, this.events, this.tasks, this.recommended, this.venues, this.activity,
      this.wishlistCount, this.activeBookings);
}

class HomeTab extends StatelessWidget {
  const HomeTab({super.key});

  Future<_HomeData> _load() async {
    final profile = await fetchMyProfile();
    final customer = await fetchCustomerProfile();
    final events = await supa.from('wedding_events').select().eq('customer_id', myId).order('event_date', ascending: true);
    final tasks = await supa.from('event_checklists').select('id, status, amount, event_id').eq('customer_id', myId);
    final city = nullIfEmpty(customer['wedding_city'] as String?);
    var recommended = await searchServices(SearchFilters(city: city, sort: 'rating'), limit: 10);
    if (recommended.isEmpty && city != null) {
      recommended = await searchServices(SearchFilters(sort: 'rating'), limit: 10);
    }
    var venues = await searchServices(SearchFilters(category: 'venues', city: city, sort: 'rating'), limit: 10);
    if (venues.isEmpty && city != null) {
      venues = await searchServices(SearchFilters(category: 'venues', sort: 'rating'), limit: 10);
    }
    final activity = await supa.from('notifications').select().eq('user_id', myId).order('created_at', ascending: false).limit(5);
    final wish = await supa.from('wishlist').select('id').eq('customer_id', myId);
    final active = await supa.from('bookings').select('id').eq('customer_id', myId).inFilter('status', ['pending', 'accepted']);
    return _HomeData(profile, customer, events, tasks, recommended, venues, activity, wish.length, active.length);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Loader<_HomeData>(
          load: _load,
          builder: (context, d, reload) => RefreshIndicator(
            onRefresh: reload,
            child: ListView(
              padding: const EdgeInsets.only(bottom: 24),
              children: [
                _header(context, d),
                _countdown(context, d),
                _searchBar(context),
                _quickStats(context, d),
                SectionHeader('Services', actionLabel: 'See all', onAction: () => openExplore()),
                SizedBox(
                  height: 96,
                  child: ListView.separated(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    scrollDirection: Axis.horizontal,
                    itemCount: categories.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 10),
                    itemBuilder: (_, i) => _CategoryTile(categories[i]),
                  ),
                ),
                _carousel(context, 'Recommended for you', d.recommended, () => openExplore()),
                _carousel(context, 'Popular wedding venues', d.venues, () => openExplore(category: 'venues')),
                _upcoming(context, d),
                _activity(context, d),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _header(BuildContext context, _HomeData d) {
    final name = str(d.profile['full_name'], 'there').split(' ').first;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
      child: Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Nomoskar, $name', style: Theme.of(context).textTheme.headlineSmall),
            const Text('Let\'s plan your wedding', style: TextStyle(color: kMuted)),
          ]),
        ),
        NotificationBell(onOpen: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const NotificationsScreen()))),
      ]),
    );
  }

  Widget _countdown(BuildContext context, _HomeData d) {
    final date = parseDate(d.customer['wedding_date']);
    final days = date == null ? null : DateTime(date.year, date.month, date.day).difference(today()).inDays;
    final total = d.tasks.where((t) => t['status'] != 'skipped').length;
    final done = d.tasks.where((t) => t['status'] == 'done').length;
    final progress = total == 0 ? 0.0 : done / total;
    final budget = toD(d.customer['budget']);
    final spent = d.tasks.where((t) => t['status'] == 'done').fold<double>(0, (s, t) => s + toD(t['amount']));

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(kRadius),
          gradient: const LinearGradient(colors: [kMaroon, Color(0xFF8E1F3D)]),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(
                  days == null
                      ? 'Set your wedding date'
                      : days > 0
                          ? '$days days to go'
                          : days == 0
                              ? 'Today is the day!'
                              : 'Married ${-days} days ago',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(color: Colors.white),
                ),
                const SizedBox(height: 4),
                Text('${fmtDate(date)} · ${str(d.customer['wedding_city'], 'Location not set')}',
                    style: const TextStyle(color: Color(0xFFF6E7C1))),
              ]),
            ),
            const Icon(Icons.favorite, color: kGold, size: 36),
          ]),
          const SizedBox(height: 16),
          Row(children: [
            const Text('Planning progress', style: TextStyle(color: Colors.white70, fontSize: 12)),
            const Spacer(),
            Text('${(progress * 100).round()}%', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
          ]),
          const SizedBox(height: 6),
          ProgressBar(progress, color: kGold),
          const SizedBox(height: 12),
          Row(children: [
            const Text('Budget', style: TextStyle(color: Colors.white70, fontSize: 12)),
            const Spacer(),
            Text(budget > 0 ? '${money(spent)} of ${money(budget)} used' : 'Budget not set',
                style: const TextStyle(color: Colors.white, fontSize: 12)),
          ]),
          if (budget > 0) ...[
            const SizedBox(height: 6),
            ProgressBar(spent / budget, color: spent > budget ? const Color(0xFFFF8A80) : Colors.white),
          ],
          const SizedBox(height: 12),
          InkWell(
            onTap: () => customerTab.value = 2,
            child: const Row(children: [
              Text('Open my wedding planner', style: TextStyle(color: kGold, fontWeight: FontWeight.w600)),
              Icon(Icons.chevron_right, color: kGold),
            ]),
          ),
        ]),
      ),
    );
  }

  Widget _searchBar(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: TextField(
        readOnly: false,
        textInputAction: TextInputAction.search,
        onSubmitted: (q) => openExplore(query: q),
        decoration: inputDeco('Search venues, photographers, caterers…', icon: Icons.search),
      ),
    );
  }

  Widget _quickStats(BuildContext context, _HomeData d) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Row(children: [
        Expanded(
          child: AppCard(
            padding: const EdgeInsets.all(12),
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const MyBookingsScreen())),
            child: Row(children: [
              const Icon(Icons.receipt_long, color: kMaroon),
              const SizedBox(width: 8),
              Expanded(child: Text('${d.activeBookings} active\nbookings', style: const TextStyle(fontSize: 13))),
            ]),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: AppCard(
            padding: const EdgeInsets.all(12),
            onTap: () => customerTab.value = 3,
            child: Row(children: [
              const Icon(Icons.favorite, color: kRoyalRed),
              const SizedBox(width: 8),
              Expanded(child: Text('${d.wishlistCount} saved\nvendors', style: const TextStyle(fontSize: 13))),
            ]),
          ),
        ),
      ]),
    );
  }

  Widget _carousel(BuildContext context, String title, List<Map<String, dynamic>> items, VoidCallback onAll) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      SectionHeader(title, actionLabel: 'See all', onAction: onAll),
      if (items.isEmpty)
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 16),
          child: AppCard(child: Text('No verified vendors listed here yet. Check back soon!', style: TextStyle(color: kMuted))),
        )
      else
        SizedBox(
          height: 268,
          child: ListView.separated(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            scrollDirection: Axis.horizontal,
            itemCount: items.length,
            separatorBuilder: (_, __) => const SizedBox(width: 12),
            itemBuilder: (_, i) => ServiceCard(
              width: 220,
              service: items[i],
              onTap: () => Navigator.push(
                  context, MaterialPageRoute(builder: (_) => ServiceDetailScreen(serviceId: items[i]['id'] as String))),
            ),
          ),
        ),
    ]);
  }

  Widget _upcoming(BuildContext context, _HomeData d) {
    final t = today();
    final upcoming = d.events.where((e) {
      final dt = parseDate(e['event_date']);
      return dt == null || !dt.isBefore(t);
    }).take(4).toList();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      SectionHeader('Upcoming events', actionLabel: 'Planner', onAction: () => customerTab.value = 2),
      if (upcoming.isEmpty)
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 16),
          child: AppCard(child: Text('No events yet. Add them in My Wedding.', style: TextStyle(color: kMuted))),
        ),
      for (final e in upcoming)
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: AppCard(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            onTap: () => customerTab.value = 2,
            child: Row(children: [
              const Icon(Icons.celebration, color: kGold),
              const SizedBox(width: 12),
              Expanded(child: Text(str(e['name']), style: const TextStyle(fontWeight: FontWeight.w600))),
              Text(fmtDate(e['event_date'], 'Date not set'), style: const TextStyle(color: kMuted, fontSize: 12)),
            ]),
          ),
        ),
    ]);
  }

  Widget _activity(BuildContext context, _HomeData d) {
    if (d.activity.isEmpty) return const SizedBox.shrink();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const SectionHeader('Recent activity'),
      for (final n in d.activity)
        ListTile(
          dense: true,
          leading: const Icon(Icons.notifications_none, color: kMaroon),
          title: Text(str(n['title'])),
          subtitle: Text(str(n['body']), maxLines: 2, overflow: TextOverflow.ellipsis),
          trailing: Text(timeAgo(n['created_at']), style: const TextStyle(fontSize: 11, color: kMuted)),
        ),
    ]);
  }
}

class _CategoryTile extends StatelessWidget {
  final WeddingCategory cat;
  const _CategoryTile(this.cat);
  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: () => openExplore(category: cat.id),
      child: SizedBox(
        width: 76,
        child: Column(children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: const Color(0xFFF0E4DC)),
            ),
            child: Icon(cat.icon, color: kMaroon),
          ),
          const SizedBox(height: 6),
          Text(cat.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12)),
        ]),
      ),
    );
  }
}
