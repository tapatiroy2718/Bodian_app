import 'package:flutter/material.dart';

import '../core/data.dart';
import '../core/theme.dart';
import '../core/utils.dart';
import '../core/widgets.dart';
import 'customer_shell.dart';
import 'service_detail_screen.dart';

class WishlistTab extends StatefulWidget {
  const WishlistTab({super.key});
  @override
  State<WishlistTab> createState() => _WishlistTabState();
}

class _WishlistTabState extends State<WishlistTab> {
  final Set<String> _selected = {};

  Future<List<Map<String, dynamic>>> _load() async {
    final rows = await supa.from('wishlist').select('service_id').eq('customer_id', myId).order('created_at', ascending: false);
    final ids = rows.map((e) => e['service_id'] as String).toList();
    return fetchServicesByIds(ids);
  }

  Future<void> _remove(String id) async {
    _selected.remove(id);
    await runAction(context, () => toggleWishlist(id, false), success: 'Removed from wishlist');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Wishlist')),
      body: Loader<List<Map<String, dynamic>>>(
        load: _load,
        builder: (context, items, reload) {
          _selected.removeWhere((id) => !items.any((s) => s['id'] == id));
          if (items.isEmpty) {
            return RefreshIndicator(
              onRefresh: reload,
              child: ListView(children: [
                EmptyView(
                  icon: Icons.favorite_border,
                  title: 'Your wishlist is empty',
                  subtitle: 'Tap the heart on any vendor to save it here and compare options.',
                  action: FilledButton(onPressed: () => openExplore(), child: const Text('Explore vendors')),
                ),
              ]),
            );
          }
          return Column(children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
              child: Text('Select 2 or 3 to compare', style: TextStyle(color: kMuted.withAlpha(220))),
            ),
            Expanded(
              child: RefreshIndicator(
                onRefresh: reload,
                child: ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 100),
                  itemCount: items.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (context, i) {
                    final s = items[i];
                    final id = s['id'] as String;
                    final v = asMap(s['vendor_profiles']);
                    final selected = _selected.contains(id);
                    return AppCard(
                      padding: const EdgeInsets.all(10),
                      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ServiceDetailScreen(serviceId: id))),
                      child: Row(children: [
                        Checkbox(
                          value: selected,
                          activeColor: kMaroon,
                          onChanged: (v) => setState(() {
                            if (v == true) {
                              if (_selected.length >= 3) {
                                showSnack(context, 'You can compare up to 3 at a time.');
                                return;
                              }
                              _selected.add(id);
                            } else {
                              _selected.remove(id);
                            }
                          }),
                        ),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: NetImage(serviceCover(s), width: 64, height: 64),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(str(s['title']), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)),
                            Text(str(v['business_name']), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: kMuted, fontSize: 12)),
                            const SizedBox(height: 4),
                            Row(children: [
                              RatingRow(toD(v['rating_avg']), toI(v['rating_count'])),
                              const SizedBox(width: 8),
                              Text('From ${money(s['starting_price'])}', style: const TextStyle(color: kMaroon, fontWeight: FontWeight.w600, fontSize: 12)),
                            ]),
                          ]),
                        ),
                        IconButton(
                          tooltip: 'Remove',
                          icon: const Icon(Icons.favorite, color: kRoyalRed),
                          onPressed: () => _remove(id),
                        ),
                      ]),
                    );
                  },
                ),
              ),
            ),
          ]);
        },
      ),
      floatingActionButton: _selected.length >= 2
          ? FloatingActionButton.extended(
              backgroundColor: kMaroon,
              foregroundColor: Colors.white,
              icon: const Icon(Icons.compare_arrows),
              label: Text('Compare ${_selected.length}'),
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => CompareScreen(serviceIds: _selected.toList())),
              ),
            )
          : null,
    );
  }
}

class _CompareData {
  final List<Map<String, dynamic>> services;
  final Map<String, Map<DateTime, String>> unavailable;
  final DateTime? weddingDate;
  _CompareData(this.services, this.unavailable, this.weddingDate);
}

