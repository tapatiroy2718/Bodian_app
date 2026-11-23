import 'package:flutter/material.dart';

import '../core/constants.dart';
import '../core/theme.dart';
import '../core/utils.dart';
import '../core/widgets.dart';

/// Create or edit a service listing with its venue details, photos and packages.
class ServiceEditorScreen extends StatefulWidget {
  final String? serviceId;
  const ServiceEditorScreen({super.key, this.serviceId});
  @override
  State<ServiceEditorScreen> createState() => _ServiceEditorScreenState();
}

class _ServiceEditorScreenState extends State<ServiceEditorScreen> {
  final _form = GlobalKey<FormState>();
  final _title = TextEditingController();
  final _description = TextEditingController();
  final _price = TextEditingController();
  final _city = TextEditingController();
  final _location = TextEditingController();
  final _facilities = TextEditingController();
  // venue
  final _minGuests = TextEditingController();
  final _maxGuests = TextEditingController();
  final _seating = TextEditingController();
  final _mapAddress = TextEditingController();
  final _lat = TextEditingController();
  final _lng = TextEditingController();
  bool? _isAc;
  bool _parking = false;
  bool _catering = false;
  bool _decoration = false;
  String? _indoorOutdoor;

  String? _category;
  String? _subcategory;
  bool _active = true;
  bool _categoryError = false;

  List<Map<String, dynamic>> _images = [];
  List<Map<String, dynamic>> _packages = [];
  bool _hadVenue = false;

  bool _loaded = false;
  Object? _loadError;
  bool _busy = false;
  bool _uploading = false;

