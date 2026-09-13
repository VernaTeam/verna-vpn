import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app_shell.dart';
import 'features/tunnel/presentation/providers/tunnel_provider.dart';
import 'features/settings/data/app_preferences.dart';
import 'core/theme/app_theme.dart';
import 'core/l10n/app_strings.dart';
import 'features/configs/presentation/screens/splash_screen.dart';
import 'features/configs/presentation/screens/home_screen.dart';
import 'features/configs/presentation/screens/settings_screen.dart';
import 'features/about/presentation/screens/about_screen.dart';
import 'features/diagnostics/presentation/diagnostics_screen.dart';
import 'features/settings/presentation/screens/plan_screen.dart';
import 'features/subscriptions/presentation/subscriptions_screen.dart';
import 'features/tunnel/presentation/screens/country_picker_screen.dart';
import 'features/tunnel/presentation/screens/vpn_home_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);
  runApp(const ProviderScope(child: VernaApp()));
}

class VernaApp extends ConsumerWidget {
  const VernaApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode =
        ref.watch(themeModeProvider).valueOrNull ?? ThemeMode.system;
    final lang = ref.watch(langProvider).valueOrNull ?? AppLang.en;

    final locale =
        lang == AppLang.en ? const Locale('en', 'US') : const Locale('fa', 'IR');

    return MaterialApp(
      title: 'Verna VPN',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: themeMode,
      locale: locale,
      supportedLocales: const [
        Locale('fa', 'IR'),
        Locale('en', 'US'),
      ],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      // Force text direction to match language
      builder: (context, child) {
        return Directionality(
          textDirection:
              lang == AppLang.en ? TextDirection.ltr : TextDirection.rtl,
          child: child!,
        );
      },
      initialRoute: '/',
      routes: {
        // Note: do not try to move this by setting `initialRoute` to a named
        // route instead. Flutter splits that path and builds the stack
        // ['/', '/whatever'], so SplashScreen gets created underneath, its
        // timer fires, and its pushReplacementNamed('/home') lands HomeScreen
        // on top of whatever was supposed to be showing.
        // The shell, not the connect screen: connect, servers, usage, plan
        // and settings are five places of their own rather than icons hidden
        // in one screen's app bar. Wrapped so the boot screen shows first --
        // as a swap inside one route rather than a push, which is what the
        // note above is warning about.
        '/': (_) => const _Boot(),
        '/vpn': (_) => const VpnHomeScreen(),
        '/splash': (_) => const SplashScreen(),
        // The original config browser, kept for people who want to copy a
        // config into another app.
        '/configs': (_) => const HomeScreen(),
        '/home': (_) => const HomeScreen(),
        '/countries': (_) => const CountryPickerScreen(),
        '/diagnostics': (_) => const DiagnosticsScreen(),
        '/plan': (_) => const PlanScreen(),
        '/subscriptions': (_) => const SubscriptionsScreen(),
        '/settings': (_) => const SettingsScreen(),
        '/about': (_) => const AboutScreen(),
      },
    );
  }
}

/// The boot screen, then the app.
///
/// A swap inside a single route rather than a `pushReplacementNamed`: the
/// splash used to navigate, and navigating from underneath a stack Flutter had
/// already built was how it once landed the wrong screen on top. Nothing here
/// touches the navigator, so there is no stack to get wrong.
class _Boot extends ConsumerStatefulWidget {
  const _Boot();

  @override
  ConsumerState<_Boot> createState() => _BootState();
}

class _BootState extends ConsumerState<_Boot> {
  bool _ready = false;

  @override
  Widget build(BuildContext context) {
    if (_ready) return const AppShell();
    return SplashScreen(
      onDone: () {
        if (!mounted) return;
        setState(() => _ready = true);
        _autoConnect();
      },
    );
  }

  /// Starts the tunnel on launch, if the user asked for that.
  ///
  /// After the boot screen rather than during it: connecting picks a server by
  /// testing candidates, and doing that while the splash is still up would show
  /// a finished progress bar over an app that is still working.
  Future<void> _autoConnect() async {
    final prefs = await ref.read(appPreferencesProvider.future);
    if (!prefs.autoConnect || !mounted) return;
    final tunnel = ref.read(tunnelSnapshotProvider);
    // Not if something is already happening: the shell may have restored a
    // live session, and a second connect would tear down the first.
    if (tunnel.isConnected || tunnel.isBusy) return;
    await ref.read(tunnelSnapshotProvider.notifier).connect();
  }
}
