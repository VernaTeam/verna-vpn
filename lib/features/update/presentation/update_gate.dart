import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/l10n/app_strings.dart';
import '../../../core/theme/palette.dart';
import '../../diagnostics/data/app_log.dart';
import '../data/update_checker.dart';
import '../domain/app_release.dart';

/// Asks once, on the way in, whether there is a newer Verna.
///
/// Wrapped around the shell rather than run from `main`: the question needs a
/// screen to put the answer on, and a dialog raised before there is one has
/// nowhere to go. Renders nothing of its own.
///
/// Silent when the check fails, when the phone is offline, and when the user
/// has already said "not now" to this exact release. The manual check in
/// Settings is the one that always reports back.
class UpdateGate extends ConsumerStatefulWidget {
  const UpdateGate({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<UpdateGate> createState() => _UpdateGateState();
}

class _UpdateGateState extends ConsumerState<UpdateGate> {
  @override
  void initState() {
    super.initState();
    // After the first frame, and not in a hurry: the launch already has a
    // config fetch and possibly an auto-connect to get through, and an update
    // is not urgent enough to compete with either.
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await Future<void>.delayed(const Duration(seconds: 4));
      if (!mounted) return;
      final release = (await UpdateChecker.check()).release;
      if (release == null || !mounted) return;
      if (await UpdateChecker.wasDismissed(release.version)) return;
      if (!mounted) return;
      await showUpdateDialog(context, ref, release);
    });
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// The offer itself, shared by the launch check and the button in Settings.
///
/// Returns once the user has answered. "Not now" is remembered for that
/// version only.
Future<void> showUpdateDialog(
  BuildContext context,
  WidgetRef ref,
  AppRelease release,
) async {
  final strings = ref.read(stringsProvider);
  final c = context.verna;
  // Taken before the dialog, because the context cannot be touched after it.
  final messenger = ScaffoldMessenger.maybeOf(context);
  final take = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      backgroundColor: c.surface,
      title: Text(strings.updateAvailable(release.version),
          style: TextStyle(color: c.textPrimary, fontSize: 17)),
      content: Text(strings.updateBody(release.version),
          style: TextStyle(color: c.textSecondary, fontSize: 14, height: 1.6)),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: Text(strings.notNow,
              style: TextStyle(color: c.textMuted)),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: Text(strings.updateNow),
        ),
      ],
    ),
  );

  if (take != true) {
    await UpdateChecker.dismiss(release.version);
    return;
  }
  await openRelease(messenger, strings, release);
}

/// Hands the link to the browser. The app never downloads or installs it.
Future<void> openRelease(
  ScaffoldMessengerState? messenger,
  S strings,
  AppRelease release,
) async {
  var opened = false;
  try {
    opened = await launchUrl(
      Uri.parse(release.apkUrl),
      mode: LaunchMode.externalApplication,
    );
  } catch (_) {
    opened = false;
  }
  AppLog.instance.info('Update opened in the browser',
      detail: opened ? release.tag : 'the browser refused the link');
  messenger?.showSnackBar(SnackBar(
    content: Text(opened ? strings.openedInBrowser : strings.couldNotOpenBrowser),
  ));
}
