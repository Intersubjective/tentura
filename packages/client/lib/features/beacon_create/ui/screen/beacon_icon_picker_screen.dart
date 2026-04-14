import 'package:flutter/material.dart';

import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/beacon_identity_catalog.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/utils/ui_utils.dart';
import 'package:tentura/ui/widget/beacon_identity_tile.dart';
import 'package:tentura/ui/widgets/app_choice_chip_style.dart';

import '../widget/beacon_color_selector.dart';

/// Result of [BeaconIconPickerScreen.show]; `iconCode == null` means cleared identity.
typedef BeaconIconPickerResult = ({
  String? iconCode,
  int? iconBackground,
});

typedef _BeaconIconPickerSelection = ({
  String? iconCode,
  int? iconBackground,
});

/// Background + foreground for a grid cell; matches [BeaconIdentityTile] rules.
({Color bg, Color fg}) _pickerTileColors({
  required bool selected,
  required int? selectionBackgroundArgb,
  required ColorScheme scheme,
}) {
  if (!selected) {
    return (
      bg: scheme.surfaceContainerHighest,
      fg: scheme.onSurfaceVariant,
    );
  }
  var swatch = paletteSwatchForArgb(selectionBackgroundArgb);
  if (swatch == null && selectionBackgroundArgb == null) {
    swatch = defaultBeaconPaletteSwatch;
  }
  if (swatch != null) {
    return (bg: swatch.background, fg: swatch.foreground);
  }
  final argb = selectionBackgroundArgb!;
  final bg = Color(argb);
  final fg = bg.computeLuminance() > 0.5
      ? Colors.black.withValues(alpha: 0.87)
      : Colors.white;
  return (bg: bg, fg: fg);
}

/// Full-screen dialog to pick beacon symbol icon and background color.
class BeaconIconPickerScreen extends StatefulWidget {
  const BeaconIconPickerScreen({
    super.key,
    this.initialIconCode,
    this.initialIconBackground,
  });

  final String? initialIconCode;
  final int? initialIconBackground;

  static Future<BeaconIconPickerResult?> show(
    BuildContext context, {
    String? iconCode,
    int? iconBackground,
  }) => showDialog<BeaconIconPickerResult>(
    context: context,
    barrierDismissible: false,
    useSafeArea: false,
    builder: (_) => Dialog.fullscreen(
      child: BeaconIconPickerScreen(
        initialIconCode: iconCode,
        initialIconBackground: iconBackground,
      ),
    ),
  );

  @override
  State<BeaconIconPickerScreen> createState() => _BeaconIconPickerScreenState();
}

class _GridListenable extends Listenable {
  _GridListenable(this._query, this._category, this._selection);

  final ValueNotifier<String> _query;
  final ValueNotifier<int> _category;
  final ValueNotifier<_BeaconIconPickerSelection> _selection;

  @override
  void addListener(VoidCallback listener) {
    _query.addListener(listener);
    _category.addListener(listener);
    _selection.addListener(listener);
  }

  @override
  void removeListener(VoidCallback listener) {
    _query.removeListener(listener);
    _category.removeListener(listener);
    _selection.removeListener(listener);
  }
}

class _BeaconIconPickerScreenState extends State<BeaconIconPickerScreen> {
  late final _BeaconIconPickerSelection _initialSelection = (
    iconCode: widget.initialIconCode,
    iconBackground: widget.initialIconBackground,
  );

  late final ValueNotifier<String> _queryNotifier = ValueNotifier('');
  late final ValueNotifier<int> _categoryNotifier = ValueNotifier(0);
  late final ValueNotifier<_BeaconIconPickerSelection> _selectionNotifier =
      ValueNotifier(_initialSelection);

  late final DateTime _epoch = DateTime.timestamp();

  late final _GridListenable _gridListenable = _GridListenable(
    _queryNotifier,
    _categoryNotifier,
    _selectionNotifier,
  );

  late AppChoiceChipStyle _chipStyle;

  /// Lowercase search blob per icon key: `code`, `label`, localized category.
  late Map<String, String> _searchBlobByKey;

  List<MapEntry<String, BeaconIconDefinition>> _cachedEntries = [];

  void _onFilterChanged() => _recomputeEntries();

  void _recomputeEntries() {
    final cat = _categoryNotifier.value;
    final q = _queryNotifier.value.trim().toLowerCase();
    _cachedEntries = [
      for (final e in kBeaconIdentityIcons.entries)
        if (cat == 0 ||
            e.value.category == BeaconIdentityCategory.values[cat - 1])
          if (q.isEmpty || _searchBlobByKey[e.key]!.contains(q)) e,
    ];
  }

