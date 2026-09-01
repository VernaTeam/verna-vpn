import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/l10n/app_strings.dart';
import '../../../core/theme/palette.dart';
import '../../configs/data/config_api_client.dart';
import '../../configs/presentation/providers/configs_provider.dart';
import '../data/app_log.dart';
import '../domain/log_entry.dart';

/// Everything needed to answer "why did that not work" without a USB cable.
///
/// Three things the app knew and never showed: what it is running on, what the
/// server currently has, and what the tunnel actually did on the last attempt.
/// Until now the third only existed in logcat, so every diagnosis needed the
/// phone plugged into a developer's machine.
class DiagnosticsScreen extends ConsumerStatefulWidget {
  const DiagnosticsScreen({super.key});

  @override
  ConsumerState<DiagnosticsScreen> createState() => _DiagnosticsScreenState();
}

class _DiagnosticsScreenState extends ConsumerState<DiagnosticsScreen> {
  _Snapshot? _snapshot;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    AppLog.instance.changes.listen((_) {
      if (mounted) setState(() {});
    });
    _refresh();
  }

  Future<void> _refresh() async {
    setState(() => _loading = true);
    final snapshot = await _collect(ref);
    if (!mounted) return;
    setState(() {
      _snapshot = snapshot;
      _loading = false;
    });
  }

  Future<void> _copyAll() async {
    final buffer = StringBuffer()
      ..writeln('=== Verna VPN diagnostics ===')
      ..writeln(_snapshot?.asText ?? 'not collected')
      ..writeln()
      ..writeln('=== event log ===')
      ..writeln(AppLog.instance.asText());
    await Clipboard.setData(ClipboardData(text: buffer.toString()));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(ref.read(stringsProvider).copied)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.verna;
    final strings = ref.watch(stringsProvider);
    final entries = AppLog.instance.entries.reversed.toList();
    final snapshot = _snapshot;

    return Scaffold(
      backgroundColor: c.background,
      appBar: AppBar(
        backgroundColor: c.background,
        foregroundColor: c.textPrimary,
        elevation: 0,
        title: Text(strings.diagnostics),
        actions: [
          IconButton(
            tooltip: strings.copy,
            icon: const Icon(Icons.copy_rounded),
            onPressed: _copyAll,
          ),
          IconButton(
            tooltip: strings.refresh,
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _loading ? null : _refresh,
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          if (_loading && snapshot == null)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 40),
              child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
            ),
          if (snapshot != null) ...[
            _Section(title: strings.diagApp, rows: snapshot.app),
            _Section(title: strings.diagDevice, rows: snapshot.device),
            _Section(title: strings.diagNetwork, rows: snapshot.network),
            _Section(title: strings.diagServer, rows: snapshot.server),
          ],
          const SizedBox(height: 8),
          Row(
            children: [
              Text(strings.diagEvents,
                  style: TextStyle(
                    color: c.textPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  )),
              const Spacer(),
              TextButton(
                onPressed: () {
                  AppLog.instance.clear();
                  setState(() {});
                },
                child: Text(strings.clear),
              ),
            ],
          ),
          if (entries.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Text(
                strings.diagNoEvents,
                textAlign: TextAlign.center,
                style: TextStyle(color: c.textMuted),
              ),
            ),
          ...entries.map((e) => _LogRow(entry: e)),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.rows});

  final String title;
  final List<(String, String)> rows;

  @override
  Widget build(BuildContext context) {
    final c = context.verna;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 16),
        Text(title,
            style: TextStyle(
              color: c.textPrimary,
              fontSize: 16,
              fontWeight: FontWeight.w600,
            )),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            color: c.surface,
            borderRadius: BorderRadius.circular(14),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          child: Column(
            children: [
              for (final (label, value) in rows)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: 120,
                        child: Text(label,
                            style: TextStyle(
                                color: c.textMuted, fontSize: 13)),
                      ),
                      Expanded(
                        // Values are addresses, versions and counts: LTR
                        // tokens that must not be reordered by an RTL layout.
                        child: Directionality(
                          textDirection: TextDirection.ltr,
                          child: Text(value,
                              style: TextStyle(
                                  color: c.textPrimary, fontSize: 13)),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _LogRow extends StatelessWidget {
  const _LogRow({required this.entry});

  final LogEntry entry;

  @override
  Widget build(BuildContext context) {
    final c = context.verna;
    final color = switch (entry.level) {
      LogLevel.good => c.accent,
      LogLevel.warn => Colors.orange,
      LogLevel.error => c.danger,
      LogLevel.info => c.textSecondary,
    };
    return Directionality(
      textDirection: TextDirection.ltr,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(entry.timestamp,
                style: TextStyle(
                    color: c.textMuted, fontSize: 12, height: 1.4)),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(entry.message,
                      style: TextStyle(color: color, fontSize: 13)),
                  if (entry.detail != null)
                    Text(entry.detail!,
                        style: TextStyle(color: c.textMuted, fontSize: 12)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A point-in-time reading of app, device, network and server.
class _Snapshot {
  const _Snapshot({
    required this.app,
    required this.device,
    required this.network,
    required this.server,
  });

  final List<(String, String)> app;
  final List<(String, String)> device;
  final List<(String, String)> network;
  final List<(String, String)> server;

  String get asText {
    final buffer = StringBuffer();
    void section(String name, List<(String, String)> rows) {
      buffer.writeln('[$name]');
      for (final (label, value) in rows) {
        buffer.writeln('  $label: $value');
      }
    }

    section('app', app);
    section('device', device);
    section('network', network);
    section('server', server);
    return buffer.toString();
  }
}

Future<_Snapshot> _collect(WidgetRef ref) async {
  final strings = ref.read(stringsProvider);

  // --- network: what this phone looks like from outside, right now ---------
  String egress = strings.unknownCountry;
  String egressCountry = '—';
  final dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 8),
    receiveTimeout: const Duration(seconds: 8),
    responseType: ResponseType.plain,
  ));
  // Several endpoints, because any single one can be blocked from here --
  // ip-api.com is, which is why this panel first reported "unreachable" on a
  // perfectly working connection. ipify answers over HTTPS from Iran and goes
  // first for that reason.
  const probes = [
    'https://api.ipify.org?format=json',
    'http://ip-api.com/json',
    'https://ipinfo.io/json',
  ];
  try {
    for (final url in probes) {
      try {
        final res = await dio.get<String>(url);
        final body = res.data ?? '';
        final ip = RegExp(r'"(?:query|ip)"\s*:\s*"([^"]+)"')
            .firstMatch(body)
            ?.group(1);
        if (ip == null) continue;
        egress = ip;
        egressCountry = RegExp(r'"(?:countryCode|country)"\s*:\s*"([^"]+)"')
                .firstMatch(body)
                ?.group(1) ??
            '—';
        break;
      } catch (_) {
        egress = strings.unreachable;
      }
    }
  } finally {
    dio.close(force: true);
  }

  // --- server: is the API up, and how fresh is its inventory ---------------
  final repository = ref.read(repositoryProvider);
  final serverRows = <(String, String)>[('URL', apiBaseUrl)];
  final stopwatch = Stopwatch()..start();
  try {
    final stats = await repository.getStats();
    stopwatch.stop();
    serverRows
      ..add(('Status', 'OK (${stopwatch.elapsedMilliseconds}ms)'))
      ..add(('Inventory', '${stats.total} configs'))
      ..add(('Text / file', '${stats.totalText} / ${stats.totalFile}'))
      ..add((
        'Last updated',
        stats.lastUpdated == null
            ? '—'
            : '${DateTime.now().difference(stats.lastUpdated!).inMinutes} min ago'
      ));
  } catch (e) {
    stopwatch.stop();
    serverRows.add(('Status', 'unreachable: $e'));
  }

  try {
    // How much the server has actually proven alive lately -- the number the
    // tunnel's chances really depend on.
    final verified = await repository.getVerifiedConfigs(maxAgeHours: 6, limit: 1);
    serverRows.add(('Verified 6h', '${verified.total} configs'));
    final day = await repository.getVerifiedConfigs(maxAgeHours: 24, limit: 1);
    serverRows.add(('Verified 24h', '${day.total} configs'));
  } catch (_) {
    serverRows.add(('Verified', 'unavailable'));
  }

  return _Snapshot(
    app: [
      ('Package', 'ir.vernaservice.vpn'),
      ('Language', strings.isFa ? 'fa' : 'en'),
      ('Build', kReleaseModeLabel),
    ],
    device: [
      ('OS', '${Platform.operatingSystem} ${Platform.operatingSystemVersion}'),
      ('Locale', Platform.localeName),
      ('Cores', '${Platform.numberOfProcessors}'),
    ],
    network: [
      ('Egress IP', egress),
      ('Egress country', egressCountry),
    ],
    server: serverRows,
  );
}

/// Debug builds assert; release builds do not. Cheaper than a plugin for the
/// one thing this screen needs to know about the build.
final String kReleaseModeLabel = () {
  var isDebug = false;
  assert(() {
    isDebug = true;
    return true;
  }());
  return isDebug ? 'debug' : 'release';
}();
