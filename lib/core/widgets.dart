import 'package:flutter/material.dart';

import 'constants.dart';
import 'data.dart';
import 'theme.dart';
import 'utils.dart';

/// Loads data, shows loading / error / content, reloads when [dataVersion] changes.
class Loader<T> extends StatefulWidget {
  final Future<T> Function() load;
  final Widget Function(BuildContext context, T data, Future<void> Function() reload) builder;
  final bool listenGlobal;
  const Loader({super.key, required this.load, required this.builder, this.listenGlobal = true});

  @override
  State<Loader<T>> createState() => _LoaderState<T>();
}

class _LoaderState<T> extends State<Loader<T>> {
  T? _data;
  bool _hasData = false;
  Object? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _run(initial: true);
    if (widget.listenGlobal) dataVersion.addListener(_onGlobal);
  }

  @override
  void dispose() {
    dataVersion.removeListener(_onGlobal);
    super.dispose();
  }

  void _onGlobal() => _run();

  Future<void> _run({bool initial = false}) async {
    if (!initial && mounted) setState(() => _loading = true);
    try {
      final d = await widget.load();
      if (!mounted) return;
      setState(() {
        _data = d;
        _hasData = true;
        _error = null;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _loading = false;
      });
      if (_hasData) showSnack(context, friendlyError(e), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_hasData) {
      if (_loading) return const LoadingView();
      return ErrorView(message: friendlyError(_error), onRetry: () => _run());
    }
    return widget.builder(context, _data as T, () => _run());
  }
}

class LoadingView extends StatelessWidget {
  const LoadingView({super.key});
  @override
  Widget build(BuildContext context) =>
      const Center(child: Padding(padding: EdgeInsets.all(32), child: CircularProgressIndicator(color: kMaroon)));
}

class ErrorView extends StatelessWidget {
  final String message;
  final VoidCallback? onRetry;
  const ErrorView({super.key, required this.message, this.onRetry});
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.cloud_off, size: 48, color: kMuted),
          const SizedBox(height: 12),
          Text(message, textAlign: TextAlign.center, style: const TextStyle(color: kMuted)),
          if (onRetry != null) ...[
            const SizedBox(height: 16),
            OutlinedButton.icon(onPressed: onRetry, icon: const Icon(Icons.refresh), label: const Text('Try again')),
          ],
        ]),
      ),
    );
  }
}

class EmptyView extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? action;
  const EmptyView({super.key, required this.icon, required this.title, this.subtitle, this.action});
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 40),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(
          padding: const EdgeInsets.all(18),
          decoration: const BoxDecoration(color: kCream, shape: BoxShape.circle),
          child: Icon(icon, size: 36, color: kMaroon),
        ),
        const SizedBox(height: 16),
        Text(title, textAlign: TextAlign.center, style: Theme.of(context).textTheme.titleMedium),
        if (subtitle != null) ...[
          const SizedBox(height: 6),
          Text(subtitle!, textAlign: TextAlign.center, style: const TextStyle(color: kMuted)),
        ],
        if (action != null) ...[const SizedBox(height: 16), action!],
      ]),
    );
  }
}

class AppCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final Color color;
  final EdgeInsetsGeometry margin;
  const AppCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.onTap,
    this.color = Colors.white,
    this.margin = EdgeInsets.zero,
  });
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: margin,
      child: Material(
        color: color,
        borderRadius: BorderRadius.circular(kRadius),
        clipBehavior: Clip.antiAlias,
        elevation: 0,
        child: InkWell(
          onTap: onTap,
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(kRadius),
              border: Border.all(color: const Color(0xFFF0E4DC)),
            ),
            padding: padding,
            child: child,
          ),
        ),
      ),
    );
  }
}

class SectionHeader extends StatelessWidget {
  final String title;
  final String? actionLabel;
  final VoidCallback? onAction;
  const SectionHeader(this.title, {super.key, this.actionLabel, this.onAction});
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 8, 8),
      child: Row(children: [
        Expanded(child: Text(title, style: Theme.of(context).textTheme.titleMedium)),
        if (actionLabel != null) TextButton(onPressed: onAction, child: Text(actionLabel!)),
      ]),
    );
  }
}

class BodianaLogo extends StatelessWidget {
  final double size;
  final bool light;
  const BodianaLogo({super.key, this.size = 72, this.light = false});
  @override
  Widget build(BuildContext context) {
    return Column(mainAxisSize: MainAxisSize.min, children: [
      ClipRRect(
        borderRadius: BorderRadius.circular(size * 0.28),
        child: Image.asset('assets/logo.png', width: size, height: size, fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => Container(
                  width: size,
                  height: size,
                  color: kMaroon,
                  alignment: Alignment.center,
                  child: Text('B', style: TextStyle(color: kGold, fontSize: size * 0.5, fontWeight: FontWeight.bold)),
                )),
      ),
      const SizedBox(height: 12),
      Text('Bodiana',
          style: Theme.of(context).textTheme.headlineMedium?.copyWith(color: light ? Colors.white : kMaroon)),
    ]);
  }
}

