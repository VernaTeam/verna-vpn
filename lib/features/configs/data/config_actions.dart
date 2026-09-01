import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/services.dart' show PlatformException;
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../domain/vpn_config.dart';

/// Result of an action, so the UI can show the right message.
enum ActionStatus { ok, noApp, failed }

class ActionResult {
  final ActionStatus status;
  final String? detail;
  const ActionResult(this.status, [this.detail]);
}

/// Handles "open in VPN app" (deep link) and "download file".
class ConfigActions {
  ConfigActions._();

  /// Launch a text config (URI) directly into its VPN app via its URI scheme.
  static Future<ActionResult> openInApp(VpnConfig config) async {
    final content = config.content;
    if (content == null || content.isEmpty) {
      return const ActionResult(ActionStatus.failed, 'empty content');
    }
    final uri = Uri.tryParse(content.trim());
    if (uri == null) {
      return const ActionResult(ActionStatus.failed, 'invalid URI');
    }
    try {
      final launched =
          await launchUrl(uri, mode: LaunchMode.externalApplication);
      return launched
          ? const ActionResult(ActionStatus.ok)
          : const ActionResult(ActionStatus.noApp);
    } on PlatformException {
      return const ActionResult(ActionStatus.noApp);
    } catch (e) {
      return ActionResult(ActionStatus.failed, e.toString());
    }
  }

  /// Open the Telegram channel.
  static Future<bool> openTelegram(String channel) async {
    final uri = Uri.parse('https://t.me/$channel');
    try {
      return await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      return false;
    }
  }

  /// Download a file config to the app's external files dir. Returns the saved
  /// path in `detail` so the UI can tell the user where it landed.
  ///
  /// We intentionally do NOT auto-open the file (that required a problematic
  /// native plugin). The user opens it from their file manager / the relevant
  /// VPN app, which is the normal flow for .ovpn/.conf imports anyway.
  static Future<ActionResult> downloadAndOpen(
    VpnConfig config, {
    void Function(double progress)? onProgress,
  }) async {
    final url = config.downloadUrl;
    if (url == null || url.isEmpty) {
      return const ActionResult(ActionStatus.failed, 'no download url');
    }

    // Build absolute URL if the API returned a relative path.
    final fullUrl = url.startsWith('http')
        ? url
        : 'https://vernaservice.ir$url';

    try {
      // Prefer a user-visible external dir; fall back to app documents.
      Directory dir;
      final ext = await getExternalStorageDirectory();
      if (ext != null) {
        dir = Directory('${ext.path}/configs');
      } else {
        dir = await getApplicationDocumentsDirectory();
      }
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }

      final fileExt = config.fileExtension ?? '.dat';
      final savePath = '${dir.path}/verna_${config.id}$fileExt';

      final dio = Dio();
      await dio.download(
        fullUrl,
        savePath,
        onReceiveProgress: (received, total) {
          if (total > 0 && onProgress != null) onProgress(received / total);
        },
        options: Options(receiveTimeout: const Duration(seconds: 30)),
      );

      final file = File(savePath);
      if (!await file.exists()) {
        return const ActionResult(ActionStatus.failed, 'file not saved');
      }
      return ActionResult(ActionStatus.ok, savePath);
    } on DioException catch (e) {
      return ActionResult(ActionStatus.failed, e.message);
    } catch (e) {
      return ActionResult(ActionStatus.failed, e.toString());
    }
  }
}
