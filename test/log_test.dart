import 'package:flutter_test/flutter_test.dart';
import 'package:verna_vpn/features/diagnostics/domain/log_entry.dart';

void main() {
  group('LogEntry', () {
    test('the screen line is a clock, the file line is a date', () {
      final entry = LogEntry(LogLevel.info, 'Connect requested');
      expect(entry.asText, startsWith(entry.timestamp));
      // The file outlives the day it was written in, so its line has to say
      // which day that was.
      final day = '${entry.at.year}-'
          '${entry.at.month.toString().padLeft(2, '0')}-'
          '${entry.at.day.toString().padLeft(2, '0')}';
      expect(entry.fileText, startsWith('$day ${entry.timestamp}'));
      expect(entry.fileText, contains('INFO'));
      expect(entry.fileText, contains('Connect requested'));
    });

    test('a detail becomes a second line, not a longer first one', () {
      final entry = LogEntry(LogLevel.error, 'Tunnel start failed',
          detail: 'core never reached started');
      final lines = entry.fileText.split('\n');
      expect(lines, hasLength(2));
      expect(lines.first, contains('Tunnel start failed'));
      expect(lines.last.trim(), 'core never reached started');
      // Indented past the timestamp column so a wall of entries still reads
      // as one event per block.
      expect(lines.last, startsWith('    '));
    });

    test('levels are padded to one width so the messages line up', () {
      final short = LogEntry(LogLevel.good, 'x').fileText;
      final long = LogEntry(LogLevel.error, 'x').fileText;
      expect(short.indexOf('x'), long.indexOf('x'));
    });
  });
}
