import 'package:flutter/material.dart';

import '../core/constants.dart';
import '../core/data.dart';
import '../core/theme.dart';
import '../core/utils.dart';
import '../core/widgets.dart';
import 'customer_shell.dart';
import 'service_detail_screen.dart';

/// Explore tab in the bottom navigation.
class ExploreTab extends StatefulWidget {
  const ExploreTab({super.key});
  @override
  State<ExploreTab> createState() => _ExploreTabState();
}

class _ExploreTabState extends State<ExploreTab> {
  final _key = GlobalKey<_ExploreBodyState>();

  @override
  void initState() {
    super.initState();
    exploreRequest.addListener(_onRequest);
  }

  @override
  void dispose() {
    exploreRequest.removeListener(_onRequest);
    super.dispose();
  }

  void _onRequest() {
    final r = exploreRequest.value;
    if (r == null) return;
    exploreRequest.value = null;
    _key.currentState?.apply(category: r.category, query: r.query);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Explore')),
      body: _ExploreBody(key: _key),
    );
  }
}

/// Standalone explore screen, e.g. "Show vendors" from a checklist task.
class ExploreScreen extends StatelessWidget {
  final String? category;
  final String? title;
  const ExploreScreen({super.key, this.category, this.title});
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title ?? (category == null ? 'Explore' : categoryById(category).name))),
      body: _ExploreBody(initialCategory: category),
    );
  }
}

class _ExploreBody extends StatefulWidget {
  final String? initialCategory;
  const _ExploreBody({super.key, this.initialCategory});
  @override
  State<_ExploreBody> createState() => _ExploreBodyState();
}

class _ExploreBodyState extends State<_ExploreBody> {
  late SearchFilters _f = SearchFilters(category: widget.initialCategory);
  final _search = TextEditingController();
  Set<String> _wish = {};

  @override
  void initState() {
    super.initState();
    _loadWish();
    dataVersion.addListener(_loadWish);
  }

  @override
  void dispose() {
    dataVersion.removeListener(_loadWish);
    _search.dispose();
    super.dispose();
  }

  Future<void> _loadWish() async {
    try {
      final w = await fetchWishlistIds();
      if (mounted) setState(() => _wish = w);
    } catch (_) {}
  }

  void apply({String? category, String? query}) {
    setState(() {
      _f = SearchFilters(category: category, query: query);
      _search.text = query ?? '';
    });
  }

  Future<void> _openFilters() async {
    final result = await showModalBottomSheet<SearchFilters>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _FilterSheet(initial: _f.copy()),
    );
    if (result != null) setState(() => _f = result);
  }

  Future<void> _toggleWish(String id) async {
    final add = !_wish.contains(id);
    setState(() => add ? _wish.add(id) : _wish.remove(id));
    final ok = await runAction(context, () => toggleWishlist(id, add), success: add ? 'Saved to wishlist' : 'Removed from wishlist');
    if (!ok && mounted) setState(() => add ? _wish.remove(id) : _wish.add(id));
  }

  @override
  Widget build(BuildContext context) {
    final count = _f.activeCount;
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
        child: Row(children: [
          Expanded(
            child: TextField(
              controller: _search,
              textInputAction: TextInputAction.search,
              onSubmitted: (q) => setState(() => _f = _f.copy()..query = q),
              decoration: inputDeco('Search vendors and venues', icon: Icons.search).copyWith(
                suffixIcon: _search.text.isEmpty && (_f.query ?? '').isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => setState(() {
                          _search.clear();
                          _f = _f.copy()..query = null;
                        }),
                      ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Badge(
            isLabelVisible: count > 0,
            label: Text('$count'),
            backgroundColor: kRoyalRed,
            child: IconButton.filledTonal(
              onPressed: _openFilters,
              icon: const Icon(Icons.tune),
              tooltip: 'Filters',
            ),
          ),
        ]),
      ),
      SizedBox(
        height: 44,
        child: ListView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          children: [
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                label: const Text('All'),
                selected: _f.category == null,
                onSelected: (_) => setState(() => _f = _f.copy()..category = null),
              ),
            ),
            for (final c in categories)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(
                  avatar: Icon(c.icon, size: 16),
                  label: Text(c.name),
                  selected: _f.category == c.id,
                  onSelected: (_) => setState(() {
                    final next = _f.copy()..category = c.id;
                    if (c.id != 'venues') next.isAc = null;
                    _f = next;
                  }),
                ),
              ),
          ],
        ),
      ),
      Expanded(
        child: Loader<List<Map<String, dynamic>>>(
          key: ValueKey(_f.signature),
          listenGlobal: false,
          load: () => searchServices(_f),
          builder: (context, items, reload) {
            if (items.isEmpty) {
              return RefreshIndicator(
                onRefresh: reload,
                child: ListView(children: [
                  EmptyView(
                    icon: Icons.search_off,
                    title: 'No vendors found',
                    subtitle: count > 0 || _f.query != null
                        ? 'Try removing some filters.'
                        : 'Verified vendors in this category will appear here.',
                    action: count > 0
                        ? OutlinedButton(
                            onPressed: () => setState(() => _f = SearchFilters(category: _f.category, query: _f.query)),
                            child: const Text('Clear filters'),
                          )
                        : null,
                  ),
                ]),
              );
            }
            return RefreshIndicator(
              onRefresh: reload,
              child: ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                itemCount: items.length + 1,
                separatorBuilder: (_, __) => const SizedBox(height: 12),
                itemBuilder: (context, i) {
                  if (i == 0) {
                    return Text('${items.length} result${items.length == 1 ? '' : 's'}',
                        style: const TextStyle(color: kMuted));
                  }
                  final s = items[i - 1];
                  final id = s['id'] as String;
                  return ServiceCard(
                    service: s,
                    onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ServiceDetailScreen(serviceId: id))),
                    trailing: IconButton(
                      onPressed: () => _toggleWish(id),
                      icon: CircleAvatar(
                        radius: 16,
                        backgroundColor: Colors.white,
                        child: Icon(_wish.contains(id) ? Icons.favorite : Icons.favorite_border, size: 18, color: kRoyalRed),
                      ),
                    ),
                  );
                },
              ),
            );
          },
        ),
      ),
    ]);
  }
}