  @override
  void initState() {
    super.initState();
    _queryNotifier.addListener(_onFilterChanged);
    _categoryNotifier.addListener(_onFilterChanged);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _chipStyle = AppChoiceChipStyle(Theme.of(context).colorScheme);
    final l10n = L10n.of(context)!;
    _searchBlobByKey = {
      for (final e in kBeaconIdentityIcons.entries)
        e.key:
            '${e.key.toLowerCase()} ${e.value.label.toLowerCase()} ${_categoryLabel(l10n, e.value.category).toLowerCase()}',
    };
    _recomputeEntries();
  }

  @override
  void dispose() {
    _queryNotifier.removeListener(_onFilterChanged);
    _categoryNotifier.removeListener(_onFilterChanged);
    _queryNotifier.dispose();
    _categoryNotifier.dispose();
    _selectionNotifier.dispose();
    super.dispose();
  }

  String _categoryLabel(L10n l10n, BeaconIdentityCategory c) => switch (c) {
    BeaconIdentityCategory.meta => l10n.beaconIdentityCategoryMeta,
    BeaconIdentityCategory.community => l10n.beaconIdentityCategoryCommunity,
    BeaconIdentityCategory.essentials => l10n.beaconIdentityCategoryEssentials,
    BeaconIdentityCategory.home => l10n.beaconIdentityCategoryHome,
    BeaconIdentityCategory.mobility => l10n.beaconIdentityCategoryMobility,
    BeaconIdentityCategory.communication =>
      l10n.beaconIdentityCategoryCommunication,
    BeaconIdentityCategory.money => l10n.beaconIdentityCategoryMoney,
    BeaconIdentityCategory.health => l10n.beaconIdentityCategoryHealth,
    BeaconIdentityCategory.safety => l10n.beaconIdentityCategorySafety,
    BeaconIdentityCategory.work => l10n.beaconIdentityCategoryWork,
    BeaconIdentityCategory.tech => l10n.beaconIdentityCategoryTech,
    BeaconIdentityCategory.nature => l10n.beaconIdentityCategoryNature,
    BeaconIdentityCategory.weather => l10n.beaconIdentityCategoryWeather,
    BeaconIdentityCategory.culture => l10n.beaconIdentityCategoryCulture,
    BeaconIdentityCategory.education => l10n.beaconIdentityCategoryEducation,
    BeaconIdentityCategory.animals => l10n.beaconIdentityCategoryAnimals,
    BeaconIdentityCategory.civic => l10n.beaconIdentityCategoryCivic,
  };

