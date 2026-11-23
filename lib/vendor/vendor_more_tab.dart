import 'package:flutter/material.dart';

import '../core/constants.dart';
import '../core/theme.dart';
import '../core/utils.dart';
import '../core/widgets.dart';
import '../customer/service_detail_screen.dart' show ReviewTile;
import '../shared/account.dart';
import '../shared/notifications_screen.dart';
import 'vendor_onboarding_screen.dart';
import 'vendor_overview_tab.dart';

class VendorMoreTab extends StatelessWidget {
  const VendorMoreTab({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('More')),
      body: Loader<Map<String, dynamic>>(
        load: fetchMyVendor,
        builder: (context, v, reload) => RefreshIndicator(
          onRefresh: reload,
          child: ListView(padding: const EdgeInsets.all(16), children: [
            AppCard(
              child: Row(children: [
                CircleAvatar(
                  radius: 28,
                  backgroundColor: kCream,
                  backgroundImage: str(v['logo_url']).isEmpty ? null : NetworkImage(str(v['logo_url'])),
                  child: str(v['logo_url']).isEmpty ? const Icon(Icons.storefront, color: kMaroon) : null,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(str(v['business_name']), style: Theme.of(context).textTheme.titleMedium),
                    Text('${categoryById(v['category_id'] as String?).name} · ${str(v['city'])}',
                        style: const TextStyle(color: kMuted, fontSize: 13)),
                    const SizedBox(height: 4),
                    VerifiedBadge(v['verification_status'] as String?),
                  ]),
                ),
              ]),
            ),
            const SizedBox(height: 12),
            AppCard(
              padding: EdgeInsets.zero,
              child: Column(children: [
                _tile(context, Icons.storefront_outlined, 'Business profile',
                    () => Navigator.push(context, MaterialPageRoute(builder: (_) => VendorOnboardingScreen(existing: v)))),
                _tile(context, Icons.verified_outlined, 'Verification',
                    () => Navigator.push(context, MaterialPageRoute(builder: (_) => const VerificationScreen()))),
                _tile(context, Icons.star_outline, 'Reviews',
                    () => Navigator.push(context, MaterialPageRoute(builder: (_) => const VendorReviewsScreen()))),
                _tile(
                    context,
                    Icons.notifications_outlined,
                    'Notifications',
                    () => Navigator.push(context,
                        MaterialPageRoute(builder: (_) => const NotificationsScreen(onOpenBooking: openVendorBooking)))),
              ]),
            ),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.only(left: 4, bottom: 8),
              child: Text('Settings', style: Theme.of(context).textTheme.titleMedium),
            ),
            const AccountSection(),
          ]),
        ),
      ),
    );
  }

  Widget _tile(BuildContext context, IconData icon, String title, VoidCallback onTap) => ListTile(
        leading: Icon(icon, color: kMaroon),
        title: Text(title),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      );
}

// ---------------------------------------------------------------- verification

class _VerifData {
  final Map<String, dynamic> vendor;
  final List<Map<String, dynamic>> documents;
  final List<Map<String, dynamic>> history;
  _VerifData(this.vendor, this.documents, this.history);
}

class VerificationScreen extends StatefulWidget {
  const VerificationScreen({super.key});
  @override
  State<VerificationScreen> createState() => _VerificationScreenState();
}

class _VerificationScreenState extends State<VerificationScreen> {
  bool _uploading = false;

  Future<_VerifData> _load() async {
    final v = await fetchMyVendor();
    final docs = await supa.from('vendor_documents').select().eq('vendor_id', myId).order('uploaded_at', ascending: false);
    final hist = await supa.from('vendor_verifications').select().eq('vendor_id', myId).order('created_at', ascending: false);
    return _VerifData(v, docs, hist);
  }

