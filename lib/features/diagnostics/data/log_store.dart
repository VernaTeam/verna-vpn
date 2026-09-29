import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// The event log's file on disk.
///
/// The log used to live only in memory, deliberately: it names the servers the
/// user connected to, and that is not something to leave lying around. But
/// memory-only meant it was gone at exactly the moment it was needed -- after
/// a crash, after Android killed the process, after "I closed it and reopened
/// it and now it says disconnected". Every real investigation in this project
/// has started from a log that had already been erased by the thing being
/// investigated.
///
/// So it is written, with the two protections that matter kept: it lives in
/// the app's private storage, which no other app can read without root, and
/// Settings can wipe it. It holds exit addresses and server ids, never
/// credentials, never the contents of a user's own subscription links.
class LogStore {
  LogStore._();

  static final LogStore instance = LogStore._();

  static const String _fileName = 'verna-events.log';

  /// Trimmed when it passes this, down to [_keepBytes]. Roughly four thousand
  /// lines, which is a few days of ordinary use and several full connect
  /// searches -- enough to cover "it broke last night".
  static const int _maxBytes = 512 * 1024;
  static const int _keepBytes = 256 * 1024;

  /// Written in batches. One write per line would put a file operation in the
  /// middle of every probe result.
  static const Duration _flushAfter = Duration(seconds: 2);
  static const int _flushAtBytes = 8 * 1024;

  File? _file;
  final StringBuffer _pending = StringBuffer();
  Timer? _timer;
  Future<void> _writing = Future<void>.value();

  String? get path => _file?.path;

  /// Opens the file and returns what earlier sessions left in it.
  ///
  /// Returns an empty string on any failure: a diagnostic aid must never be
  /// the reason the app does not start.
  Future<String> open() async {
    try {
      final dir = await getApplicationSupportDirectory();
      final file = File('${dir.path}${Platform.pathSeparator}$_fileName');
      if (!file.existsSync()) {
        file.createSync(recursive: true);
      }
      _file = file;
      await _trim(file);
      return file.readAsStringSync();
    } catch (_) {
      _file = null;
      return '';
    }
  }

  void append(String text) {
    if (_file == null) return;
    _pending.writeln(text);
    if (_pending.length >= _flushAtBytes) {
      unawaited(flush());
      return;
    }
    _timer ??= Timer(_flushAfter, () => unawaited(flush()));
  }

  /// Writes whatever is buffered. Safe to call at any time; serialised so two
  /// flushes cannot interleave inside the file.
  Future<void> flush() async {
    _timer?.cancel();
    _timer = null;
    final file = _file;
    if (file == null || _pending.isEmpty) return;
    final text = _pending.toString();
    _pending.clear();
    _writing = _writing.then((_) async {
      try {
        file.writeAsStringSync(text, mode: FileMode.append, flush: true);
        if (file.lengthSync() > _maxBytes) await _trim(file);
      } catch (_) {
        // A log that cannot be written is not worth an error dialog.
      }
    });
    return _writing;
  }

  Future<void> clear() async {
    _timer?.cancel();
    _timer = null;
    _pending.clear();
    try {
      _file?.writeAsStringSync('', flush: true);
    } catch (_) {
      // Same.
    }
  }

  /// Keeps the newest [_keepBytes] and drops the rest, cutting on a line
  /// boundary so the first surviving entry is a whole one.
  Future<void> _trim(File file) async {
    try {
      if (file.lengthSync() <= _maxBytes) return;
      final raw = file.readAsBytesSync();
      final tail = raw.sublist(raw.length - _keepBytes);
      final text = utf8.decode(tail, allowMalformed: true);
      final cut = text.indexOf('\n');
      file.writeAsStringSync(
        cut < 0 ? text : text.substring(cut + 1),
        flush: true,
      );
    } catch (_) {
      // Leave the file as it is rather than risk losing it entirely.
    }
  }
}
