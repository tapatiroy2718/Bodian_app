import 'dart:async';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import 'theme.dart';

SupabaseClient get supa => Supabase.instance.client;
String get myId => supa.auth.currentUser!.id;

final rootNavigatorKey = GlobalKey<NavigatorState>();

/// Bumped after any change so open screens reload their data.
final dataVersion = ValueNotifier<int>(0);
void bumpData() => dataVersion.value++;

// ---------------------------------------------------------------- parsing

Map<String, dynamic> asMap(dynamic v) {
  if (v is Map) return Map<String, dynamic>.from(v);
  if (v is List && v.isNotEmpty && v.first is Map) return Map<String, dynamic>.from(v.first as Map);
  return <String, dynamic>{};
}

Map<String, dynamic>? asMapOrNull(dynamic v) {
  final m = asMap(v);
  return m.isEmpty ? null : m;
}

List<Map<String, dynamic>> asList(dynamic v) {
  if (v is List) {
    return v.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
  }
  if (v is Map) return [Map<String, dynamic>.from(v)];
  return <Map<String, dynamic>>[];
}

List<String> asStrings(dynamic v) {
  if (v is List) return v.where((e) => e != null).map((e) => e.toString()).toList();
  return <String>[];
}

double toD(dynamic v) {
  if (v is num) return v.toDouble();
  if (v is String) return double.tryParse(v) ?? 0;
  return 0;
}

int toI(dynamic v) {
  if (v is int) return v;
  if (v is num) return v.toInt();
  if (v is String) return int.tryParse(v) ?? 0;
  return 0;
}

String str(dynamic v, [String fallback = '']) {
  if (v == null) return fallback;
  final s = v.toString().trim();
  return s.isEmpty ? fallback : s;
}

DateTime? parseDate(dynamic v) {
  if (v == null) return null;
  return DateTime.tryParse(v.toString())?.toLocal();
}

String ymd(DateTime d) => DateFormat('yyyy-MM-dd').format(d);
String fmtDate(dynamic v, [String fallback = 'Not set']) {
  final d = v is DateTime ? v : parseDate(v);
  return d == null ? fallback : DateFormat('d MMM yyyy').format(d);
}

String fmtDateTime(dynamic v) {
  final d = parseDate(v);
  return d == null ? '' : DateFormat('d MMM yyyy, h:mm a').format(d);
}

String timeAgo(dynamic v) {
  final d = parseDate(v);
  if (d == null) return '';
  final diff = DateTime.now().difference(d);
  if (diff.inMinutes < 1) return 'just now';
  if (diff.inHours < 1) return '${diff.inMinutes} min ago';
  if (diff.inDays < 1) return '${diff.inHours} h ago';
  if (diff.inDays < 7) return '${diff.inDays} d ago';
  return fmtDate(d);
}

final _money = NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0);
String money(dynamic v) => _money.format(toD(v));

DateTime today() {
  final n = DateTime.now();
  return DateTime(n.year, n.month, n.day);
}

String? nullIfEmpty(String? s) {
  final t = s?.trim();
  return (t == null || t.isEmpty) ? null : t;
}

// ---------------------------------------------------------------- errors

String friendlyError(Object? e) {
  if (e == null) return 'Something went wrong.';
  if (e is AuthException) return e.message;
  if (e is PostgrestException) {
    if (e.code == '42501' || e.message.contains('row-level security')) {
      return 'You do not have permission to do that.';
    }
    if (e.code == 'PGRST202' || e.code == '42883') {
      return 'The server is missing a database function. Run the Bodiana SQL setup file in Supabase.';
    }
    if (e.code == '42P01' || e.code == 'PGRST205') {
      return 'The database tables are missing. Run the Bodiana SQL setup file in Supabase.';
    }
    return e.message;
  }
  if (e is StorageException) return 'Upload failed: ${e.message}';
  if (e is TimeoutException) return 'The request timed out. Please try again.';
  final s = e.toString();
  if (s.contains('SocketException') || s.contains('Failed host lookup') || s.contains('ClientException')) {
    return 'No internet connection. Check your network and try again.';
  }
  return s.replaceFirst('Exception: ', '');
}

