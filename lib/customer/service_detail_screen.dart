import 'package:flutter/material.dart';

import '../core/constants.dart';
import '../core/data.dart';
import '../core/theme.dart';
import '../core/utils.dart';
import '../core/widgets.dart';
import 'booking_form_screen.dart';

class _DetailData {
  final Map<String, dynamic> service;
  final List<Map<String, dynamic>> reviews;
  final Map<DateTime, String> unavailable;
  final bool wished;
  _DetailData(this.service, this.reviews, this.unavailable, this.wished);
}

/// Vendor profile + service details, packages, venue info, availability and reviews.
class ServiceDetailScreen extends StatefulWidget {
  final String serviceId;

  /// Vendors previewing their own listing see no booking actions.
  final bool preview;
  const ServiceDetailScreen({super.key, required this.serviceId, this.preview = false});
  @override
  State<ServiceDetailScreen> createState() => _ServiceDetailScreenState();
}

class _ServiceDetailScreenState extends State<ServiceDetailScreen> {
  bool? _wished;

  Future<_DetailData> _load() async {
    final s = await fetchService(widget.serviceId);
    if (s == null) throw Exception('This listing is no longer available.');
    final vendorId = s['vendor_id'] as String;
    final reviews = await supa.from('reviews').select().eq('vendor_id', vendorId).order('created_at', ascending: false).limit(30);
    final unavailable = await fetchUnavailableDates(widget.serviceId);
    var wished = false;
    if (!widget.preview) {
      final w = await supa.from('wishlist').select('id').eq('customer_id', myId).eq('service_id', widget.serviceId).maybeSingle();
      wished = w != null;
    }
    return _DetailData(s, reviews, unavailable, wished);
  }

  Future<void> _toggleWish(bool current) async {
    setState(() => _wished = !current);
    final ok = await runAction(context, () => toggleWishlist(widget.serviceId, !current),
        success: current ? 'Removed from wishlist' : 'Saved to wishlist');
    if (!ok && mounted) setState(() => _wished = current);
  }