  Future<void> _upload() async {
    final type = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Padding(
            padding: EdgeInsets.only(bottom: 8),
            child: Text('Which document are you uploading?', style: TextStyle(fontWeight: FontWeight.w600)),
          ),
          for (final e in documentTypes.entries)
            ListTile(
              leading: const Icon(Icons.description_outlined),
              title: Text(e.value),
              onTap: () => Navigator.pop(ctx, e.key),
            ),
        ]),
      ),
    );
    if (type == null || !mounted) return;
    final file = await chooseImageSource(context);
    if (file == null || !mounted) return;
    setState(() => _uploading = true);
    final ok = await runAction(context, () async {
      final up = await uploadImage(file, folder: 'documents', bucket: 'vendor-documents', maxMb: 10);
      await supa.from('vendor_documents').insert({
        'vendor_id': myId,
        'doc_type': type,
        'file_path': up.path,
        'file_name': file.name,
        'mime_type': up.mime,
        'size_bytes': up.size,
      });
    }, success: 'Document uploaded securely');
    if (mounted) setState(() => _uploading = false);
    if (ok) bumpData();
  }

  Future<void> _view(Map<String, dynamic> doc) async {
    try {
      final url = await supa.storage.from('vendor-documents').createSignedUrl(str(doc['file_path']), 120);
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (ctx) => Dialog(
          insetPadding: const EdgeInsets.all(12),
          clipBehavior: Clip.antiAlias,
          child: InteractiveViewer(child: NetImage(url, fit: BoxFit.contain)),
        ),
      );
    } catch (e) {
      if (mounted) showSnack(context, friendlyError(e), error: true);
    }
  }

  Future<void> _delete(Map<String, dynamic> doc) async {
    final yes = await confirmDialog(context, 'Delete document?', documentTypes[doc['doc_type']] ?? 'Document',
        confirm: 'Delete', destructive: true);
    if (!yes || !mounted) return;
    final ok = await runAction(context, () async {
      await supa.storage.from('vendor-documents').remove([str(doc['file_path'])]);
      await supa.from('vendor_documents').delete().eq('id', doc['id'] as String);
    });
    if (ok) bumpData();
  }

  Future<void> _requestReview() async {
    final ok = await runAction(context, () async {
      await supa.rpc('request_verification_review');
    }, success: 'Sent for review');
    if (ok) bumpData();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Verification')),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: kMaroon,
        foregroundColor: Colors.white,
        onPressed: _uploading ? null : _upload,
        icon: _uploading
            ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
            : const Icon(Icons.upload_file),
        label: const Text('Upload document'),
      ),
      body: Loader<_VerifData>(
        load: _load,
        builder: (context, d, reload) {
          final status = str(d.vendor['verification_status'], 'pending');
          final note = str(d.vendor['verification_note']);
          final (IconData icon, Color color, String title, String body) = switch (status) {
            'verified' => (
                Icons.verified,
                kSuccess,
                'Your business is verified',
                'Customers can find your services in the marketplace and see the verified badge.'
              ),
            'rejected' => (
                Icons.error_outline,
                const Color(0xFFB3261E),
                'Verification not approved',
                note.isEmpty ? 'Please upload clearer or additional documents and request a review.' : note
              ),
            _ => (
                Icons.hourglass_top,
                kWarning,
                'Verification pending',
                'Our team reviews your documents, usually within 2 working days. Your listings become visible once verified.'
              ),
          };
          return RefreshIndicator(
            onRefresh: reload,
            child: ListView(padding: const EdgeInsets.fromLTRB(16, 16, 16, 96), children: [
              AppCard(
                color: color.withAlpha(22),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Icon(icon, color: color, size: 32),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(title, style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(height: 4),
                      Text(body),
                    ]),
                  ),
                ]),
              ),
              if (status == 'rejected') ...[
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: d.documents.isEmpty ? null : _requestReview,
                  icon: const Icon(Icons.send),
                  label: const Text('Request review again'),
                ),
              ],
              const SizedBox(height: 16),
              Text('Accepted documents', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 6),
              const Text(
                'Trade licence, business registration, business card or other supporting documents. '
                'Take a clear photo. Documents are private: only you and the Bodiana verification team can see them.',
                style: TextStyle(color: kMuted),
              ),
              const SizedBox(height: 16),
              Text('Your documents (${d.documents.length})', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              if (d.documents.isEmpty)
                const AppCard(child: Text('No documents uploaded yet.', style: TextStyle(color: kMuted))),
              for (final doc in d.documents)
                AppCard(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.fromLTRB(16, 4, 4, 4),
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.description, color: kMaroon),
                    title: Text(documentTypes[doc['doc_type']] ?? 'Document'),
                    subtitle: Text('Uploaded ${fmtDate(doc['uploaded_at'])}'),
                    onTap: () => _view(doc),
                    trailing: IconButton(
                      icon: const Icon(Icons.delete_outline, color: Color(0xFFB3261E)),
                      onPressed: () => _delete(doc),
                    ),
                  ),
                ),
              if (d.history.isNotEmpty) ...[
                const SizedBox(height: 16),
                Text('History', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                for (final h in d.history)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: StatusChip(str(h['status'])),
                    title: Text(str(h['note'], '—')),
                    subtitle: Text(fmtDateTime(h['created_at'])),
                  ),
              ],
            ]),
          );
        },
      ),
    );
  }
}

// ---------------------------------------------------------------- reviews

class VendorReviewsScreen extends StatelessWidget {
  const VendorReviewsScreen({super.key});

  Future<List<Map<String, dynamic>>> _load() async {
    return await supa.from('reviews').select().eq('vendor_id', myId).order('created_at', ascending: false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Reviews')),
      body: Loader<List<Map<String, dynamic>>>(
        load: _load,
        builder: (context, items, reload) {
          if (items.isEmpty) {
            return const Center(
              child: EmptyView(
                icon: Icons.star_outline,
                title: 'No reviews yet',
                subtitle: 'Customers can review you after you mark their booking as completed.',
              ),
            );
          }
          final avg = items.fold<double>(0, (s, r) => s + toD(r['rating'])) / items.length;
          return RefreshIndicator(
            onRefresh: reload,
            child: ListView(padding: const EdgeInsets.all(16), children: [
              AppCard(
                color: kCream,
                child: Row(children: [
                  Text(avg.toStringAsFixed(1), style: Theme.of(context).textTheme.headlineMedium),
                  const SizedBox(width: 8),
                  const Icon(Icons.star_rounded, color: kGold, size: 32),
                  const Spacer(),
                  Text('${items.length} review${items.length == 1 ? '' : 's'}'),
                ]),
              ),
              const SizedBox(height: 12),
              for (final r in items) ReviewTile(r),
            ]),
          );
        },
      ),
    );
  }
}