void showSnack(BuildContext context, String message, {bool error = false}) {
  final m = ScaffoldMessenger.maybeOf(context);
  if (m == null) return;
  m.hideCurrentSnackBar();
  m.showSnackBar(SnackBar(
    content: Text(message),
    backgroundColor: error ? const Color(0xFFB3261E) : kInk,
    behavior: SnackBarBehavior.floating,
  ));
}

/// Runs [action], shows success/error snackbars, returns true on success.
Future<bool> runAction(BuildContext context, Future<void> Function() action, {String? success}) async {
  try {
    await action();
    if (success != null && context.mounted) showSnack(context, success);
    return true;
  } catch (e) {
    if (context.mounted) showSnack(context, friendlyError(e), error: true);
    return false;
  }
}

// ---------------------------------------------------------------- dialogs

Future<bool> confirmDialog(BuildContext context, String title, String message,
    {String confirm = 'Yes', bool destructive = false}) async {
  final r = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
        FilledButton(
          style: destructive ? FilledButton.styleFrom(backgroundColor: const Color(0xFFB3261E)) : null,
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(confirm),
        ),
      ],
    ),
  );
  return r ?? false;
}

/// Asks for a line of text. Returns null when cancelled.
Future<String?> promptText(BuildContext context, String title,
    {String label = 'Reason', bool required = true, String initial = '', int maxLines = 3}) async {
  final ctrl = TextEditingController(text: initial);
  final r = await showDialog<String>(
    context: context,
    builder: (ctx) {
      String? error;
      return StatefulBuilder(builder: (ctx, setLocal) {
        return AlertDialog(
          title: Text(title),
          content: TextField(
            controller: ctrl,
            autofocus: true,
            maxLines: maxLines,
            minLines: 1,
            decoration: inputDeco(label).copyWith(errorText: error),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            FilledButton(
              onPressed: () {
                if (required && ctrl.text.trim().isEmpty) {
                  setLocal(() => error = 'Required');
                  return;
                }
                Navigator.pop(ctx, ctrl.text.trim());
              },
              child: const Text('OK'),
            ),
          ],
        );
      });
    },
  );
  return r;
}

Future<DateTime?> pickDate(BuildContext context,
    {DateTime? initial, DateTime? first, DateTime? last, bool Function(DateTime)? selectable}) async {
  final firstDate = first ?? today();
  final lastDate = last ?? today().add(const Duration(days: 365 * 3));
  var init = initial ?? firstDate;
  if (init.isBefore(firstDate)) init = firstDate;
  if (init.isAfter(lastDate)) init = lastDate;
  if (selectable != null && !selectable(init)) {
    var d = firstDate;
    DateTime? found;
    while (!d.isAfter(lastDate)) {
      if (selectable(d)) {
        found = d;
        break;
      }
      d = d.add(const Duration(days: 1));
    }
    if (found == null) {
      if (context.mounted) showSnack(context, 'No dates are available.', error: true);
      return null;
    }
    init = found;
  }
  return showDatePicker(
    context: context,
    initialDate: init,
    firstDate: firstDate,
    lastDate: lastDate,
    selectableDayPredicate: selectable,
  );
}

// ---------------------------------------------------------------- contact

String _digits(String phone) => phone.replaceAll(RegExp(r'[^0-9]'), '');

Future<void> callPhone(BuildContext context, String? phone) async {
  final p = nullIfEmpty(phone);
  if (p == null) {
    showSnack(context, 'No phone number available.', error: true);
    return;
  }
  await _open(context, Uri(scheme: 'tel', path: p));
}

