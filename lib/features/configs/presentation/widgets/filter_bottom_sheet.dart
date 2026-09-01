import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../domain/vpn_config.dart';
import '../providers/configs_provider.dart';
import '../../../../core/l10n/app_strings.dart';
import '../../../../core/theme/palette.dart';

/// Protocol and country filters for the config list.
///
/// Both are multi-select: "vless and vmess" is a normal thing to want, and the
/// old single-choice version could not say it. "All" is not a separate option
/// competing with the others -- it is the empty selection, so the two can never
/// contradict each other. Tapping it clears; tapping any specific chip while
/// "All" is active simply starts a selection.
class FilterBottomSheet extends ConsumerWidget {
  const FilterBottomSheet({super.key});

  static Future<void> show(BuildContext context) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: context.verna.background,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => const FilterBottomSheet(),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filter = ref.watch(filterProvider);
    final countries = ref.watch(availableCountriesProvider);
    final s = ref.watch(stringsProvider);
    final c = context.verna;

    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      minChildSize: 0.4,
      maxChildSize: 0.9,
      expand: false,
      builder: (_, scrollController) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: ListView(
          controller: scrollController,
          children: [
            Center(
              child: Container(
                margin: const EdgeInsets.symmetric(vertical: 10),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: c.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Row(
              children: [
                Text(
                  s.filter,
                  style: TextStyle(
                    color: c.textPrimary,
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const Spacer(),
                TextButton(
                  onPressed: () {
                    ref.read(filterProvider.notifier).reset();
                    Navigator.pop(context);
                  },
                  child: Text(s.clearFilter),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _SectionLabel(
              text: s.filterByType,
              count: filter.typeFilter.length,
              s: s,
            ),
            const SizedBox(height: 10),
            _ProtocolChips(selected: filter.typeFilter, s: s),
            const SizedBox(height: 20),
            _SectionLabel(
              text: s.filterByCountry,
              count: filter.countryFilter.length,
              s: s,
            ),
            const SizedBox(height: 10),
            _CountryChips(
              countries: countries,
              selected: filter.countryFilter,
              s: s,
            ),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.text, required this.count, required this.s});

  final String text;
  final int count;
  final S s;

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(
      color: context.verna.textSecondary,
      fontSize: 13,
      fontWeight: FontWeight.w600,
    );
    return Row(
      children: [
        Text(text, style: style),
        if (count > 0) ...[
          const SizedBox(width: 8),
          // How many are picked, so a selection scrolled out of view is still
          // visible from the heading.
          Text(s.selectedCount(count),
              style: style.copyWith(color: context.verna.accent)),
        ],
      ],
    );
  }
}

class _ProtocolChips extends ConsumerWidget {
  const _ProtocolChips({required this.selected, required this.s});

  final Set<VpnConfigType> selected;
  final S s;

  /// Taken from `usableTypes` rather than written out here, so a chip can
  /// never offer a protocol the list refuses to show. The hand-kept list this
  /// replaces still advertised OpenVPN and WireGuard long after the app
  /// stopped displaying them.
  static final List<VpnConfigType> _protocols = [
    ...tunnelableTypes,
    ...handoffTypes,
  ];


  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(filterProvider.notifier);
    final c = context.verna;
    final allSelected = selected.isEmpty;
    final allStyle = _chipColors(c, allSelected);

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        FilterChip(
          label: Text(s.allTypes),
          selected: allSelected,
          backgroundColor: allStyle.background,
          selectedColor: allStyle.selected,
          checkmarkColor: c.accent,
          side: allStyle.side,
          labelStyle: allStyle.label,
          // Already-all is not a no-op worth re-firing; tapping it again does
          // nothing rather than rebuilding the list for no change.
          onSelected: allSelected ? null : (_) => notifier.clearTypes(),
        ),
        ..._protocols.map((p) {
          final isOn = selected.contains(p);
          final style = _chipColors(c, isOn);
          return FilterChip(
            label: Text(p.label),
            selected: isOn,
            backgroundColor: style.background,
            selectedColor: style.selected,
            checkmarkColor: c.accent,
            side: style.side,
            labelStyle: style.label,
            // Greyed out while "All" is active, so it reads as "all of these
            // are included" rather than "none of these are".
            showCheckmark: true,
            onSelected: (_) => notifier.toggleType(p),
          );
        }),
      ],
    );
  }
}

/// The one place a filter chip's colours are decided.
///
/// Written out per chip at first, which is how the country row ended up on
/// Material's defaults while the protocol row was already in the app's green.
ChipThemeBits _chipColors(VernaColors c, bool on) => (
      background: c.surface,
      selected: c.accent.withValues(alpha: 0.18),
      side: BorderSide(color: on ? c.accent : c.border),
      label: TextStyle(
        color: on ? c.accent : c.textSecondary,
        fontWeight: FontWeight.w600,
      ),
    );

typedef ChipThemeBits = ({
  Color background,
  Color selected,
  BorderSide side,
  TextStyle label,
});

class _CountryChips extends ConsumerWidget {
  const _CountryChips({
    required this.countries,
    required this.selected,
    required this.s,
  });

  final List<({String code, String name, String flag})> countries;
  final Set<String> selected;
  final S s;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(filterProvider.notifier);
    final c = context.verna;
    final allSelected = selected.isEmpty;

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        () {
          final style = _chipColors(c, allSelected);
          return FilterChip(
            label: Text(s.allCountries),
            selected: allSelected,
            backgroundColor: style.background,
            selectedColor: style.selected,
            checkmarkColor: c.accent,
            side: style.side,
            labelStyle: style.label,
            onSelected: allSelected ? null : (_) => notifier.clearCountries(),
          );
        }(),
        ...countries.map((country) {
          final on = selected.contains(country.code);
          final style = _chipColors(c, on);
          return FilterChip(
            label: Text('${country.flag} ${country.name}'),
            selected: on,
            backgroundColor: style.background,
            selectedColor: style.selected,
            checkmarkColor: c.accent,
            side: style.side,
            labelStyle: style.label,
            showCheckmark: true,
            onSelected: (_) => notifier.toggleCountry(country.code),
          );
        }),
      ],
    );
  }
}