  void _onDone() {
    final s = _selectionNotifier.value;
    Navigator.of(context).pop((
      iconCode: s.iconCode,
      iconBackground: s.iconBackground,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: ValueListenableBuilder<_BeaconIconPickerSelection>(
          valueListenable: _selectionNotifier,
          builder: (context, sel, _) {
            final previewBeacon = Beacon(
              createdAt: _epoch,
              updatedAt: _epoch,
              iconCode: sel.iconCode,
              iconBackground: sel.iconBackground,
            );
            return Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                BeaconIdentityTile(beacon: previewBeacon, size: 32),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    l10n.beaconSymbolTitle,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            );
          },
        ),
        actions: [
          ValueListenableBuilder<_BeaconIconPickerSelection>(
            valueListenable: _selectionNotifier,
            builder: (context, sel, _) {
              return Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (sel.iconCode != null)
                    TextButton(
                      onPressed: () => _selectionNotifier.value = (
                        iconCode: null,
                        iconBackground: null,
                      ),
                      child: Text(l10n.beaconSymbolClear),
                    ),
                  TextButton(
                    onPressed: _onDone,
                    child: Text(l10n.beaconSymbolDone),
                  ),
                ],
              );
            },
          ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextField(
              decoration: InputDecoration(
                hintText: l10n.beaconSymbolSearchHint,
                isDense: true,
                prefixIcon: const Icon(Icons.search, size: 20),
              ),
              onChanged: (v) => _queryNotifier.value = v,
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: ValueListenableBuilder<int>(
              valueListenable: _categoryNotifier,
              builder: (context, cat, _) {
                final chipStyle = _chipStyle;
                return Wrap(
                  spacing: kSpacingSmall,
                  runSpacing: kSpacingSmall,
                  children: [
                    ChoiceChip(
                      showCheckmark: false,
                      color: chipStyle.background,
                      labelStyle: theme.textTheme.labelLarge?.copyWith(
                        fontWeight: FontWeight.w500,
                        color: chipStyle.labelForeground,
                      ),
                      checkmarkColor: chipStyle.checkmarkColor,
                      side: chipStyle.outline,
                      selected: cat == 0,
                      label: Text(l10n.beaconSymbolCategoryAll),
                      onSelected: (_) => _categoryNotifier.value = 0,
                    ),
                    for (
                      var i = 0;
                      i < BeaconIdentityCategory.values.length;
                      i++
                    )
                      ChoiceChip(
                        showCheckmark: false,
                        color: chipStyle.background,
                        labelStyle: theme.textTheme.labelLarge?.copyWith(
                          fontWeight: FontWeight.w500,
                          color: chipStyle.labelForeground,
                        ),
                        checkmarkColor: chipStyle.checkmarkColor,
                        side: chipStyle.outline,
                        selected: cat == i + 1,
                        label: Text(
                          _categoryLabel(
                            l10n,
                            BeaconIdentityCategory.values[i],
                          ),
                        ),
                        onSelected: (_) => _categoryNotifier.value = i + 1,
                      ),
                  ],
                );
              },
            ),
          ),
          Expanded(
            child: ListenableBuilder(
              listenable: _gridListenable,
              builder: (context, _) {
                final entries = _cachedEntries;
                final sel = _selectionNotifier.value;
                if (entries.isEmpty) {
                  return CustomScrollView(
                    slivers: [
                      SliverFillRemaining(
                        hasScrollBody: false,
                        child: Center(
                          child: Text(
                            l10n.beaconSymbolNoMatches,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ),
                    ],
                  );
                }
                return CustomScrollView(
                  slivers: [
                    SliverPadding(
                      padding: const EdgeInsets.all(8),
                      sliver: SliverGrid(
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 4,
                              mainAxisSpacing: 8,
                              crossAxisSpacing: 8,
                              childAspectRatio: 0.85,
                            ),
                        delegate: SliverChildBuilderDelegate(
                          (context, i) {
                            final entry = entries[i];
                            final selected = sel.iconCode == entry.key;
                            return _IconGridTile(
                              key: ValueKey(entry.key),
                              iconData: entry.value.icon,
                              label: entry.value.label,
                              selected: selected,
                              selectionBackgroundArgb: selected
                                  ? sel.iconBackground
                                  : null,
                              scheme: scheme,
                              baseLabelStyle: theme.textTheme.labelSmall,
                              onTap: () {
                                final cur = _selectionNotifier.value;
                                _selectionNotifier.value = (
                                  iconCode: entry.key,
                                  iconBackground:
                                      cur.iconBackground ??
                                      kBeaconIdentityPalette
                                          .first
                                          .backgroundArgb,
                                );
                              },
                            );
                          },
                          childCount: entries.length,
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
          Material(
            elevation: 8,
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      l10n.beaconSymbolBackground,
                      style: theme.textTheme.labelLarge,
                    ),
                    const SizedBox(height: 8),
                    ValueListenableBuilder<_BeaconIconPickerSelection>(
                      valueListenable: _selectionNotifier,
                      builder: (context, sel, _) {
                        return Opacity(
                          opacity: sel.iconCode == null ? 0.4 : 1,
                          child: IgnorePointer(
                            ignoring: sel.iconCode == null,
                            child: BeaconColorSelector(
                              selectedArgb: sel.iconBackground,
                              onSelected: (v) {
                                final cur = _selectionNotifier.value;
                                _selectionNotifier.value = (
                                  iconCode: cur.iconCode,
                                  iconBackground: v,
                                );
                              },
                            ),
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _IconGridTile extends StatelessWidget {
  const _IconGridTile({
    required this.iconData,
    required this.label,
    required this.selected,
    required this.onTap,
    required this.scheme,
    required this.baseLabelStyle,
    this.selectionBackgroundArgb,
    super.key,
  });

  final IconData iconData;
  final String label;
  final bool selected;

  /// Current selection background when [selected]; drives palette like [BeaconIdentityTile].
  final int? selectionBackgroundArgb;
  final VoidCallback onTap;
  final ColorScheme scheme;
  final TextStyle? baseLabelStyle;

  @override
  Widget build(BuildContext context) {
    final colors = _pickerTileColors(
      selected: selected,
      selectionBackgroundArgb: selectionBackgroundArgb,
      scheme: scheme,
    );
    final fg = colors.fg;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colors.bg,
          borderRadius: BorderRadius.circular(10),
          border: selected
              ? Border.all(
                  color: scheme.outlineVariant.withValues(alpha: 0.35),
                )
              : null,
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(iconData, color: fg),
              const SizedBox(height: 4),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: baseLabelStyle?.copyWith(color: fg),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