class CompareScreen extends StatelessWidget {
  final List<String> serviceIds;
  const CompareScreen({super.key, required this.serviceIds});

  Future<_CompareData> _load() async {
    final services = await fetchServicesByIds(serviceIds);
    final unavailable = <String, Map<DateTime, String>>{};
    for (final s in services) {
      unavailable[s['id'] as String] = await fetchUnavailableDates(s['id'] as String);
    }
    final c = await fetchCustomerProfile();
    return _CompareData(services, unavailable, parseDate(c['wedding_date']));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Compare')),
      body: Loader<_CompareData>(
        load: _load,
        listenGlobal: false,
        builder: (context, d, reload) {
          final rows = <(String, String Function(Map<String, dynamic>))>[
            ('Vendor', (s) => str(asMap(s['vendor_profiles'])['business_name'])),
            ('Starting price', (s) => money(s['starting_price'])),
            ('Packages', (s) {
              final p = activePackages(s);
              if (p.isEmpty) return 'On request';
              return p.map((e) => '${str(e['name'])}: ${money(e['price'])}').join('\n');
            }),
            ('Rating', (s) {
              final v = asMap(s['vendor_profiles']);
              return toI(v['rating_count']) == 0
                  ? 'No reviews yet'
                  : '${toD(v['rating_avg']).toStringAsFixed(1)} ★ (${toI(v['rating_count'])})';
            }),
            ('Location', (s) => str(s['location'], str(s['city'], str(asMap(s['vendor_profiles'])['city'], '—')))),
            ('Services', (s) {
              final items = <String>{
                ...asStrings(s['facilities']),
                for (final p in activePackages(s)) ...asStrings(p['included_services']),
              };
              return items.isEmpty ? '—' : items.take(8).join(', ');
            }),
            ('Capacity', (s) {
              final v = asMapOrNull(s['venue_details']);
              if (v == null) return '—';
              final max = v['max_guests'];
              return max == null ? '—' : 'Up to ${toI(max)} (${v['is_ac'] == true ? 'AC' : v['is_ac'] == false ? 'Non-AC' : 'AC n/a'})';
            }),
            ('Availability', (s) {
              final u = d.unavailable[s['id']] ?? const {};
              final wd = d.weddingDate;
              if (wd != null) {
                final key = DateTime(wd.year, wd.month, wd.day);
                return u.containsKey(key) ? 'Not available on ${fmtDate(wd)}' : 'Open on ${fmtDate(wd)}';
              }
              return u.isEmpty ? 'No dates blocked' : '${u.length} upcoming dates taken';
            }),
          ];
          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Table(
                defaultColumnWidth: const FixedColumnWidth(170),
                columnWidths: const {0: FixedColumnWidth(110)},
                border: TableBorder.all(color: const Color(0xFFF0E4DC), borderRadius: BorderRadius.circular(12)),
                children: [
                  TableRow(
                    decoration: const BoxDecoration(color: kCream),
                    children: [
                      const SizedBox(),
                      for (final s in d.services)
                        InkWell(
                          onTap: () => Navigator.push(context,
                              MaterialPageRoute(builder: (_) => ServiceDetailScreen(serviceId: s['id'] as String))),
                          child: Padding(
                            padding: const EdgeInsets.all(10),
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(10),
                                child: NetImage(serviceCover(s), height: 80, width: double.infinity),
                              ),
                              const SizedBox(height: 6),
                              Text(str(s['title']), style: const TextStyle(fontWeight: FontWeight.w700)),
                            ]),
                          ),
                        ),
                    ],
                  ),
                  for (final r in rows)
                    TableRow(children: [
                      Padding(
                        padding: const EdgeInsets.all(10),
                        child: Text(r.$1, style: const TextStyle(fontWeight: FontWeight.w600, color: kMaroon)),
                      ),
                      for (final s in d.services)
                        Padding(padding: const EdgeInsets.all(10), child: Text(r.$2(s))),
                    ]),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
