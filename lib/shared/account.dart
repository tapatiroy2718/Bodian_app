import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../auth/auth_screens.dart';
import '../core/config.dart';
import '../core/theme.dart';
import '../core/utils.dart';
import '../core/widgets.dart';

/// Round avatar that uploads a new profile photo when tapped.
class AvatarPicker extends StatefulWidget {
  final String? url;
  final String name;
  const AvatarPicker({super.key, this.url, required this.name});
  @override
  State<AvatarPicker> createState() => _AvatarPickerState();
}

class _AvatarPickerState extends State<AvatarPicker> {
  bool _busy = false;
  String? _url;

  Future<void> _pick() async {
    final file = await pickImage();
    if (file == null || !mounted) return;
    setState(() => _busy = true);
    await runAction(context, () async {
      final up = await uploadImage(file, folder: 'avatar');
      await supa.from('profiles').update({'avatar_url': up.url}).eq('id', myId);
      await removePublicFiles([publicPathFromUrl(_url ?? widget.url)]);
      _url = up.url;
    }, success: 'Photo updated');
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final url = nullIfEmpty(_url ?? widget.url);
    return GestureDetector(
      onTap: _busy ? null : _pick,
      child: Stack(children: [
        CircleAvatar(
          radius: 32,
          backgroundColor: kCream,
          backgroundImage: url == null ? null : NetworkImage(url),
          child: url == null
              ? Text(widget.name.isEmpty ? '?' : widget.name[0].toUpperCase(),
                  style: const TextStyle(fontSize: 24, color: kMaroon, fontWeight: FontWeight.bold))
              : null,
        ),
        Positioned(
          right: 0,
          bottom: 0,
          child: CircleAvatar(
            radius: 11,
            backgroundColor: kMaroon,
            child: _busy
                ? const SizedBox(width: 10, height: 10, child: CircularProgressIndicator(strokeWidth: 1.5, color: Colors.white))
                : const Icon(Icons.camera_alt, size: 12, color: Colors.white),
          ),
        ),
      ]),
    );
  }
}

class EditProfileScreen extends StatefulWidget {
  final Map<String, dynamic> profile;
  const EditProfileScreen({super.key, required this.profile});
  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  late final _name = TextEditingController(text: str(widget.profile['full_name']));
  late final _phone = TextEditingController(text: str(widget.profile['phone']));
  bool _busy = false;

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_name.text.trim().isEmpty) {
      showSnack(context, 'Name cannot be empty', error: true);
      return;
    }
    setState(() => _busy = true);
    final ok = await runAction(context, () async {
      await supa.from('profiles').update({
        'full_name': _name.text.trim(),
        'phone': nullIfEmpty(_phone.text),
      }).eq('id', myId);
    }, success: 'Profile saved');
    if (!mounted) return;
    setState(() => _busy = false);
    if (ok) {
      bumpData();
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Edit profile')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        TextField(
          controller: _name,
          textCapitalization: TextCapitalization.words,
          decoration: inputDeco('Full name', icon: Icons.person_outline),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _phone,
          keyboardType: TextInputType.phone,
          decoration: inputDeco('Phone number', icon: Icons.phone_outlined),
        ),
        const SizedBox(height: 12),
        TextField(
          enabled: false,
          controller: TextEditingController(text: str(widget.profile['email'])),
          decoration: inputDeco('Email', icon: Icons.mail_outline),
        ),
        const SizedBox(height: 20),
        ElevatedButton(onPressed: _busy ? null : _save, child: const Text('Save')),
      ]),
    );
  }
}

/// Password, privacy policy, sign out and account deletion.
class AccountSection extends StatelessWidget {
  const AccountSection({super.key});

  Future<void> _delete(BuildContext context) async {
    final first = await confirmDialog(
      context,
      'Delete your account?',
      'This permanently deletes your profile, wedding plans, wishlist, bookings, services and uploaded photos. '
          'This cannot be undone.',
      confirm: 'Continue',
      destructive: true,
    );
    if (!first || !context.mounted) return;
    final typed = await promptText(context, 'Type DELETE to confirm', label: 'DELETE', maxLines: 1);
    if (typed?.toUpperCase() != 'DELETE' || !context.mounted) return;

    await runAction(context, () async {
      // Remove uploaded files first (storage files are not deleted by the database).
      final paths = <String?>[];
      try {
        final p = await supa.from('profiles').select('avatar_url').eq('id', myId).maybeSingle();
        paths.add(publicPathFromUrl(p?['avatar_url'] as String?));
        final v = await supa.from('vendor_profiles').select('logo_url, cover_url, gallery').eq('id', myId).maybeSingle();
        if (v != null) {
          paths.add(publicPathFromUrl(v['logo_url'] as String?));
          paths.add(publicPathFromUrl(v['cover_url'] as String?));
          for (final g in asStrings(v['gallery'])) {
            paths.add(publicPathFromUrl(g));
          }
          final imgs = await supa.from('service_images').select('storage_path, services!inner(vendor_id)').eq('services.vendor_id', myId);
          for (final i in imgs) {
            paths.add(i['storage_path'] as String?);
          }
          final docs = await supa.from('vendor_documents').select('file_path').eq('vendor_id', myId);
          final docPaths = docs.map((d) => d['file_path'] as String).toList();
          if (docPaths.isNotEmpty) await supa.storage.from('vendor-documents').remove(docPaths);
        }
      } catch (_) {}
      await removePublicFiles(paths);
      await supa.rpc('delete_my_account');
      try {
        await supa.auth.signOut();
      } catch (_) {
        await supa.auth.signOut(scope: SignOutScope.local);
      }
    }, success: 'Your account has been deleted');
  }

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: EdgeInsets.zero,
      child: Column(children: [
        ListTile(
          leading: const Icon(Icons.lock_outline, color: kMaroon),
          title: const Text('Change password'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ResetPasswordScreen())),
        ),
        if (AppConfig.privacyPolicyUrl.isNotEmpty)
          ListTile(
            leading: const Icon(Icons.privacy_tip_outlined, color: kMaroon),
            title: const Text('Privacy policy'),
            trailing: const Icon(Icons.open_in_new, size: 18),
            onTap: () => openUrl(context, AppConfig.privacyPolicyUrl),
          ),
        ListTile(
          leading: const Icon(Icons.logout, color: kMaroon),
          title: const Text('Sign out'),
          onTap: () async {
            if (await confirmDialog(context, 'Sign out?', 'You can log in again any time.', confirm: 'Sign out')) {
              await supa.auth.signOut();
            }
          },
        ),
        ListTile(
          leading: const Icon(Icons.delete_forever_outlined, color: Color(0xFFB3261E)),
          title: const Text('Delete account', style: TextStyle(color: Color(0xFFB3261E))),
          onTap: () => _delete(context),
        ),
      ]),
    );
  }
}

/// Picks an image from camera or gallery via a small chooser sheet.
Future<XFile?> chooseImageSource(BuildContext context) async {
  final source = await showModalBottomSheet<ImageSource>(
    context: context,
    showDragHandle: true,
    builder: (ctx) => SafeArea(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        ListTile(
          leading: const Icon(Icons.photo_camera_outlined),
          title: const Text('Take a photo'),
          onTap: () => Navigator.pop(ctx, ImageSource.camera),
        ),
        ListTile(
          leading: const Icon(Icons.photo_library_outlined),
          title: const Text('Choose from gallery'),
          onTap: () => Navigator.pop(ctx, ImageSource.gallery),
        ),
      ]),
    ),
  );
  if (source == null) return null;
  return pickImage(source: source);
}
