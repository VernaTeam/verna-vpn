import 'dart:convert';
import 'dart:ffi' show Abi;

import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/app_version.dart';
import '../../diagnostics/data/app_log.dart';
import '../domain/app_release.dart';

/// Asks GitHub whether there is a newer Verna than this one.
///
/// The app is not on any store, so nothing tells a user that the version on
/// their phone is six weeks behind. This does -- and it stops there: it finds
/// the release, picks the file that matches the phone, and hands the link to
/// the browser. Nothing is downloaded inside the app and nothing is installed
/// by it. An app that fetches and opens an APK by itself is asking to be
/// trusted with exactly the mechanism malware wants, and Meysam asked for the
/// browser on 2026-09-30.
class UpdateChecker {
  const UpdateChecker._();

  static const String _repo = 'VernaTeam/verna-vpn';
  static const String _latest =
      'https://api.github.com/repos/$_repo/releases/latest';

  /// Where the browser goes when there is no file for this phone's processor.
  static const String _releasesPage = 'https://github.com/$_repo/releases';

  /// The release the user said "not now" to, so the prompt does not return on
  /// every launch. A newer one than this still asks.
  static const String _kDismissed = 'update_dismissed_version_v1';

  /// Reads the newest release.
  ///
  /// `release` is null when this build is already the newest one *and* when
  /// the question could not be asked; `reachable` is what tells those apart.
  /// The launch check ignores the difference and stays quiet either way; the
  /// button in Settings has to say which happened, because a person who just
  /// pressed it is owed an answer.
  ///
  /// Never throws: a failed check is not an error the user did anything about.
  static Future<({AppRelease? release, bool reachable})> check({
    bool persian = false,
  }) async {
    final dio = Dio(BaseOptions(
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 10),
      // Without this GitHub may answer with its HTML page instead of JSON.
      headers: const {'Accept': 'application/vnd.github+json'},
    ));
    try {
      final res = await dio.get<Map<String, dynamic>>(_latest);
      final body = res.data;
      if (body == null) return (release: null, reachable: false);

      final tag = (body['tag_name'] as String?) ?? '';
      final version = normalise(tag);
      if (version.isEmpty) return (release: null, reachable: false);
      if (!isNewer(version, kAppVersion)) {
        AppLog.instance.info('Update check', detail: 'up to date ($tag)');
        return (release: null, reachable: true);
      }

      final assets = (body['assets'] as List?) ?? const [];
      final names = <String, String>{
        for (final asset in assets)
          if (asset is Map &&
              asset['name'] is String &&
              asset['browser_download_url'] is String)
            asset['name'] as String: asset['browser_download_url'] as String,
      };

      final notes = (body['body'] as String?)?.trim();
      final release = AppRelease(
        version: version,
        tag: tag,
        apkUrl: _apkFor(names) ?? (body['html_url'] as String?) ?? _releasesPage,
        pageUrl: (body['html_url'] as String?) ?? _releasesPage,
        notes: notes,
        whatsNew: whatsNew(notes, persian: persian),
      );
      AppLog.instance.info('Update available',
          detail: '$tag (this build is $kAppVersion)');
      return (release: release, reachable: true);
    } catch (e) {
      AppLog.instance.info('Update check failed', detail: _short(e));
      return (release: null, reachable: false);
    } finally {
      dio.close(force: true);
    }
  }


  /// The short "what's new" for the update dialog, pulled out of the release
  /// notes.
  ///
  /// The notes themselves are a page: tables, download links, headings. None
  /// of that belongs in a dialog, and parsing prose for the interesting parts
  /// would guess wrong the first time someone rewrites a heading. So the
  /// release carries the dialog's copy explicitly, inside an HTML comment:
  ///
  ///     <!-- whatsnew
  ///     Faster connecting.
  ///     Bug fixes and performance improvements.
  ///     -->
  ///     <!-- whatsnew-fa
  ///     اتصال سریع‌تر.
  ///     رفع اشکال و بهبود عملکرد.
  ///     -->
  ///
  /// GitHub renders comments as nothing, so the release page stays clean and
  /// the app still gets a written-for-humans summary. A release that forgets
  /// the block gets the generic line instead, which is what it would have
  /// deserved anyway.
  ///
  /// **What goes in the block** (Meysam, 2026-10-07, after 1.0.4 shipped three
  /// lines explaining itself): only a change the user would notice and care
  /// about -- a new feature, something that now works where it did not, a
  /// different way of using the app. Bug fixes and cosmetic work are not
  /// listed one by one; they are the single generic line, exactly as Play
  /// Store releases write it. The honest default for a release that only
  /// fixes things is to write nothing here at all and let [whatsNew] fall
  /// through to the generic line. This is an editorial rule, not a technical
  /// one -- the parser will happily print four lines of changelog nobody
  /// asked for.
  static List<String> whatsNew(String? notes, {bool persian = false}) {
    if (notes == null || notes.isEmpty) return const [];
    // The Persian block when the app is in Persian, falling back to the
    // English one: a line in the wrong language still says more than nothing.
    final block = _block(notes, persian ? 'whatsnew-fa' : 'whatsnew') ??
        _block(notes, persian ? 'whatsnew' : 'whatsnew-fa');
    if (block == null) return const [];
    return [
      for (final line in const LineSplitter().convert(block))
        if (_tidy(line).isNotEmpty) _tidy(line),
    ].take(_maxLines).toList();
  }

  /// At most this many lines reach the dialog. A changelog is not a dialog.
  static const int _maxLines = 4;

  static String? _block(String notes, String name) {
    final match = RegExp(
      '<!--\\s*$name\\s*(.*?)-->',
      dotAll: true,
      caseSensitive: false,
    ).firstMatch(notes);
    final body = match?.group(1)?.trim();
    return body == null || body.isEmpty ? null : body;
  }

  /// Without the bullet someone typed, and clipped: a line long enough to
  /// wrap four times is a paragraph that belongs on the release page.
  static String _tidy(String line) {
    var text = line.trim();
    text = text.replaceFirst(RegExp(r'^[-*\u2022]\s*'), '');
    if (text.length > 120) text = '${text.substring(0, 117)}...';
    return text;
  }

  /// The file built for this phone's processor.
  ///
  /// The release carries one APK per ABI plus a universal one. Handing an
  /// arm64 phone the armeabi-v7a build would work and waste half its speed;
  /// handing it the universal build works and costs 40 MB. So the exact one
  /// first, the universal as a fallback, and the release page if a future
  /// release is shaped differently.
  static String? _apkFor(Map<String, String> assets) {
    final wanted = switch (Abi.current()) {
      Abi.androidArm64 => 'arm64-v8a',
      Abi.androidArm => 'armeabi-v7a',
      Abi.androidX64 => 'x86_64',
      Abi.androidIA32 => 'x86',
      _ => null,
    };
    String? match(String needle) {
      for (final entry in assets.entries) {
        if (entry.key.toLowerCase().endsWith('.apk') &&
            entry.key.toLowerCase().contains(needle)) {
          return entry.value;
        }
      }
      return null;
    }

    if (wanted != null) {
      final exact = match(wanted);
      if (exact != null) return exact;
    }
    return match('universal');
  }

  /// "v1.0.1" and "1.0.1" are the same release.
  static String normalise(String tag) {
    var text = tag.trim();
    if (text.toLowerCase().startsWith('v')) text = text.substring(1);
    // The leading numbers only: "1.0.1-beta" is 1.0.1 for the purpose of "is
    // this newer", and a tag that does not begin with a number -- "nightly" --
    // is nothing this can compare, so it is refused rather than guessed at.
    return RegExp(r'^\d+(\.\d+)*').firstMatch(text)?.group(0) ?? '';
  }

  /// Compares dotted versions field by field, shorter padded with zeroes, so
  /// 1.2 is older than 1.2.1 and 1.10 is newer than 1.9 -- which a string
  /// comparison gets backwards.
  static bool isNewer(String candidate, String current) {
    final a = _parts(candidate);
    final b = _parts(current);
    for (var i = 0; i < (a.length > b.length ? a.length : b.length); i++) {
      final left = i < a.length ? a[i] : 0;
      final right = i < b.length ? b[i] : 0;
      if (left != right) return left > right;
    }
    return false;
  }

  static List<int> _parts(String version) => [
        for (final part in version.split('.')) int.tryParse(part.trim()) ?? 0,
      ];

  /// A release the user has already been asked about and declined.
  static Future<bool> wasDismissed(String version) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(_kDismissed) == version;
    } catch (_) {
      return false;
    }
  }

  static Future<void> dismiss(String version) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kDismissed, version);
    } catch (_) {
      // Then it asks again next time, which is the harmless direction.
    }
  }

  static String _short(Object error) {
    if (error is DioException) {
      return error.type == DioExceptionType.badResponse
          ? 'HTTP ${error.response?.statusCode ?? '?'}'
          : error.type.name;
    }
    return error.runtimeType.toString();
  }
}
