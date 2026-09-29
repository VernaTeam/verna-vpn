/// One line in the app's own event log.
///
/// The tunnel makes a lot of decisions the user never sees: which servers were
/// unreachable, which answered the proxy probe and how fast, why a candidate
/// was discarded. When something does not work, those reasons are the whole
/// story, and until now they existed only in adb logcat -- which means only on
/// a developer's machine, with a cable attached.
class LogEntry {
  LogEntry(this.level, this.message, {this.detail})
      : at = DateTime.now();

  final DateTime at;
  final LogLevel level;
  final String message;

  /// Optional second line: an address, an error, a measurement.
  final String? detail;

  String get timestamp {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(at.hour)}:${two(at.minute)}:${two(at.second)}';
  }

  /// Plain text, for the copy-everything button.
  String get asText {
    final tag = level.name.toUpperCase().padRight(5);
    return detail == null
        ? '$timestamp  $tag  $message'
        : '$timestamp  $tag  $message\n                  $detail';
  }

  /// Plain text for the file, which outlives the day it was written in.
  ///
  /// The on-screen list can afford a bare clock -- it is obviously today. A
  /// file that keeps several days of history cannot: "03:14 connect failed" is
  /// useless when the question is whether it happened last night or last week.
  String get fileText {
    String two(int n) => n.toString().padLeft(2, '0');
    final day = '${at.year}-${two(at.month)}-${two(at.day)}';
    final tag = level.name.toUpperCase().padRight(5);
    return detail == null
        ? '$day $timestamp  $tag  $message'
        : '$day $timestamp  $tag  $message\n                             $detail';
  }
}

enum LogLevel {
  /// Ordinary progress.
  info,

  /// Something worked and is worth noticing.
  good,

  /// Something failed, but the app carried on.
  warn,

  /// Something failed and stopped the operation.
  error,
}
