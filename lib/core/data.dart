import 'utils.dart';

/// Columns fetched for marketplace listings.
const serviceSelect = '*, '
    'vendor_profiles!services_vendor_id_fkey(id, business_name, city, rating_avg, rating_count, verification_status, logo_url, cover_url, phone, whatsapp, gallery, description, address), '
    'service_images(id, url, storage_path, sort), '
    'service_packages(*), '
    'venue_details(*)';

String? serviceCover(Map<String, dynamic> service) {
  final images = asList(service['service_images'])..sort((a, b) => toI(a['sort']).compareTo(toI(b['sort'])));
  if (images.isNotEmpty) return str(images.first['url']);
  final vendor = asMap(service['vendor_profiles']);
  return nullIfEmpty(vendor['cover_url'] as String?) ?? nullIfEmpty(vendor['logo_url'] as String?);
}

List<Map<String, dynamic>> activePackages(Map<String, dynamic> service) {
  final p = asList(service['service_packages']).where((e) => e['is_active'] != false).toList()
    ..sort((a, b) => toD(a['price']).compareTo(toD(b['price'])));
  return p;
}

Future<List<Map<String, dynamic>>> fetchServicesByIds(List<String> ids) async {
  if (ids.isEmpty) return [];
  final rows = await supa.from('services').select(serviceSelect).inFilter('id', ids);
  final byId = <String, Map<String, dynamic>>{for (final r in rows) r['id'] as String: r};
  return [for (final id in ids) if (byId[id] != null) byId[id]!];
}

Future<Map<String, dynamic>?> fetchService(String id) async {
  final r = await supa.from('services').select(serviceSelect).eq('id', id).maybeSingle();
  return r;
}

class SearchFilters {
  String? category;
  String? query;
  String? city;
  double? minPrice;
  double? maxPrice;
  double? minRating;
  int? guests;
  bool? isAc;
  DateTime? date;
  String sort;

  SearchFilters({
    this.category,
    this.query,
    this.city,
    this.minPrice,
    this.maxPrice,
    this.minRating,
    this.guests,
    this.isAc,
    this.date,
    this.sort = 'recommended',
  });

  SearchFilters copy() => SearchFilters(
        category: category,
        query: query,
        city: city,
        minPrice: minPrice,
        maxPrice: maxPrice,
        minRating: minRating,
        guests: guests,
        isAc: isAc,
        date: date,
        sort: sort,
      );

  int get activeCount => [city, minPrice, maxPrice, minRating, guests, isAc, date].where((e) => e != null).length +
      (sort == 'recommended' ? 0 : 1);

  String get signature => [category, query, city, minPrice, maxPrice, minRating, guests, isAc, date, sort].join('|');

  Map<String, dynamic> toParams({int limit = 60}) => {
        'p_category': category,
        'p_query': nullIfEmpty(query),
        'p_city': nullIfEmpty(city),
        'p_min_price': minPrice,
        'p_max_price': maxPrice,
        'p_min_rating': minRating,
        'p_guests': guests,
        'p_is_ac': isAc,
        'p_date': date == null ? null : ymd(date!),
        'p_sort': sort,
        'p_limit': limit,
      };
}

Future<List<Map<String, dynamic>>> searchServices(SearchFilters f, {int limit = 60}) async {
  final res = await supa.rpc('search_services', params: f.toParams(limit: limit));
  final ids = asList(res).map((e) => e['id'].toString()).toList();
  return fetchServicesByIds(ids);
}

/// Dates a service can't be booked: {date: 'booked' | 'unavailable'}.
Future<Map<DateTime, String>> fetchUnavailableDates(String serviceId) async {
  final res = await supa.rpc('service_unavailable_dates', params: {'p_service_id': serviceId});
  final out = <DateTime, String>{};
  for (final r in asList(res)) {
    final d = DateTime.tryParse(str(r['date']));
    if (d != null) out[DateTime(d.year, d.month, d.day)] = str(r['reason']);
  }
  return out;
}

Future<Map<String, dynamic>> fetchMyProfile() async {
  final r = await supa.from('profiles').select().eq('id', myId).maybeSingle();
  return r ?? <String, dynamic>{};
}

Future<Map<String, dynamic>> fetchCustomerProfile() async {
  final r = await supa.from('customer_profiles').select().eq('user_id', myId).maybeSingle();
  return r ?? <String, dynamic>{};
}

Future<Set<String>> fetchWishlistIds() async {
  final rows = await supa.from('wishlist').select('service_id').eq('customer_id', myId);
  return rows.map((e) => e['service_id'] as String).toSet();
}

Future<void> toggleWishlist(String serviceId, bool add) async {
  if (add) {
    await supa.from('wishlist').upsert({'customer_id': myId, 'service_id': serviceId}, onConflict: 'customer_id,service_id');
  } else {
    await supa.from('wishlist').delete().eq('customer_id', myId).eq('service_id', serviceId);
  }
  bumpData();
}
