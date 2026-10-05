import 'dart:async';

import 'package:dio/dio.dart';

import '../../configs/data/config_api_client.dart';
import '../../diagnostics/data/app_log.dart';

/// How fast the tunnel actually is, measured once per session.
///
/// The traffic counters say what the user did, not what the line could do:
/// someone who connects and reads a page moves 30 KB and is indistinguishable
/// in the data from someone on a server that can barely pass a byte. So the
/// app downloads a fixed block through the tunnel and times it.
///
/// From verna-api rather than a public CDN, for two reasons: the far end is
/// identical for every user, which is what makes the numbers comparable
/// between servers and between phones; and this host has to be reachable for
/// the app to work at all, so it is not a new thing that could be blocked.
class SpeedProbe {
  const SpeedProbe._();

  /// 256 KB. Enough to get past TCP's slow start and see a real rate, small
  /// enough that a user on mobile data does not pay for the measurement --
  /// once per session, a quarter of a megabyte.
  static const int _bytes = 262144;

  /// Below this the sample says more about the timing than the tunnel.
  static const Duration _minDuration = Duration(milliseconds: 150);

  /// Kilobytes per second, or null if the sample could not be taken or is not
  /// worth trusting.
  ///
  /// The budget is generous on purpose. Ten seconds to connect was not enough
  /// on an Iranian mobile tunnel -- measured on an A54 on Irancell,
  /// 2026-10-05, where the attempt died with "connection timeout after
  /// 0:00:10" and the session row carried no speed at all. A measurement that
  /// gives up before the slow networks answer reports only on the fast ones,
  /// which is the opposite of what it is for.
  static Future<int?> measure({
    Duration timeout = const Duration(seconds: 40),
  }) async {
    final dio = Dio(BaseOptions(
      connectTimeout: const Duration(seconds: 25),
      receiveTimeout: timeout,
      responseType: ResponseType.bytes,
    ));
    final watch = Stopwatch()..start();
    try {
      final res = await dio.get<List<int>>(
        '$apiBaseUrl/api/v1/speedtest?size=$_bytes',
        options: Options(headers: const {'Cache-Control': 'no-store'}),
      );
      watch.stop();
      final got = res.data?.length ?? 0;
      // A short read is a truncated download, not a fast one.
      if (got < _bytes) return null;
      if (watch.elapsed < _minDuration) {
        // Faster than the clock can describe. Report the floor rather than a
        // number that would look like a record.
        return (got / 1024 / _minDuration.inMilliseconds * 1000).round();
      }
      final kbps = got / 1024 / (watch.elapsedMilliseconds / 1000);
      return kbps.round();
    } catch (e) {
      AppLog.instance.info('Speed sample skipped', detail: '$e');
      return null;
    } finally {
      dio.close(force: true);
    }
  }
}