  void _book(Map<String, dynamic> service, Map<DateTime, String> unavailable, [Map<String, dynamic>? package]) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => BookingFormScreen(service: service, unavailable: unavailable, initialPackage: package),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Loader<_DetailData>(
        load: _load,
        builder: (context, d, reload) {
          final s = d.service;
          final v = asMap(s['vendor_profiles']);
          final wished = _wished ?? d.wished;
          final images = asList(s['service_images'])..sort((a, b) => toI(a['sort']).compareTo(toI(b['sort'])));
          final gallery = [
            ...images.map((e) => str(e['url'])),
            ...asStrings(v['gallery']),
          ].where((u) => u.isNotEmpty).toList();
          final packages = activePackages(s);
          final venue = asMapOrNull(s['venue_details']);
          final cat = categoryById(s['category_id'] as String?);
          final facilities = asStrings(s['facilities']);

          return Stack(children: [
            RefreshIndicator(
              onRefresh: reload,
              child: CustomScrollView(slivers: [
                SliverAppBar(
                  expandedHeight: 260,
                  pinned: true,
                  backgroundColor: kMaroon,
                  foregroundColor: Colors.white,
                  actions: [
                    if (!widget.preview)
                      IconButton(
                        onPressed: () => _toggleWish(wished),
                        icon: Icon(wished ? Icons.favorite : Icons.favorite_border, color: Colors.white),
                      ),
                  ],
                  flexibleSpace: FlexibleSpaceBar(
                    background: gallery.isEmpty
                        ? NetImage(v['cover_url'] as String?, placeholderIcon: cat.icon)
                        : PageView(children: [for (final u in gallery) NetImage(u)]),
                  ),
                ),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 120),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(str(s['title']), style: Theme.of(context).textTheme.headlineSmall),
                      const SizedBox(height: 6),
                      Row(children: [
                        CircleAvatar(
                          radius: 14,
                          backgroundColor: kCream,
                          backgroundImage: nullIfEmpty(v['logo_url'] as String?) == null
                              ? null
                              : NetworkImage(v['logo_url'] as String),
                          child: nullIfEmpty(v['logo_url'] as String?) == null
                              ? const Icon(Icons.storefront, size: 16, color: kMaroon)
                              : null,
                        ),
                        const SizedBox(width: 8),
                        Flexible(child: Text(str(v['business_name']), style: const TextStyle(fontWeight: FontWeight.w600))),
                        const SizedBox(width: 8),
                        VerifiedBadge(v['verification_status'] as String?),
                      ]),
                      const SizedBox(height: 8),
                      Wrap(spacing: 12, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
                        RatingRow(toD(v['rating_avg']), toI(v['rating_count'])),
                        Row(mainAxisSize: MainAxisSize.min, children: [
                          const Icon(Icons.place_outlined, size: 16, color: kMuted),
                          Flexible(
                            child: Text(str(s['location'], str(s['city'], str(v['city'], 'Location on request'))),
                                style: const TextStyle(color: kMuted)),
                          ),
                        ]),
                        Chip(
                          label: Text(str(s['subcategory'], cat.name)),
                          visualDensity: VisualDensity.compact,
                          backgroundColor: kCream,
                          side: BorderSide.none,
                        ),
                      ]),
                      const SizedBox(height: 12),
                      AppCard(
                        color: kCream,
                        child: Row(children: [
                          const Text('Starting from', style: TextStyle(color: kMuted)),
                          const Spacer(),
                          Text(money(s['starting_price']),
                              style: Theme.of(context).textTheme.titleLarge?.copyWith(color: kMaroon)),
                        ]),
                      ),
                      if (str(s['description']).isNotEmpty || str(v['description']).isNotEmpty) ...[
                        const SectionTitle('About'),
                        Text(str(s['description'], str(v['description'])), style: const TextStyle(height: 1.45)),
                      ],
                      if (facilities.isNotEmpty) ...[
                        const SectionTitle('Facilities and services'),
                        Wrap(spacing: 8, runSpacing: 8, children: [
                          for (final f in facilities)
                            Chip(
                              avatar: const Icon(Icons.check, size: 16, color: kSuccess),
                              label: Text(f),
                              backgroundColor: Colors.white,
                              side: const BorderSide(color: Color(0xFFF0E4DC)),
                            ),
                        ]),
                      ],
                      if (venue != null) ...[
                        const SectionTitle('Venue details'),
                        AppCard(
                          child: Column(children: [
                            InfoRow(Icons.ac_unit, 'Type', venue['is_ac'] == null ? 'Not specified' : (venue['is_ac'] == true ? 'AC' : 'Non-AC')),
                            InfoRow(Icons.groups_outlined, 'Capacity', _capacity(venue)),
                            if (str(venue['seating']).isNotEmpty) InfoRow(Icons.event_seat, 'Seating', str(venue['seating'])),
                            InfoRow(Icons.local_parking, 'Parking', venue['parking'] == true ? 'Available' : 'Not available'),
                            InfoRow(Icons.restaurant, 'Catering', venue['catering_available'] == true ? 'In-house available' : 'Outside caterer'),
                            InfoRow(Icons.local_florist, 'Decoration', venue['decoration_available'] == true ? 'In-house available' : 'Outside decorator'),
                            if (str(venue['indoor_outdoor']).isNotEmpty)
                              InfoRow(Icons.deck, 'Setting', _setting(str(venue['indoor_outdoor']))),
                            const SizedBox(height: 8),
                            SizedBox(
                              width: double.infinity,
                              child: OutlinedButton.icon(
                                icon: const Icon(Icons.map_outlined),
                                label: const Text('Open in Maps'),
                                onPressed: () => openMap(
                                  context,
                                  lat: (venue['latitude'] as num?)?.toDouble(),
                                  lng: (venue['longitude'] as num?)?.toDouble(),
                                  query: str(venue['map_address'],
                                      '${str(s['title'])} ${str(s['location'], str(s['city'], str(v['address'])))}'),
                                ),
                              ),
                            ),
                          ]),
                        ),
                      ],
                      SectionTitle('Packages (${packages.length})'),
                      if (packages.isEmpty)
                        const Text('No packages listed. Send a request with your requirements for a quote.',
                            style: TextStyle(color: kMuted)),
                      for (final p in packages)
                        _PackageCard(
                          package: p,
                          onBook: widget.preview ? null : () => _book(s, d.unavailable, p),
                        ),
                      const SectionTitle('Availability'),
                      _Availability(d.unavailable),
                      if (gallery.length > 1) ...[
                        const SectionTitle('Portfolio'),
                        GridView.count(
                          crossAxisCount: 3,
                          mainAxisSpacing: 6,
                          crossAxisSpacing: 6,
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          children: [
                            for (final u in gallery)
                              GestureDetector(
                                onTap: () => _viewImage(context, u),
                                child: ClipRRect(borderRadius: BorderRadius.circular(10), child: NetImage(u)),
                              ),
                          ],
                        ),
                      ],
                      SectionTitle('Reviews (${d.reviews.length})'),
                      if (d.reviews.isEmpty)
                        const Text('No reviews yet.', style: TextStyle(color: kMuted)),
                      for (final r in d.reviews) ReviewTile(r),
                      if (str(v['address']).isNotEmpty) ...[
                        const SectionTitle('Business address'),
                        Text(str(v['address'])),
                      ],
                    ]),
                  ),
                ),
              ]),
            ),
            if (!widget.preview)
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: Container(
                  padding: EdgeInsets.fromLTRB(16, 12, 16, 12 + MediaQuery.of(context).padding.bottom),
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    boxShadow: [BoxShadow(color: Color(0x14000000), blurRadius: 12, offset: Offset(0, -2))],
                  ),
                  child: Row(children: [
                    IconButton.outlined(
                      tooltip: 'Call',
                      onPressed: () => callPhone(context, v['phone'] as String?),
                      icon: const Icon(Icons.call_outlined),
                    ),
                    const SizedBox(width: 8),
                    IconButton.outlined(
                      tooltip: 'WhatsApp',
                      onPressed: () => openWhatsApp(context, str(v['whatsapp'], str(v['phone'])),
                          text: 'Hi, I found ${str(s['title'])} on Bodiana and would like to know more.'),
                      icon: const Icon(Icons.chat_outlined),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () => _book(s, d.unavailable),
                        child: const Text('Send booking request'),
                      ),
                    ),
                  ]),
                ),
              ),
          ]);
        },
      ),
    );
  }

  String _capacity(Map<String, dynamic> v) {
    final min = v['min_guests'];
    final max = v['max_guests'];
    if (min == null && max == null) return 'Not specified';
    if (min == null) return 'Up to ${toI(max)} guests';
    if (max == null) return 'From ${toI(min)} guests';
    return '${toI(min)} – ${toI(max)} guests';
  }

  String _setting(String s) => switch (s) { 'indoor' => 'Indoor', 'outdoor' => 'Outdoor', _ => 'Indoor and outdoor' };

  void _viewImage(BuildContext context, String url) {
    showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        insetPadding: const EdgeInsets.all(12),
        clipBehavior: Clip.antiAlias,
        child: InteractiveViewer(child: NetImage(url, fit: BoxFit.contain)),
      ),
    );
  }
}