class _FilterSheet extends StatefulWidget {
  final SearchFilters initial;
  const _FilterSheet({required this.initial});
  @override
  State<_FilterSheet> createState() => _FilterSheetState();
}

class _FilterSheetState extends State<_FilterSheet> {
  late final SearchFilters f = widget.initial;
  late final _city = TextEditingController(text: f.city ?? '');
  late final _min = TextEditingController(text: f.minPrice?.toStringAsFixed(0) ?? '');
  late final _max = TextEditingController(text: f.maxPrice?.toStringAsFixed(0) ?? '');
  late final _guests = TextEditingController(text: f.guests?.toString() ?? '');

  @override
  void dispose() {
    for (final c in [_city, _min, _max, _guests]) {
      c.dispose();
    }
    super.dispose();
  }

  void _apply() {
    f.city = nullIfEmpty(_city.text);
    f.minPrice = double.tryParse(_min.text.trim());
    f.maxPrice = double.tryParse(_max.text.trim());
    f.guests = int.tryParse(_guests.text.trim());
    Navigator.pop(context, f);
  }

  void _reset() {
    Navigator.pop(context, SearchFilters(category: f.category, query: f.query));
  }

  @override
  Widget build(BuildContext context) {
    final isVenue = f.category == 'venues' || f.category == null;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('Filters', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 16),
          TextField(controller: _city, decoration: inputDeco('City / location', icon: Icons.place_outlined)),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
              child: TextField(
                  controller: _min, keyboardType: TextInputType.number, decoration: inputDeco('Min price (₹)')),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextField(
                  controller: _max, keyboardType: TextInputType.number, decoration: inputDeco('Max price (₹)')),
            ),
          ]),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            icon: const Icon(Icons.event_available),
            label: Text(f.date == null ? 'Available on date (any)' : 'Available on ${fmtDate(f.date)}'),
            onPressed: () async {
              final d = await pickDate(context, initial: f.date);
              if (d != null) setState(() => f.date = d);
            },
          ),
          if (f.date != null)
            TextButton(onPressed: () => setState(() => f.date = null), child: const Text('Clear date')),
          const SizedBox(height: 12),
          Text('Minimum rating', style: Theme.of(context).textTheme.titleSmall),
          Wrap(spacing: 8, children: [
            for (final r in [null, 3.0, 4.0, 4.5])
              ChoiceChip(
                label: Text(r == null ? 'Any' : '${r.toStringAsFixed(r == 4.5 ? 1 : 0)}★ +'),
                selected: f.minRating == r,
                onSelected: (_) => setState(() => f.minRating = r),
              ),
          ]),
          if (isVenue) ...[
            const SizedBox(height: 12),
            TextField(
              controller: _guests,
              keyboardType: TextInputType.number,
              decoration: inputDeco('Guest capacity (venues)', icon: Icons.groups_outlined),
            ),
            const SizedBox(height: 12),
            Text('Venue type', style: Theme.of(context).textTheme.titleSmall),
            Wrap(spacing: 8, children: [
              ChoiceChip(label: const Text('Any'), selected: f.isAc == null, onSelected: (_) => setState(() => f.isAc = null)),
              ChoiceChip(label: const Text('AC'), selected: f.isAc == true, onSelected: (_) => setState(() => f.isAc = true)),
              ChoiceChip(
                  label: const Text('Non-AC'), selected: f.isAc == false, onSelected: (_) => setState(() => f.isAc = false)),
            ]),
          ],
          const SizedBox(height: 12),
          Text('Sort by', style: Theme.of(context).textTheme.titleSmall),
          Wrap(spacing: 8, children: [
            for (final e in const {
              'recommended': 'Recommended',
              'rating': 'Top rated',
              'price_low': 'Price: low to high',
              'price_high': 'Price: high to low',
            }.entries)
              ChoiceChip(label: Text(e.value), selected: f.sort == e.key, onSelected: (_) => setState(() => f.sort = e.key)),
          ]),
          const SizedBox(height: 20),
          Row(children: [
            Expanded(child: OutlinedButton(onPressed: _reset, child: const Text('Reset'))),
            const SizedBox(width: 12),
            Expanded(child: FilledButton(onPressed: _apply, child: const Text('Show results'))),
          ]),
        ]),
      ),
    );
  }
}
