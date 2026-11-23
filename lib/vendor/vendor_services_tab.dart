import 'package:flutter/material.dart';

import '../core/constants.dart';
import '../core/data.dart';
import '../core/theme.dart';
import '../core/utils.dart';
import '../core/widgets.dart';
import '../customer/service_detail_screen.dart';
import 'service_editor_screen.dart';

class VendorServicesTab extends StatelessWidget {
  const VendorServicesTab({super.key});

  Future<List<Map<String, dynamic>>> _load() async {
    return await supa
        .from('services')
        .select('*, service_images(url, sort), service_packages(id), venue_details(service_id)')
        .eq('vendor_id', myId)
        .order('created_at', ascending: false);
  }

  Future<void> _toggle(BuildContext context, Map<String, dynamic> s, bool active) async {
    final ok = await runAction(context, () async {
      await supa.from('services').update({'is_active': active}).eq('id', s['id'] as String);
    }, success: active ? 'Listing activated' : 'Listing hidden from customers');
    if (ok) bumpData();
  }

  Future<void> _delete(BuildContext context, Map<String, dynamic> s) async {
    final yes = await confirmDialog(context, 'Delete "${str(s['title'])}"?',
        'Its packages and photos will be removed. Existing bookings keep their history.',
        confirm: 'Delete', destructive: true);
    if (!yes || !context.mounted) return;
    final ok = await runAction(context, () async {
      final imgs = await supa.from('service_images').select('storage_path').eq('service_id', s['id'] as String);
      await supa.from('services').delete().eq('id', s['id'] as String);
      await removePublicFiles(imgs.map((e) => e['storage_path'] as String?));
    }, success: 'Service deleted');
    if (ok) bumpData();
  }

  void _openEditor(BuildContext context, [String? id]) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => ServiceEditorScreen(serviceId: id)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('My services')),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: kMaroon,
        foregroundColor: Colors.white,
        onPressed: () => _openEditor(context),
        icon: const Icon(Icons.add),
        label: const Text('Add service'),
      ),
      body: Loader<List<Map<String, dynamic>>>(
        load: _load,
        builder: (context, items, reload) {
          if (items.isEmpty) {
            return RefreshIndicator(
              onRefresh: reload,
              child: ListView(children: [
                EmptyView(
                  icon: Icons.storefront_outlined,
                  title: 'No services yet',
                  subtitle: 'Add what you offer – a banquet hall, a photography package, bridal makeup – with prices and photos.',
                  action: FilledButton.icon(
                    onPressed: () => _openEditor(context),
                    icon: const Icon(Icons.add),
                    label: const Text('Add your first service'),
                  ),
                ),
              ]),
            );
          }
          return RefreshIndicator(
            onRefresh: reload,
            child: ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
              itemCount: items.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (context, i) {
                final s = items[i];
                final active = s['is_active'] == true;
                final cat = categoryById(s['category_id'] as String?);
                final packages = asList(s['service_packages']).length;
                return AppCard(
                  padding: const EdgeInsets.all(12),
                  onTap: () => _openEditor(context, s['id'] as String),
                  child: Column(children: [
                    Row(children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: NetImage(serviceCover(s), width: 72, height: 72, placeholderIcon: cat.icon),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(str(s['title']), style: const TextStyle(fontWeight: FontWeight.w600)),
                          Text('${cat.name}${str(s['subcategory']).isEmpty ? '' : ' · ${str(s['subcategory'])}'}',
                              style: const TextStyle(color: kMuted, fontSize: 12)),
                          const SizedBox(height: 4),
                          Text('From ${money(s['starting_price'])} · $packages package${packages == 1 ? '' : 's'}',
                              style: const TextStyle(color: kMaroon, fontSize: 12, fontWeight: FontWeight.w600)),
                        ]),
                      ),
                      Switch(value: active, onChanged: (v) => _toggle(context, s, v)),
                    ]),
                    const Divider(height: 16),
                    Row(children: [
                      Text(active ? 'Active' : 'Hidden', style: TextStyle(color: active ? kSuccess : kMuted, fontSize: 12)),
                      const Spacer(),
                      TextButton.icon(
                        onPressed: () => Navigator.push(context,
                            MaterialPageRoute(builder: (_) => ServiceDetailScreen(serviceId: s['id'] as String, preview: true))),
                        icon: const Icon(Icons.visibility_outlined, size: 18),
                        label: const Text('Preview'),
                      ),
                      TextButton.icon(
                        onPressed: () => _openEditor(context, s['id'] as String),
                        icon: const Icon(Icons.edit_outlined, size: 18),
                        label: const Text('Edit'),
                      ),
                      IconButton(
                        onPressed: () => _delete(context, s),
                        icon: const Icon(Icons.delete_outline, color: Color(0xFFB3261E)),
                      ),
                    ]),
                  ]),
                );
              },
            ),
          );
        },
      ),
    );
  }
}
