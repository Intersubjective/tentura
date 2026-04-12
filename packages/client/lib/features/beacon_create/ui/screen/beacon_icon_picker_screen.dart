import 'package:flutter/material.dart';

import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/beacon_identity_catalog.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/widget/beacon_identity_tile.dart';

import '../widget/beacon_color_selector.dart';

/// Result of [BeaconIconPickerScreen.show]; `iconCode == null` means cleared identity.
typedef BeaconIconPickerResult = ({
  String? iconCode,
  int? iconBackground,
});

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
  }) =>
      showDialog<BeaconIconPickerResult>(
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

class _BeaconIconPickerScreenState extends State<BeaconIconPickerScreen>
    with TickerProviderStateMixin {
  late final TabController _tabController = TabController(
    length: 1 + BeaconIdentityCategory.values.length,
    vsync: this,
  );

  String _query = '';
  late String? _iconCode = widget.initialIconCode;
  late int? _iconBackground = widget.initialIconBackground;

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  String _categoryLabel(L10n l10n, BeaconIdentityCategory c) => switch (c) {
        BeaconIdentityCategory.meta => l10n.beaconIdentityCategoryMeta,
        BeaconIdentityCategory.community =>
          l10n.beaconIdentityCategoryCommunity,
        BeaconIdentityCategory.essentials =>
          l10n.beaconIdentityCategoryEssentials,
        BeaconIdentityCategory.home => l10n.beaconIdentityCategoryHome,
        BeaconIdentityCategory.mobility =>
          l10n.beaconIdentityCategoryMobility,
        BeaconIdentityCategory.communication =>
          l10n.beaconIdentityCategoryCommunication,
        BeaconIdentityCategory.money => l10n.beaconIdentityCategoryMoney,
        BeaconIdentityCategory.health => l10n.beaconIdentityCategoryHealth,
        BeaconIdentityCategory.safety => l10n.beaconIdentityCategorySafety,
        BeaconIdentityCategory.work => l10n.beaconIdentityCategoryWork,
        BeaconIdentityCategory.tech => l10n.beaconIdentityCategoryTech,
        BeaconIdentityCategory.nature => l10n.beaconIdentityCategoryNature,
        BeaconIdentityCategory.weather =>
          l10n.beaconIdentityCategoryWeather,
        BeaconIdentityCategory.culture =>
          l10n.beaconIdentityCategoryCulture,
        BeaconIdentityCategory.education =>
          l10n.beaconIdentityCategoryEducation,
        BeaconIdentityCategory.animals =>
          l10n.beaconIdentityCategoryAnimals,
        BeaconIdentityCategory.civic => l10n.beaconIdentityCategoryCivic,
      };

  List<MapEntry<String, BeaconIconDefinition>> _filteredEntries(L10n l10n) {
    var e = kBeaconIdentityIcons.entries.toList();
    final tab = _tabController.index;
    if (tab > 0) {
      final cat = BeaconIdentityCategory.values[tab - 1];
      e = e.where((x) => x.value.category == cat).toList();
    }
    if (_query.trim().isNotEmpty) {
      final q = _query.trim().toLowerCase();
      e = e
          .where(
            (x) =>
                x.key.toLowerCase().contains(q) ||
                x.value.label.toLowerCase().contains(q) ||
                _categoryLabel(l10n, x.value.category).toLowerCase().contains(q),
          )
          .toList();
    }
    return e;
  }

  void _onDone() {
    Navigator.of(context).pop((
      iconCode: _iconCode,
      iconBackground: _iconBackground,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final entries = _filteredEntries(l10n);
    final now = DateTime.timestamp();
    final previewBeacon = Beacon(
      createdAt: now,
      updatedAt: now,
      iconCode: _iconCode,
      iconBackground: _iconBackground,
    );

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Row(
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
        ),
        actions: [
          if (_iconCode != null)
            TextButton(
              onPressed: () => setState(() {
                _iconCode = null;
                _iconBackground = null;
              }),
              child: Text(l10n.beaconSymbolClear),
            ),
          TextButton(
            onPressed: _onDone,
            child: Text(l10n.beaconSymbolDone),
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
              onChanged: (v) => setState(() => _query = v),
            ),
          ),
          TabBar(
            controller: _tabController,
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            onTap: (_) => setState(() {}),
            tabs: [
              Tab(text: l10n.beaconSymbolCategoryAll),
              for (final c in BeaconIdentityCategory.values)
                Tab(text: _categoryLabel(l10n, c)),
            ],
          ),
          Expanded(
            child: CustomScrollView(
              slivers: [
                if (entries.isEmpty)
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
                  )
                else
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
                          final sel = _iconCode == entry.key;
                          return Material(
                            color: sel
                                ? scheme.primaryContainer
                                : scheme.surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(10),
                            child: InkWell(
                              borderRadius: BorderRadius.circular(10),
                              onTap: () => setState(() {
                                _iconCode = entry.key;
                                _iconBackground ??=
                                    kBeaconIdentityPalette.first.backgroundArgb;
                              }),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 4,
                                  vertical: 6,
                                ),
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      entry.value.icon,
                                      color: sel
                                          ? scheme.onPrimaryContainer
                                          : scheme.onSurfaceVariant,
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      entry.value.label,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      textAlign: TextAlign.center,
                                      style: theme.textTheme.labelSmall
                                          ?.copyWith(
                                        color: sel
                                            ? scheme.onPrimaryContainer
                                            : scheme.onSurfaceVariant,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                        childCount: entries.length,
                      ),
                    ),
                  ),
              ],
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
                    Opacity(
                      opacity: _iconCode == null ? 0.4 : 1,
                      child: IgnorePointer(
                        ignoring: _iconCode == null,
                        child: BeaconColorSelector(
                          selectedArgb: _iconBackground,
                          onSelected: (v) =>
                              setState(() => _iconBackground = v),
                        ),
                      ),
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