  bool get _editing => widget.serviceId != null;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final c in [_title, _description, _price, _city, _location, _facilities, _minGuests, _maxGuests, _seating, _mapAddress, _lat, _lng]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loaded = false;
      _loadError = null;
    });
    try {
      if (_editing) {
        final s = await supa
            .from('services')
            .select('*, service_images(*), service_packages(*), venue_details(*)')
            .eq('id', widget.serviceId!)
            .single();
        _title.text = str(s['title']);
        _description.text = str(s['description']);
        _price.text = toD(s['starting_price']).toStringAsFixed(0);
        _city.text = str(s['city']);
        _location.text = str(s['location']);
        _facilities.text = asStrings(s['facilities']).join(', ');
        _category = s['category_id'] as String?;
        _subcategory = s['subcategory'] as String?;
        _active = s['is_active'] == true;
        _images = asList(s['service_images'])..sort((a, b) => toI(a['sort']).compareTo(toI(b['sort'])));
        _packages = asList(s['service_packages'])..sort((a, b) => toD(a['price']).compareTo(toD(b['price'])));
        final v = asMapOrNull(s['venue_details']);
        _hadVenue = v != null;
        if (v != null) {
          _isAc = v['is_ac'] as bool?;
          _minGuests.text = v['min_guests'] == null ? '' : '${toI(v['min_guests'])}';
          _maxGuests.text = v['max_guests'] == null ? '' : '${toI(v['max_guests'])}';
          _seating.text = str(v['seating']);
          _parking = v['parking'] == true;
          _catering = v['catering_available'] == true;
          _decoration = v['decoration_available'] == true;
          _indoorOutdoor = v['indoor_outdoor'] as String?;
          _mapAddress.text = str(v['map_address']);
          _lat.text = v['latitude'] == null ? '' : '${v['latitude']}';
          _lng.text = v['longitude'] == null ? '' : '${v['longitude']}';
        }
      } else {
        final v = await supa.from('vendor_profiles').select('category_id, city').eq('id', myId).maybeSingle();
        _category = v?['category_id'] as String?;
        _city.text = str(v?['city']);
      }
    } catch (e) {
      _loadError = e;
    }
    if (mounted) setState(() => _loaded = true);
  }

  Future<void> _reloadChildren() async {
    if (!_editing) return;
    try {
      final imgs = await supa.from('service_images').select().eq('service_id', widget.serviceId!).order('sort');
      final pk = await supa.from('service_packages').select().eq('service_id', widget.serviceId!).order('price');
      if (mounted) {
        setState(() {
          _images = imgs;
          _packages = pk;
        });
      }
    } catch (_) {}
  }

  Future<void> _save() async {
    final valid = _form.currentState!.validate();
    setState(() => _categoryError = _category == null);
    if (!valid || _category == null) {
      showSnack(context, 'Please fill in the required fields.', error: true);
      return;
    }
    setState(() => _busy = true);
    final values = <String, dynamic>{
      'vendor_id': myId,
      'title': _title.text.trim(),
      'category_id': _category,
      'subcategory': _subcategory,
      'description': nullIfEmpty(_description.text),
      'starting_price': double.tryParse(_price.text.trim()) ?? 0,
      'city': nullIfEmpty(_city.text),
      'location': nullIfEmpty(_location.text),
      'facilities': _facilities.text.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList(),
      'is_active': _active,
    };
    String? newId;
    final ok = await runAction(context, () async {
      final String id;
      if (_editing) {
        id = widget.serviceId!;
        await supa.from('services').update(values).eq('id', id);
      } else {
        final row = await supa.from('services').insert(values).select('id').single();
        id = row['id'] as String;
        newId = id;
      }
      if (_category == 'venues') {
        await supa.from('venue_details').upsert({
          'service_id': id,
          'is_ac': _isAc,
          'min_guests': int.tryParse(_minGuests.text.trim()),
          'max_guests': int.tryParse(_maxGuests.text.trim()),
          'seating': nullIfEmpty(_seating.text),
          'parking': _parking,
          'catering_available': _catering,
          'decoration_available': _decoration,
          'indoor_outdoor': _indoorOutdoor,
          'map_address': nullIfEmpty(_mapAddress.text),
          'latitude': double.tryParse(_lat.text.trim()),
          'longitude': double.tryParse(_lng.text.trim()),
        }, onConflict: 'service_id');
      } else if (_hadVenue) {
        await supa.from('venue_details').delete().eq('service_id', id);
      }
    }, success: _editing ? 'Service saved' : 'Service created. Now add photos and packages.');
    if (!mounted) return;
    setState(() => _busy = false);
    if (!ok) return;
    bumpData();
    if (newId != null) {
      Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => ServiceEditorScreen(serviceId: newId)));
    } else {
      _hadVenue = _category == 'venues';
    }
  }

  Future<void> _addPhotos() async {
    final files = await pickImages();
    if (files.isEmpty || !mounted) return;
    final room = 15 - _images.length;
    if (room <= 0) {
      showSnack(context, 'You can add up to 15 photos per service.', error: true);
      return;
    }
    setState(() => _uploading = true);
    var sort = _images.fold<int>(0, (m, e) => toI(e['sort']) > m ? toI(e['sort']) : m);
    await runAction(context, () async {
      for (final f in files.take(room)) {
        final up = await uploadImage(f, folder: 'services/${widget.serviceId}');
        sort++;
        await supa.from('service_images').insert({
          'service_id': widget.serviceId,
          'url': up.url,
          'storage_path': up.path,
          'sort': sort,
        });
      }
    }, success: 'Photos added');
    await _reloadChildren();
    bumpData();
    if (mounted) setState(() => _uploading = false);
  }

  Future<void> _deletePhoto(Map<String, dynamic> img) async {
    final ok = await runAction(context, () async {
      await supa.from('service_images').delete().eq('id', img['id'] as String);
      await removePublicFiles([img['storage_path'] as String?]);
    });
    if (ok) {
      await _reloadChildren();
      bumpData();
    }
  }

  Future<void> _makeCover(Map<String, dynamic> img) async {
    final minSort = _images.fold<int>(0, (m, e) => toI(e['sort']) < m ? toI(e['sort']) : m);
    final ok = await runAction(context, () async {
      await supa.from('service_images').update({'sort': minSort - 1}).eq('id', img['id'] as String);
    }, success: 'Cover photo updated');
    if (ok) {
      await _reloadChildren();
      bumpData();
    }
  }

  Future<void> _editPackage([Map<String, dynamic>? p]) async {
    final result = await Navigator.push<Map<String, dynamic>>(
      context,
      MaterialPageRoute(builder: (_) => PackageEditorScreen(package: p)),
    );
    if (result == null || !mounted) return;
    final ok = await runAction(context, () async {
      if (p == null) {
        await supa.from('service_packages').insert({...result, 'service_id': widget.serviceId});
      } else {
        await supa.from('service_packages').update(result).eq('id', p['id'] as String);
      }
    }, success: 'Package saved');
    if (ok) {
      await _reloadChildren();
      bumpData();
    }
  }

  Future<void> _deletePackage(Map<String, dynamic> p) async {
    final yes = await confirmDialog(context, 'Delete package?', str(p['name']), confirm: 'Delete', destructive: true);
    if (!yes || !mounted) return;
    final ok = await runAction(context, () async {
      await supa.from('service_packages').delete().eq('id', p['id'] as String);
    });
    if (ok) {
      await _reloadChildren();
      bumpData();
    }
  }

  Widget _section(String title, {Widget? trailing}) => Padding(
        padding: const EdgeInsets.only(top: 24, bottom: 8),
        child: Row(children: [
          Expanded(child: Text(title, style: Theme.of(context).textTheme.titleMedium)),
          if (trailing != null) trailing,
        ]),
      );

  @override
  Widget build(BuildContext context) {
    if (!_loaded) return Scaffold(appBar: AppBar(), body: const LoadingView());
    if (_loadError != null) {
      return Scaffold(appBar: AppBar(), body: ErrorView(message: friendlyError(_loadError), onRetry: _load));
    }
    final cat = _category == null ? null : categoryById(_category);
    final isVenue = _category == 'venues';
    return Scaffold(
      appBar: AppBar(title: Text(_editing ? 'Edit service' : 'New service')),
      body: Form(
        key: _form,
        child: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 32), children: [
          TextFormField(
            controller: _title,
            textCapitalization: TextCapitalization.sentences,
            validator: (v) => (v ?? '').trim().isEmpty ? 'Required' : null,
            decoration: inputDeco('Service name *', hint: 'e.g. Grand Banquet Hall, Bridal Makeup Package'),
          ),
          const SizedBox(height: 12),
          SelectField<String>(
            label: 'Category *',
            icon: Icons.category_outlined,
            value: _category,
            errorText: _categoryError ? 'Choose a category' : null,
            options: [for (final c in categories) (c.id, c.name)],
            onChanged: (v) => setState(() {
              _category = v;
              _subcategory = null;
              _categoryError = false;
            }),
          ),
          if (cat != null) ...[
            const SizedBox(height: 12),
            SelectField<String?>(
              label: 'Subcategory',
              icon: Icons.label_outline,
              value: _subcategory,
              placeholder: 'None',
              options: [(null, 'None'), for (final s in cat.subcategories) (s, s)],
              onChanged: (v) => setState(() => _subcategory = v),
            ),
          ],
          const SizedBox(height: 12),
          TextFormField(
            controller: _description,
            maxLines: 5,
            decoration: inputDeco('Description', hint: 'What is included, experience, style…'),
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _price,
            keyboardType: TextInputType.number,
            validator: (v) {
              final n = double.tryParse((v ?? '').trim());
              return (n == null || n < 0) ? 'Enter a starting price' : null;
            },
            decoration: inputDeco('Starting price (₹) *', icon: Icons.currency_rupee),
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _city,
            textCapitalization: TextCapitalization.words,
            decoration: inputDeco('City', icon: Icons.location_city),
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _location,
            decoration: inputDeco('Area / service location', icon: Icons.place_outlined, hint: 'e.g. Salt Lake, Kolkata'),
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _facilities,
            maxLines: 2,
            decoration: inputDeco('Facilities and services', helper: 'Separate with commas, e.g. Generator backup, Bridal room, Lift'),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Visible to customers'),
            subtitle: const Text('Turn off to hide this listing temporarily'),
            value: _active,
            onChanged: (v) => setState(() => _active = v),
          ),
          if (isVenue) ...[
            _section('Venue details'),
            SelectField<bool?>(
              label: 'AC / Non-AC',
              icon: Icons.ac_unit,
              value: _isAc,
              placeholder: 'Not specified',
              options: const [(null, 'Not specified'), (true, 'AC'), (false, 'Non-AC')],
              onChanged: (v) => setState(() => _isAc = v),
            ),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(
                child: TextFormField(
                    controller: _minGuests, keyboardType: TextInputType.number, decoration: inputDeco('Min guests')),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextFormField(
                    controller: _maxGuests, keyboardType: TextInputType.number, decoration: inputDeco('Max guests')),
              ),
            ]),
            const SizedBox(height: 12),
            TextFormField(
                controller: _seating, decoration: inputDeco('Seating arrangement', hint: 'e.g. Round tables, theatre, floating')),
            const SizedBox(height: 12),
            SelectField<String?>(
              label: 'Indoor / outdoor',
              icon: Icons.deck_outlined,
              value: _indoorOutdoor,
              placeholder: 'Not specified',
              options: const [(null, 'Not specified'), ('indoor', 'Indoor'), ('outdoor', 'Outdoor'), ('both', 'Both')],
              onChanged: (v) => setState(() => _indoorOutdoor = v),
            ),
            SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Parking available'),
                value: _parking,
                onChanged: (v) => setState(() => _parking = v)),
            SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('In-house catering'),
                value: _catering,
                onChanged: (v) => setState(() => _catering = v)),
            SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('In-house decoration'),
                value: _decoration,
                onChanged: (v) => setState(() => _decoration = v)),
            const SizedBox(height: 8),
            TextFormField(
                controller: _mapAddress,
                decoration: inputDeco('Address for Google Maps', icon: Icons.map_outlined)),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(
                child: TextFormField(
                  controller: _lat,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                  decoration: inputDeco('Latitude (optional)'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextFormField(
                  controller: _lng,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                  decoration: inputDeco('Longitude (optional)'),
                ),
              ),
            ]),
          ],
          const SizedBox(height: 20),
          ElevatedButton(
            onPressed: _busy ? null : _save,
            child: _busy
                ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : Text(_editing ? 'Save details' : 'Create service'),
          ),
          if (!_editing)
            const Padding(
              padding: EdgeInsets.only(top: 12),
              child: Text('After creating the service you can add photos and packages.',
                  textAlign: TextAlign.center, style: TextStyle(color: kMuted)),
            ),
          if (_editing) ...[
            _section('Photos (${_images.length}/15)',
                trailing: TextButton.icon(
                  onPressed: _uploading ? null : _addPhotos,
                  icon: const Icon(Icons.add_photo_alternate_outlined),
                  label: const Text('Add'),
                )),
            if (_uploading) const LinearProgressIndicator(color: kMaroon),
            if (_images.isEmpty)
              const Text('Listings with photos get far more enquiries. The first photo is the cover.',
                  style: TextStyle(color: kMuted)),
            GridView.count(
              crossAxisCount: 3,
              shrinkWrap: true,
              mainAxisSpacing: 6,
              crossAxisSpacing: 6,
              physics: const NeverScrollableScrollPhysics(),
              children: [
                for (var i = 0; i < _images.length; i++)
                  GestureDetector(
                    onTap: () async {
                      final img = _images[i];
                      final action = await showModalBottomSheet<String>(
                        context: context,
                        showDragHandle: true,
                        builder: (ctx) => SafeArea(
                          child: Column(mainAxisSize: MainAxisSize.min, children: [
                            if (i != 0)
                              ListTile(
                                leading: const Icon(Icons.star_outline),
                                title: const Text('Make cover photo'),
                                onTap: () => Navigator.pop(ctx, 'cover'),
                              ),
                            ListTile(
                              leading: const Icon(Icons.delete_outline, color: Color(0xFFB3261E)),
                              title: const Text('Delete photo'),
                              onTap: () => Navigator.pop(ctx, 'delete'),
                            ),
                          ]),
                        ),
                      );
                      if (action == 'cover') await _makeCover(img);
                      if (action == 'delete') await _deletePhoto(img);
                    },
                    child: Stack(fit: StackFit.expand, children: [
                      ClipRRect(borderRadius: BorderRadius.circular(10), child: NetImage(str(_images[i]['url']))),
                      if (i == 0)
                        Positioned(
                          left: 4,
                          top: 4,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(color: kMaroon, borderRadius: BorderRadius.circular(8)),
                            child: const Text('Cover', style: TextStyle(color: Colors.white, fontSize: 10)),
                          ),
                        ),
                    ]),
                  ),
              ],
            ),
            _section('Packages (${_packages.length})',
                trailing: TextButton.icon(
                  onPressed: () => _editPackage(),
                  icon: const Icon(Icons.add),
                  label: const Text('Add'),
                )),
            if (_packages.isEmpty)
              const Text('Add packages like Silver, Gold and Platinum with what is included.', style: TextStyle(color: kMuted)),
            for (final p in _packages)
              AppCard(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.fromLTRB(16, 8, 4, 8),
                child: Row(children: [
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(str(p['name']), style: const TextStyle(fontWeight: FontWeight.w600)),
                      Text(
                        '${money(p['price'])}${p['is_active'] == false ? ' · hidden' : ''}'
                        '${asStrings(p['included_services']).isEmpty ? '' : ' · ${asStrings(p['included_services']).length} items'}',
                        style: const TextStyle(color: kMuted, fontSize: 12),
                      ),
                    ]),
                  ),
                  IconButton(icon: const Icon(Icons.edit_outlined), onPressed: () => _editPackage(p)),
                  IconButton(
                      icon: const Icon(Icons.delete_outline, color: Color(0xFFB3261E)), onPressed: () => _deletePackage(p)),
                ]),
              ),
          ],
        ]),
      ),
    );
  }
}

