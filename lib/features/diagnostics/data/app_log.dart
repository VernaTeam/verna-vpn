import 'dart:async';
import 'dart:collection';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../domain/log_entry.dart';
import 'log_store.dart';

/// The app's event log.
///
/// A global rather than something passed around: the tunnel service, the API
/// layer and the UI all write to it, and threading one instance through every
/// constructor would add plumbing to code that has nothing else to do with
/// logging.
///
/// The recent part is kept in memory for the diagnostics screen; every line
/// also goes to a file in the app's private storage, so the record survives
/// the app being closed, crashing, or killed by Android -- which is precisely
/// when it is wanted. See [LogStore] for what that file is allowed to hold.
class AppLog {
  AppLog._();

  static final AppLog instance = AppLog._();

  /// How much is kept for the on-screen list. The file keeps far more.
  static const int _maxEntries = 500;

  final Queue<LogEntry> _entries = Queue<LogEntry>();
  final StreamController<void> _changes = StreamController<void>.broadcast();

  String _earlier = '';

  /// Newest last, so a list view reads top to bottom in time order.
  List<LogEntry> get entries => List.unmodifiable(_entries);

  /// What earlier runs of the app left in the file, oldest first.
  ///
  /// Empty when the log was cleared or this is a first run. Kept as plain text
  /// rather than parsed back into entries: it is read, copied and sent, never
  /// filtered or styled.
  String get earlier => _earlier;

  bool get hasEarlier => _earlier.trim().isNotEmpty;

  String? get filePath => LogStore.instance.path;

  Stream<void> get changes => _changes.stream;

  /// Opens the log file, keeps what is already in it, and starts a session.
  ///
  /// Called once from `main` before the app runs, so the first lines the
  /// tunnel writes are already going to disk.
  Future<void> attach({required String version}) async {
    _earlier = await LogStore.instance.open();
    final now = DateTime.now();
    String two(int n) => n.toString().padLeft(2, '0');
    final stamp = '${now.year}-${two(now.month)}-${two(now.day)} '
        '${two(now.hour)}:${two(now.minute)}:${two(now.second)}';
    // A header per run, because most questions start with "which time did it
    // do that" -- and because the build and the OS version are the first two
    // things worth knowing about a report that arrives without them.
    LogStore.instance.append(
      '\n===== session $stamp  ·  Verna $version  ·  '
      '${Platform.operatingSystem} ${Platform.operatingSystemVersion}  ·  '
      '${PlatformDispatcher.instance.locale.toLanguageTag()} =====',
    );
    info('App started', detail: 'Verna $version');
  }

  void add(LogLevel level, String message, {String? detail}) {
    // Mirrored to the console in debug builds so a failure can be read from
    // logcat while the phone is on a cable, without navigating the app to the
    // diagnostics screen first -- which is exactly the moment the UI is least
    // likely to be cooperating. Stripped from release builds: these lines name
    // the servers the user connected to.
    assert(() {
      debugPrint('[verna] ${level.name}: $message${detail == null ? '' : ' -- $detail'}');
      return true;
    }());
    final entry = LogEntry(level, message, detail: detail);
    _entries.add(entry);
    while (_entries.length > _maxEntries) {
      _entries.removeFirst();
    }
    LogStore.instance.append(entry.fileText);
    if (!_changes.isClosed) _changes.add(null);
  }

  void info(String message, {String? detail}) =>
      add(LogLevel.info, message, detail: detail);
  void good(String message, {String? detail}) =>
      add(LogLevel.good, message, detail: detail);
  void warn(String message, {String? detail}) =>
      add(LogLevel.warn, message, detail: detail);
  void error(String message, {String? detail}) =>
      add(LogLevel.error, message, detail: detail);

  /// Writes anything still buffered. Called when the app goes to the
  /// background, which on Android may be the last moment it runs at all.
  Future<void> flush() => LogStore.instance.flush();

  /// Clears both the screen and the file.
  Future<void> clear() async {
    _entries.clear();
    _earlier = '';
    await LogStore.instance.clear();
    if (!_changes.isClosed) _changes.add(null);
  }

  /// Everything there is, for the copy button: the file first, then this run.
  String asText() {
    final current = _entries.map((e) => e.fileText).join('\n');
    if (!hasEarlier) return current;
    return '${_earlier.trimRight()}\n$current';
  }

  /// Just this run, for the on-screen list's own copy.
  String asSessionText() => _entries.map((e) => e.asText).join('\n');
}