class SectionTitle extends StatelessWidget {
  final String text;
  const SectionTitle(this.text, {super.key});
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 22, bottom: 10),
        child: Text(text, style: Theme.of(context).textTheme.titleMedium),
      );
}

class _PackageCard extends StatelessWidget {
  final Map<String, dynamic> package;
  final VoidCallback? onBook;
  const _PackageCard({required this.package, this.onBook});
  @override
  Widget build(BuildContext context) {
    final included = asStrings(package['included_services']);
    return AppCard(
      margin: const EdgeInsets.only(bottom: 10),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text(str(package['name']), style: Theme.of(context).textTheme.titleMedium)),
          Text(money(package['price']), style: const TextStyle(color: kMaroon, fontWeight: FontWeight.w700, fontSize: 16)),
        ]),
        if (str(package['description']).isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(str(package['description']), style: const TextStyle(color: kMuted)),
        ],
        if (included.isNotEmpty) ...[
          const SizedBox(height: 8),
          for (final i in included)
            Padding(
              padding: const EdgeInsets.only(bottom: 2),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Icon(Icons.check_circle, size: 16, color: kSuccess),
                const SizedBox(width: 6),
                Expanded(child: Text(i)),
              ]),
            ),
        ],
        if (str(package['additional_charges']).isNotEmpty) ...[
          const SizedBox(height: 8),
          Text('Additional charges: ${str(package['additional_charges'])}', style: const TextStyle(fontSize: 12)),
        ],
        if (str(package['terms']).isNotEmpty) ...[
          const SizedBox(height: 4),
          Text('Terms: ${str(package['terms'])}', style: const TextStyle(fontSize: 12, color: kMuted)),
        ],
        if (onBook != null) ...[
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton.tonal(onPressed: onBook, child: const Text('Request this package')),
          ),
        ],
      ]),
    );
  }
}

class _Availability extends StatelessWidget {
  final Map<DateTime, String> unavailable;
  const _Availability(this.unavailable);
  @override
  Widget build(BuildContext context) {
    if (unavailable.isEmpty) {
      return const AppCard(
        child: Row(children: [
          Icon(Icons.event_available, color: kSuccess),
          SizedBox(width: 10),
          Expanded(child: Text('No dates blocked yet. Send a request to confirm your date.')),
        ]),
      );
    }
    final dates = unavailable.keys.toList()..sort();
    return AppCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('These upcoming dates are not available:', style: TextStyle(color: kMuted)),
        const SizedBox(height: 8),
        Wrap(spacing: 6, runSpacing: 6, children: [
          for (final d in dates.take(30))
            Chip(
              label: Text(fmtDate(d)),
              visualDensity: VisualDensity.compact,
              backgroundColor: const Color(0xFFFBE9E7),
              side: BorderSide.none,
            ),
        ]),
      ]),
    );
  }
}

class ReviewTile extends StatelessWidget {
  final Map<String, dynamic> review;
  const ReviewTile(this.review, {super.key});
  @override
  Widget build(BuildContext context) {
    final rating = toI(review['rating']);
    return AppCard(
      margin: const EdgeInsets.only(bottom: 8),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text(str(review['customer_name'], 'Customer'), style: const TextStyle(fontWeight: FontWeight.w600))),
          for (var i = 1; i <= 5; i++) Icon(i <= rating ? Icons.star_rounded : Icons.star_outline_rounded, size: 16, color: kGold),
        ]),
        if (str(review['comment']).isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(str(review['comment'])),
        ],
        const SizedBox(height: 4),
        Text(fmtDate(review['created_at']), style: const TextStyle(fontSize: 11, color: kMuted)),
      ]),
    );
  }
}
