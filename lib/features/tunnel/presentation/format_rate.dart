/// A transfer rate in the largest unit that still leaves a short number.
///
/// Three steps: bytes under a kilobyte, kilobytes under a megabyte, then
/// megabytes. "1200 KB/s" is four digits a reader has to parse; "1.2 MB/s" is
/// read at a glance, which is the whole job of a number on a card nobody is
/// studying. Asked for by Meysam on 2026-10-07.
///
/// It was fixed at KB/s for a week, because a unit that changed under a number
/// animating sixty times a second was unreadable. The animation was the fault
/// and it is gone; one reading a second, held still, can change its unit
/// without becoming noise.
///
/// Out here rather than inside the widget so the boundaries can be tested --
/// 1023 bytes, exactly 1024, and the step to megabytes are precisely where a
/// later edit goes wrong without anyone noticing.
({String value, String unit}) formatRate(int bytesPerSecond) {
  if (bytesPerSecond <= 0) return (value: '0', unit: 'B/s');
  if (bytesPerSecond < 1024) return (value: '$bytesPerSecond', unit: 'B/s');

  final kb = bytesPerSecond / 1024;
  if (kb < 1024) {
    // One decimal while the decimal still means something, whole numbers once
    // it does not: 1.4 KB/s is a fact, 847.3 KB/s is three digits of noise.
    return (
      value: kb < 10 ? kb.toStringAsFixed(1) : kb.round().toString(),
      unit: 'KB/s',
    );
  }

  final mb = kb / 1024;
  return (
    value: mb < 10 ? mb.toStringAsFixed(1) : mb.round().toString(),
    unit: 'MB/s',
  );
}
