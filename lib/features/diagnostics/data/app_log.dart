import 'dart:async';
import 'dart:collection';

import 'package:flutter/foundation.dart';

import '../domain/log_entry.dart';

/// The app's in-memory event log.
///
/// A global rather than something passed around: the tunnel service, the API
/// layer and the UI all write to it, and threading one instance through every
/// constructor would add plumbing to code that has nothing else to do with
/// logging.
///
/// Memory only, and capped. This is a diagnostic aid for "why did that not
/// connect", not an audit trail -- and it holds the addresses of servers the
/// user connected to, which is not something to leave on disk by default.
class AppLog {
  AppLog._();

  static final AppLog instance = AppLog._();

  static const int _maxEntries = 500;

  final Queue<LogEntry> _entries = Queue<LogEntry>();
  final StreamController<void> _changes = StreamController<void>.broadcast();

  /// Newest last, so a list view reads top to bottom in time order.
  List<LogEntry> get entries => List.unmodifiable(_entries);

  Stream<void> get changes => _changes.stream;

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
    _entries.add(LogEntry(level, message, detail: detail));
    while (_entries.length > _maxEntries) {
      _entries.removeFirst();
    }
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

  void clear() {
    _entries.clear();
    if (!_changes.isClosed) _changes.add(null);
  }

  String asText() => _entries.map((e) => e.asText).join('\n');
}
