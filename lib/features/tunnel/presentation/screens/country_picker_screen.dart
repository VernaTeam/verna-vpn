import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/l10n/app_strings.dart';
import '../../../../core/theme/palette.dart';
import '../../../configs/domain/vpn_config.dart';
import '../providers/tunnel_provider.dart';

/// Where the user picks an exit country.
///
/// Not a server list, which is what a commercial VPN would show here. The
/// inventory is thousands of disposable free configs, most of them dead at any
/// moment, so a list of individual servers would mostly be a list of things
/// that will not work. What the app can honestly offer is a country: the server
/// verifies configs through real tunnels and reports how many currently answer
/// from each exit, and the app picks one of those when connecting.
///
/// The counts come from the same verification that decides what the tunnel is
/// allowed to try, so a country shown with 40 servers really has 40 that
/// answered recently -- not 40 that were scraped at some point.
class CountryPickerScreen extends ConsumerStatefulWidget {
  const CountryPickerScreen({super.key});

  @override
  ConsumerState<CountryPickerScreen> createState() =>
      _CountryPickerScreenState();
}

class _CountryPickerScreenState extends ConsumerState<CountryPickerScreen> {
  final TextEditingController _search = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _choose(String? code) {
    ref.read(preferredCountryProvider.notifier).state = code;
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.verna;
    final strings = ref.watch(stringsProvider);
    final selected = ref.watch(preferredCountryProvider);
    final countries = ref.watch(verifiedCountriesProvider);

    return Scaffold(
      backgroundColor: c.background,
      appBar: AppBar(
        backgroundColor: c.background,
        foregroundColor: c.textPrimary,
        elevation: 0,
        title: Text(strings.chooseLocation),
        actions: [
          IconButton(
            tooltip: strings.refresh,
            icon: const Icon(Icons.refresh_rounded),
            onPressed: () => ref.invalidate(verifiedCountriesProvider),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
            child: TextField(
              controller: _search,
              onChanged: (value) => setState(() => _query = value.trim()),
              style: TextStyle(color: c.textPrimary),
              decoration: InputDecoration(
                hintText: strings.searchCountry,
                hintStyle: TextStyle(color: c.textMuted),
                prefixIcon: Icon(Icons.search, color: c.textMuted),
                filled: true,
                fillColor: c.textPrimary.withValues(alpha: 0.06),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(vertical: 4),
              ),
            ),
          ),
          _AutomaticTile(
            strings: strings,
            selected: selected == null,
            onTap: () => _choose(null),
          ),
          Divider(height: 24, color: c.border),
          Expanded(
            child: countries.when(
              loading: () => const Center(
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              error: (_, __) => _Message(
                icon: Icons.cloud_off_rounded,
                text: strings.msgFetchFailed,
                action: strings.retry,
                onAction: () => ref.invalidate(verifiedCountriesProvider),
              ),
              data: (all) {
                final list = _filter(all, _query);
                if (list.isEmpty) {
                  return _Message(
                    icon: Icons.public_off_rounded,
                    text: all.isEmpty
                        ? strings.noVerifiedCountries
                        : strings.noSearchResults,
                  );
                }
                return RefreshIndicator(
                  onRefresh: () async =>
                      ref.invalidate(verifiedCountriesProvider),
                  child: ListView.builder(
                    padding: const EdgeInsets.only(bottom: 24),
                    itemCount: list.length,
                    itemBuilder: (_, i) => _CountryTile(
                      country: list[i],
                      strings: strings,
                      selected: list[i].code == selected,
                      onTap: () => _choose(list[i].code),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  /// Matches on both the name and the code, so "NL" and "Netherlands" both
  /// find the same row.
  List<VerifiedCountry> _filter(List<VerifiedCountry> all, String query) {
    if (query.isEmpty) return all;
    final needle = query.toLowerCase();
    return all
        .where((c) =>
            c.name.toLowerCase().contains(needle) ||
            c.code.toLowerCase().contains(needle))
        .toList();
  }
}

class _AutomaticTile extends StatelessWidget {
  const _AutomaticTile({
    required this.strings,
    required this.selected,
    required this.onTap,
  });

  final S strings;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.verna;
    return ListTile(
      onTap: onTap,
      leading: const Text('🌐', style: TextStyle(fontSize: 26)),
      title: Text(
        strings.autoSelect,
        style: TextStyle(color: c.textPrimary, fontWeight: FontWeight.w600),
      ),
      subtitle: Text(
        strings.bestAvailable,
        style: TextStyle(color: c.textMuted, fontSize: 12),
      ),
      trailing: selected
          ? const Icon(Icons.check_circle, color: Color(0xFF2EE6A8))
          : null,
    );
  }
}

class _CountryTile extends StatelessWidget {
  const _CountryTile({
    required this.country,
    required this.strings,
    required this.selected,
    required this.onTap,
  });

  final VerifiedCountry country;
  final S strings;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.verna;
    return ListTile(
      onTap: onTap,
      leading: Text(
        country.flag.isEmpty ? '🏳️' : country.flag,
        style: const TextStyle(fontSize: 26),
      ),
      title: Text(
        country.name.isEmpty ? country.code : country.name,
        style: TextStyle(color: c.textPrimary),
      ),
      subtitle: Text(
        strings.serversAvailable(country.count),
        style: TextStyle(color: c.textMuted, fontSize: 12),
      ),
      trailing: selected
          ? const Icon(Icons.check_circle, color: Color(0xFF2EE6A8))
          : null,
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({
    required this.icon,
    required this.text,
    this.action,
    this.onAction,
  });

  final IconData icon;
  final String text;
  final String? action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final c = context.verna;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 48, color: c.border),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 40),
            child: Text(
              text,
              textAlign: TextAlign.center,
              style: TextStyle(color: c.textMuted),
            ),
          ),
          if (action != null) ...[
            const SizedBox(height: 12),
            TextButton(onPressed: onAction, child: Text(action!)),
          ],
        ],
      ),
    );
  }
}