class NetImage extends StatelessWidget {
  final String? url;
  final double? width;
  final double? height;
  final BoxFit fit;
  final IconData placeholderIcon;
  const NetImage(this.url, {super.key, this.width, this.height, this.fit = BoxFit.cover, this.placeholderIcon = Icons.image});
  @override
  Widget build(BuildContext context) {
    final placeholder = Container(
      width: width,
      height: height,
      color: kCream,
      alignment: Alignment.center,
      child: Icon(placeholderIcon, color: kMaroon.withAlpha(110), size: 32),
    );
    final u = nullIfEmpty(url);
    if (u == null) return placeholder;
    return Image.network(
      u,
      width: width,
      height: height,
      fit: fit,
      errorBuilder: (_, __, ___) => placeholder,
      loadingBuilder: (ctx, child, progress) => progress == null ? child : placeholder,
    );
  }
}

class StatusChip extends StatelessWidget {
  final String status;
  const StatusChip(this.status, {super.key});

  static Color colorFor(String s) => switch (s) {
        'accepted' || 'verified' || 'done' => kSuccess,
        'pending' || 'held' => kWarning,
        'rejected' || 'cancelled' || 'not_done' || 'unavailable' => const Color(0xFFB3261E),
        'completed' => kMaroon,
        _ => kMuted,
      };

  @override
  Widget build(BuildContext context) {
    final label = bookingStatusLabels[status] ??
        switch (status) {
          'verified' => 'Verified',
          'done' => 'Done',
          'not_done' => 'Not done',
          'skipped' => 'Skipped',
          _ => status.isEmpty ? '' : status[0].toUpperCase() + status.substring(1),
        };
    final c = colorFor(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: c.withAlpha(28), borderRadius: BorderRadius.circular(20)),
      child: Text(label, style: TextStyle(color: c, fontWeight: FontWeight.w600, fontSize: 12)),
    );
  }
}

/// Only "verified" vendors get the verified badge.
class VerifiedBadge extends StatelessWidget {
  final String? status;
  final bool compact;
  const VerifiedBadge(this.status, {super.key, this.compact = false});
  @override
  Widget build(BuildContext context) {
    if (status == 'verified') {
      return Row(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.verified, size: 16, color: kGold),
        if (!compact) ...[
          const SizedBox(width: 4),
          const Text('Verified', style: TextStyle(color: Color(0xFF9A7B14), fontWeight: FontWeight.w600, fontSize: 12)),
        ],
      ]);
    }
    if (compact) return const SizedBox.shrink();
    final label = status == 'rejected' ? 'Verification rejected' : 'Verification pending';
    return Row(mainAxisSize: MainAxisSize.min, children: [
      const Icon(Icons.hourglass_top, size: 14, color: kMuted),
      const SizedBox(width: 4),
      Text(label, style: const TextStyle(color: kMuted, fontSize: 12)),
    ]);
  }
}

class RatingRow extends StatelessWidget {
  final double rating;
  final int count;
  const RatingRow(this.rating, this.count, {super.key});
  @override
  Widget build(BuildContext context) {
    if (count == 0) return const Text('New', style: TextStyle(color: kMuted, fontSize: 12));
    return Row(mainAxisSize: MainAxisSize.min, children: [
      const Icon(Icons.star_rounded, size: 16, color: kGold),
      const SizedBox(width: 2),
      Text(rating.toStringAsFixed(1), style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12)),
      Text(' ($count)', style: const TextStyle(color: kMuted, fontSize: 12)),
    ]);
  }
}

class ProgressBar extends StatelessWidget {
  final double value;
  final Color color;
  const ProgressBar(this.value, {super.key, this.color = kMaroon});
  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: LinearProgressIndicator(
        value: value.clamp(0.0, 1.0),
        minHeight: 8,
        backgroundColor: kCream,
        color: color,
      ),
    );
  }
}

class StatTile extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;
  const StatTile({super.key, required this.label, required this.value, required this.icon, this.color = kMaroon});
  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.all(14),
      child: Row(children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(color: color.withAlpha(25), borderRadius: BorderRadius.circular(12)),
          child: Icon(icon, color: color, size: 20),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(value, style: Theme.of(context).textTheme.titleLarge),
            Text(label, style: const TextStyle(color: kMuted, fontSize: 12), maxLines: 1, overflow: TextOverflow.ellipsis),
          ]),
        ),
      ]),
    );
  }
}