Future<void> openWhatsApp(BuildContext context, String? phone, {String text = ''}) async {
  final p = nullIfEmpty(phone);
  if (p == null) {
    showSnack(context, 'No WhatsApp number available.', error: true);
    return;
  }
  var d = _digits(p);
  if (d.length == 10) d = '91$d';
  final uri = Uri.parse('https://wa.me/$d${text.isEmpty ? '' : '?text=${Uri.encodeComponent(text)}'}');
  await _open(context, uri);
}

Future<void> openMap(BuildContext context, {double? lat, double? lng, String? query}) async {
  final Uri uri;
  if (lat != null && lng != null) {
    uri = Uri.parse('https://www.google.com/maps/search/?api=1&query=$lat,$lng');
  } else if (nullIfEmpty(query) != null) {
    uri = Uri.parse('https://www.google.com/maps/search/?api=1&query=${Uri.encodeComponent(query!)}');
  } else {
    showSnack(context, 'No location available.', error: true);
    return;
  }
  await _open(context, uri);
}

Future<void> openUrl(BuildContext context, String url) => _open(context, Uri.parse(url));

Future<void> _open(BuildContext context, Uri uri) async {
  try {
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && context.mounted) showSnack(context, 'Could not open ${uri.scheme} link.', error: true);
  } catch (e) {
    if (context.mounted) showSnack(context, 'Could not open link.', error: true);
  }
}

// ---------------------------------------------------------------- uploads

final _picker = ImagePicker();

Future<XFile?> pickImage({ImageSource source = ImageSource.gallery}) =>
    _picker.pickImage(source: source, maxWidth: 1800, maxHeight: 1800, imageQuality: 82);

Future<List<XFile>> pickImages() => _picker.pickMultiImage(maxWidth: 1800, maxHeight: 1800, imageQuality: 82);

String _ext(String name) {
  final i = name.lastIndexOf('.');
  final e = i < 0 ? 'jpg' : name.substring(i + 1).toLowerCase();
  if (e == 'jpeg' || e == 'jpg') return 'jpg';
  if (e == 'png' || e == 'webp') return e;
  return 'jpg';
}

String _mime(String ext) => switch (ext) { 'png' => 'image/png', 'webp' => 'image/webp', _ => 'image/jpeg' };

class UploadedFile {
  final String path;
  final String url;
  final int size;
  final String mime;
  const UploadedFile(this.path, this.url, this.size, this.mime);
}

/// Uploads an image into `<bucket>/<userId>/<folder>/...`.
/// For the public bucket [UploadedFile.url] is the public URL.
Future<UploadedFile> uploadImage(XFile file, {required String folder, String bucket = 'public-media', int maxMb = 5}) async {
  final bytes = await file.readAsBytes();
  if (bytes.length > maxMb * 1024 * 1024) {
    throw Exception('The image is larger than $maxMb MB. Please choose a smaller photo.');
  }
  final ext = _ext(file.name);
  final mime = _mime(ext);
  final path = '$myId/$folder/${DateTime.now().millisecondsSinceEpoch}.$ext';
  await supa.storage.from(bucket).uploadBinary(path, bytes, fileOptions: FileOptions(contentType: mime, upsert: false));
  final url = bucket == 'public-media' ? supa.storage.from(bucket).getPublicUrl(path) : '';
  return UploadedFile(path, url, bytes.length, mime);
}

/// Converts a public-media URL back to its storage path (for deletion).
String? publicPathFromUrl(String? url) {
  if (url == null) return null;
  const marker = '/public-media/';
  final i = url.indexOf(marker);
  if (i < 0) return null;
  return Uri.decodeComponent(url.substring(i + marker.length).split('?').first);
}

Future<void> removePublicFiles(Iterable<String?> paths) async {
  final list = paths.whereType<String>().where((p) => p.isNotEmpty).toList();
  if (list.isEmpty) return;
  try {
    await supa.storage.from('public-media').remove(list);
  } catch (_) {
    // Best effort; leftover files are harmless.
  }
}
