import 'package:flutter/material.dart';

import '../auth/auth_gate.dart';
import '../core/constants.dart';
import '../core/data.dart';
import '../core/theme.dart';
import '../core/utils.dart';
import '../core/widgets.dart';
import '../shared/account.dart';

/// Business profile form. Used for first-time vendor onboarding and for editing later.
class VendorOnboardingScreen extends StatefulWidget {
  final Map<String, dynamic>? existing;
  const VendorOnboardingScreen({super.key, this.existing});
  bool get editing => existing != null;
  @override
  State<VendorOnboardingScreen> createState() => _VendorOnboardingScreenState();
}

class _VendorOnboardingScreenState extends State<VendorOnboardingScreen> {
  final _form = GlobalKey<FormState>();
  final _owner = TextEditingController();
  final _phone = TextEditingController();
  final _whatsapp = TextEditingController();
  final _email = TextEditingController();
  final _business = TextEditingController();
  final _address = TextEditingController();
  final _city = TextEditingController();
  final _description = TextEditingController();
  String? _category;
  String? _logo;
  String? _cover;
  List<String> _gallery = [];
  final List<String> _uploadedThisSession = [];
  bool _uploading = false;
  bool _busy = false;
  bool _loaded = false;
  bool _categoryError = false;

  @override
  void initState() {
    super.initState();
    _prefill();
  }

  Future<void> _prefill() async {
    try {
      final p = await fetchMyProfile();
      _owner.text = str(p['full_name']);
      _phone.text = str(p['phone']);
      _email.text = str(p['email']);
      final v = widget.existing;
      if (v != null) {
        _owner.text = str(v['owner_name'], _owner.text);
        _phone.text = str(v['phone'], _phone.text);
        _whatsapp.text = str(v['whatsapp']);
        _email.text = str(v['email'], _email.text);
        _business.text = str(v['business_name']);
        _address.text = str(v['address']);
        _city.text = str(v['city']);
        _description.text = str(v['description']);
        _category = v['category_id'] as String?;
        _logo = nullIfEmpty(v['logo_url'] as String?);
        _cover = nullIfEmpty(v['cover_url'] as String?);
        _gallery = asStrings(v['gallery']);
      }
    } catch (_) {}
    if (mounted) setState(() => _loaded = true);
  }