class PackageEditorScreen extends StatefulWidget {
  final Map<String, dynamic>? package;
  const PackageEditorScreen({super.key, this.package});
  @override
  State<PackageEditorScreen> createState() => _PackageEditorScreenState();
}

class _PackageEditorScreenState extends State<PackageEditorScreen> {
  final _form = GlobalKey<FormState>();
  late final _name = TextEditingController(text: str(widget.package?['name']));
  late final _description = TextEditingController(text: str(widget.package?['description']));
  late final _included = TextEditingController(text: asStrings(widget.package?['included_services']).join('\n'));
  late final _price = TextEditingController(
      text: widget.package == null ? '' : toD(widget.package!['price']).toStringAsFixed(0));
  late final _charges = TextEditingController(text: str(widget.package?['additional_charges']));
  late final _terms = TextEditingController(text: str(widget.package?['terms']));
  late bool _active = widget.package?['is_active'] != false;

  @override
  void dispose() {
    for (final c in [_name, _description, _included, _price, _charges, _terms]) {
      c.dispose();
    }
    super.dispose();
  }

  void _save() {
    if (!_form.currentState!.validate()) return;
    Navigator.pop(context, <String, dynamic>{
      'name': _name.text.trim(),
      'description': nullIfEmpty(_description.text),
      'included_services': _included.text.split('\n').map((e) => e.trim()).where((e) => e.isNotEmpty).toList(),
      'price': double.tryParse(_price.text.trim()) ?? 0,
      'additional_charges': nullIfEmpty(_charges.text),
      'terms': nullIfEmpty(_terms.text),
      'is_active': _active,
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.package == null ? 'New package' : 'Edit package')),
      body: Form(
        key: _form,
        child: ListView(padding: const EdgeInsets.all(16), children: [
          TextFormField(
            controller: _name,
            textCapitalization: TextCapitalization.words,
            validator: (v) => (v ?? '').trim().isEmpty ? 'Required' : null,
            decoration: inputDeco('Package name *', hint: 'e.g. Gold package'),
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _price,
            keyboardType: TextInputType.number,
            validator: (v) {
              final n = double.tryParse((v ?? '').trim());
              return (n == null || n < 0) ? 'Enter a price' : null;
            },
            decoration: inputDeco('Price (₹) *', icon: Icons.currency_rupee),
          ),
          const SizedBox(height: 12),
          TextFormField(controller: _description, maxLines: 3, decoration: inputDeco('Package description')),
          const SizedBox(height: 12),
          TextFormField(
            controller: _included,
            maxLines: 6,
            decoration: inputDeco('Included services', helper: 'One per line, e.g.\nStage decoration\n200 plates veg menu'),
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _charges,
            maxLines: 2,
            decoration: inputDeco('Additional charges', hint: 'e.g. ₹500 per extra plate, GST extra'),
          ),
          const SizedBox(height: 12),
          TextFormField(controller: _terms, maxLines: 4, decoration: inputDeco('Terms and conditions')),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Show this package to customers'),
            value: _active,
            onChanged: (v) => setState(() => _active = v),
          ),
          const SizedBox(height: 12),
          ElevatedButton(onPressed: _save, child: const Text('Save package')),
        ]),
      ),
    );
  }
}