/// Marketplace listing card.
class ServiceCard extends StatelessWidget {
  final Map<String, dynamic> service;
  final VoidCallback onTap;
  final double? width;
  final Widget? trailing;
  const ServiceCard({super.key, required this.service, required this.onTap, this.width, this.trailing});

  @override
  Widget build(BuildContext context) {
    final vendor = asMap(service['vendor_profiles']);
    final cat = categoryById(service['category_id'] as String?);
    return SizedBox(
      width: width,
      child: AppCard(
        padding: EdgeInsets.zero,
        onTap: onTap,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          Stack(children: [
            NetImage(serviceCover(service), height: 140, width: double.infinity, placeholderIcon: cat.icon),
            Positioned(
              left: 10,
              top: 10,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(color: Colors.white.withAlpha(235), borderRadius: BorderRadius.circular(12)),
                child: Text(str(service['subcategory'], cat.name),
                    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: kMaroon)),
              ),
            ),
            if (trailing != null) Positioned(right: 4, top: 4, child: trailing!),
          ]),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(str(service['title']),
                  maxLines: 1, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
              const SizedBox(height: 2),
              Row(children: [
                Flexible(
                  child: Text(str(vendor['business_name']),
                      maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: kMuted, fontSize: 12)),
                ),
                const SizedBox(width: 4),
                VerifiedBadge(vendor['verification_status'] as String?, compact: true),
              ]),
              const SizedBox(height: 6),
              Row(children: [
                RatingRow(toD(vendor['rating_avg']), toI(vendor['rating_count'])),
                const SizedBox(width: 8),
                const Icon(Icons.place_outlined, size: 14, color: kMuted),
                Flexible(
                  child: Text(str(service['city'], str(vendor['city'])),
                      maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: kMuted, fontSize: 12)),
                ),
              ]),
              const SizedBox(height: 6),
              Text('From ${money(service['starting_price'])}',
                  style: const TextStyle(color: kMaroon, fontWeight: FontWeight.w700)),
            ]),
          ),
        ]),
      ),
    );
  }
}

class InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  const InfoRow(this.icon, this.label, this.value, {super.key});
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, size: 18, color: kMaroon),
        const SizedBox(width: 10),
        SizedBox(width: 110, child: Text(label, style: const TextStyle(color: kMuted))),
        Expanded(child: Text(value, style: const TextStyle(fontWeight: FontWeight.w500))),
      ]),
    );
  }
}

class GoldDivider extends StatelessWidget {
  const GoldDivider({super.key});
  @override
  Widget build(BuildContext context) => Container(
        height: 2,
        width: 48,
        margin: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(color: kGold, borderRadius: BorderRadius.circular(2)),
      );
}

/// Bottom-sheet header used in several sheets.
Widget sheetHandle() => Center(
      child: Container(
        width: 40,
        height: 4,
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(color: Colors.black12, borderRadius: BorderRadius.circular(4)),
      ),
    );

/// A dropdown-style field that opens a bottom sheet. Avoids DropdownButtonFormField
/// API differences between Flutter versions.
class SelectField<T> extends StatelessWidget {
  final String label;
  final IconData? icon;
  final T? value;
  final List<(T, String)> options;
  final ValueChanged<T?> onChanged;
  final String? errorText;
  final String placeholder;
  const SelectField({
    super.key,
    required this.label,
    required this.value,
    required this.options,
    required this.onChanged,
    this.icon,
    this.errorText,
    this.placeholder = 'Select',
  });

  @override
  Widget build(BuildContext context) {
    String? current;
    for (final o in options) {
      if (o.$1 == value) current = o.$2;
    }
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () async {
        final picked = await showModalBottomSheet<(T,)>(
          context: context,
          showDragHandle: true,
          isScrollControlled: true,
          builder: (ctx) => SafeArea(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.7),
              child: ListView(shrinkWrap: true, children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                  child: Text(label, style: Theme.of(ctx).textTheme.titleMedium),
                ),
                for (final o in options)
                  ListTile(
                    title: Text(o.$2),
                    trailing: o.$1 == value ? const Icon(Icons.check, color: kMaroon) : null,
                    onTap: () => Navigator.pop(ctx, (o.$1,)),
                  ),
              ]),
            ),
          ),
        );
        if (picked != null) onChanged(picked.$1);
      },
      child: InputDecorator(
        decoration: inputDeco(label, icon: icon, suffix: const Icon(Icons.arrow_drop_down)).copyWith(errorText: errorText),
        isEmpty: current == null,
        child: Text(current ?? placeholder,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: current == null ? kMuted : kInk)),
      ),
    );
  }
}