  @override
  void dispose() {
    for (final c in [_owner, _phone, _whatsapp, _email, _business, _address, _city, _description]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<String?> _uploadOne(String folder) async {
    final file = await chooseImageSource(context);
    if (file == null || !mounted) return null;
    setState(() => _uploading = true);
    String? url;
    await runAction(context, () async {
      final up = await uploadImage(file, folder: folder);
      _uploadedThisSession.add(up.path);
      url = up.url;
    });
    if (mounted) setState(() => _uploading = false);
    return url;
  }

  Future<void> _addGallery() async {
    final files = await pickImages();
    if (files.isEmpty || !mounted) return;
    final room = 12 - _gallery.length;
    if (room <= 0) {
      showSnack(context, 'You can add up to 12 portfolio photos.', error: true);
      return;
    }
    setState(() => _uploading = true);
    await runAction(context, () async {
      for (final f in files.take(room)) {
        final up = await uploadImage(f, folder: 'gallery');
        _uploadedThisSession.add(up.path);
        if (mounted) setState(() => _gallery.add(up.url));
      }
    });
    if (mounted) setState(() => _uploading = false);
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
      'business_name': _business.text.trim(),
      'category_id': _category,
      'owner_name': _owner.text.trim(),
      'phone': nullIfEmpty(_phone.text),
      'whatsapp': nullIfEmpty(_whatsapp.text),
      'email': nullIfEmpty(_email.text),
      'address': nullIfEmpty(_address.text),
      'city': nullIfEmpty(_city.text),
      'description': nullIfEmpty(_description.text),
      'logo_url': _logo,
      'cover_url': _cover,
      'gallery': _gallery,
    };
    final ok = await runAction(context, () async {
      await supa.from('profiles').update({
        'full_name': _owner.text.trim(),
        'phone': nullIfEmpty(_phone.text),
      }).eq('id', myId);
      if (widget.editing) {
        await supa.from('vendor_profiles').update(values).eq('id', myId);
      } else {
        await supa.from('vendor_profiles').insert({...values, 'id': myId});
      }
    }, success: widget.editing ? 'Business profile saved' : 'Welcome to Bodiana!');
    if (!mounted) return;
    setState(() => _busy = false);
    if (!ok) return;
    if (widget.editing) {
      // Clean up images that were replaced or removed.
      final keep = {publicPathFromUrl(_logo), publicPathFromUrl(_cover), ..._gallery.map(publicPathFromUrl)};
      final old = widget.existing!;
      final previous = [
        publicPathFromUrl(old['logo_url'] as String?),
        publicPathFromUrl(old['cover_url'] as String?),
        ...asStrings(old['gallery']).map(publicPathFromUrl),
      ];
      await removePublicFiles(previous.where((p) => p != null && !keep.contains(p)));
      bumpData();
      if (mounted) Navigator.pop(context);
    } else {
      gateRefresh.value++;
    }
  }

  Widget _imageBox({required String label, required String? url, required VoidCallback onPick, double height = 140, double? width}) {
    return InkWell(
      onTap: _uploading ? null : onPick,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        height: height,
        width: width,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFE6D9D2)),
        ),
        clipBehavior: Clip.antiAlias,
        child: url == null
            ? Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                const Icon(Icons.add_a_photo_outlined, color: kMaroon),
                const SizedBox(height: 4),
                Text(label, textAlign: TextAlign.center, style: const TextStyle(fontSize: 12, color: kMuted)),
              ])
            : NetImage(url, width: width, height: height),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) return const Scaffold(body: LoadingView());
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.editing ? 'Business profile' : 'Set up your business'),
        actions: [
          if (!widget.editing) TextButton(onPressed: () => supa.auth.signOut(), child: const Text('Sign out')),
        ],
      ),
      body: Form(
        key: _form,
        child: ListView(padding: const EdgeInsets.all(16), children: [
          if (!widget.editing)
            const AppCard(
              color: kCream,
              margin: EdgeInsets.only(bottom: 16),
              child: Text(
                'Tell customers about your business. After you save, add your services and upload documents '
                'for verification. Only verified businesses appear in the marketplace.',
              ),
            ),
          Text('Photos', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          _imageBox(
            label: 'Cover photo',
            url: _cover,
            onPick: () async {
              final u = await _uploadOne('cover');
              if (u != null) setState(() => _cover = u);
            },
          ),
          const SizedBox(height: 10),
          Row(children: [
            _imageBox(
              label: 'Logo',
              url: _logo,
              width: 96,
              height: 96,
              onPick: () async {
                final u = await _uploadOne('logo');
                if (u != null) setState(() => _logo = u);
              },
            ),
            const SizedBox(width: 12),
            if (_uploading) const Expanded(child: LinearProgressIndicator(color: kMaroon)),
          ]),
          const SizedBox(height: 20),
          Text('Owner details', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          TextFormField(
            controller: _owner,
            textCapitalization: TextCapitalization.words,
            validator: (v) => (v ?? '').trim().isEmpty ? 'Required' : null,
            decoration: inputDeco('Owner name *', icon: Icons.person_outline),
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _phone,
            keyboardType: TextInputType.phone,
            decoration: inputDeco('Contact number', icon: Icons.phone_outlined, helper: 'Shown to customers'),
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _whatsapp,
            keyboardType: TextInputType.phone,
            decoration: inputDeco('WhatsApp number', icon: Icons.chat_outlined, helper: 'Leave empty to use the contact number'),
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _email,
            keyboardType: TextInputType.emailAddress,
            decoration: inputDeco('Business email', icon: Icons.mail_outline),
          ),
          const SizedBox(height: 20),
          Text('Business details', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          TextFormField(
            controller: _business,
            textCapitalization: TextCapitalization.words,
            validator: (v) => (v ?? '').trim().isEmpty ? 'Required' : null,
            decoration: inputDeco('Business name *', icon: Icons.storefront_outlined),
          ),
          const SizedBox(height: 12),
          SelectField<String>(
            label: 'Business category *',
            icon: Icons.category_outlined,
            value: _category,
            errorText: _categoryError ? 'Choose a category' : null,
            options: [for (final c in categories) (c.id, c.name)],
            onChanged: (v) => setState(() {
              _category = v;
              _categoryError = false;
            }),
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _address,
            maxLines: 2,
            decoration: inputDeco('Business address', icon: Icons.home_work_outlined),
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _city,
            textCapitalization: TextCapitalization.words,
            validator: (v) => (v ?? '').trim().isEmpty ? 'Required' : null,
            decoration: inputDeco('City *', icon: Icons.location_city),
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _description,
            maxLines: 5,
            decoration: inputDeco('Business description', hint: 'Experience, speciality, what makes you different'),
          ),
          const SizedBox(height: 20),
          Row(children: [
            Expanded(child: Text('Portfolio (${_gallery.length}/12)', style: Theme.of(context).textTheme.titleMedium)),
            TextButton.icon(
              onPressed: _uploading ? null : _addGallery,
              icon: const Icon(Icons.add_photo_alternate_outlined),
              label: const Text('Add photos'),
            ),
          ]),
          const SizedBox(height: 8),
          if (_gallery.isEmpty)
            const Text('Add photos of your past wedding work.', style: TextStyle(color: kMuted))
          else
            GridView.count(
              crossAxisCount: 3,
              shrinkWrap: true,
              mainAxisSpacing: 6,
              crossAxisSpacing: 6,
              physics: const NeverScrollableScrollPhysics(),
              children: [
                for (final u in _gallery)
                  Stack(fit: StackFit.expand, children: [
                    ClipRRect(borderRadius: BorderRadius.circular(10), child: NetImage(u)),
                    Positioned(
                      right: 2,
                      top: 2,
                      child: InkWell(
                        onTap: () => setState(() => _gallery.remove(u)),
                        child: const CircleAvatar(radius: 12, backgroundColor: Colors.black54, child: Icon(Icons.close, size: 14, color: Colors.white)),
                      ),
                    ),
                  ]),
              ],
            ),
          const SizedBox(height: 24),
          ElevatedButton(
            onPressed: (_busy || _uploading) ? null : _save,
            child: _busy
                ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : Text(widget.editing ? 'Save changes' : 'Create business profile'),
          ),
        ]),
      ),
    );
  }
}
