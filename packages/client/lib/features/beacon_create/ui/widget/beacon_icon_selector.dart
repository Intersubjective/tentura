import 'package:flutter/material.dart';

import 'package:tentura/domain/entity/beacon_identity_catalog.dart';
import 'package:tentura/ui/l10n/l10n.dart';

/// Curated icon grid with category filter and search by key label.
class BeaconIconSelector extends StatefulWidget {
  const BeaconIconSelector({
    required this.selectedKey,
    required this.onSelected,
    required this.onClear,
    super.key,
  });

  final String? selectedKey;
  final ValueChanged<String> onSelected;
  final VoidCallback onClear;

  @override
  State<BeaconIconSelector> createState() => _BeaconIconSelectorState();
}

class _BeaconIconSelectorState extends State<BeaconIconSelector> {
  BeaconIdentityCategory? _filter;
  String _query = '';

  String _categoryLabel(L10n l10n, BeaconIdentityCategory c) => switch (c) {
        BeaconIdentityCategory.general => l10n.beaconIdentityCategoryGeneral,
        BeaconIdentityCategory.work => l10n.beaconIdentityCategoryWork,
        BeaconIdentityCategory.places => l10n.beaconIdentityCategoryPlaces,
        BeaconIdentityCategory.transport => l10n.beaconIdentityCategoryTransport,
        BeaconIdentityCategory.people => l10n.beaconIdentityCategoryPeople,
        BeaconIdentityCategory.health => l10n.beaconIdentityCategoryHealth,
        BeaconIdentityCategory.commerce => l10n.beaconIdentityCategoryCommerce,
        BeaconIdentityCategory.nature => l10n.beaconIdentityCategoryNature,
      };

  List<MapEntry<String, BeaconIconDefinition>> _filteredList(L10n l10n) {
    var e = kBeaconIdentityIcons.entries.toList();
    if (_filter != null) {
      e = e.where((x) => x.value.category == _filter).toList();
    }
    if (_query.trim().isNotEmpty) {
      final q = _query.trim().toLowerCase();
      e = e
          .where(
            (x) =>
                x.key.toLowerCase().contains(q) ||
                _categoryLabel(l10n, x.value.category).toLowerCase().contains(q),
          )
          .toList();
    }
    return e;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final entries = _filteredList(l10n);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          decoration: InputDecoration(
            hintText: l10n.beaconSymbolSearchHint,
            isDense: true,
            prefixIcon: const Icon(Icons.search, size: 20),
          ),
          onChanged: (v) => setState(() => _query = v),
        ),
        const SizedBox(height: 8),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              FilterChip(
                label: Text(l10n.beaconSymbolCategoryAll),
                selected: _filter == null,
                onSelected: (_) => setState(() => _filter = null),
              ),
              for (final c in BeaconIdentityCategory.values) ...[
                const SizedBox(width: 6),
                FilterChip(
                  label: Text(_categoryLabel(l10n, c)),
                  selected: _filter == c,
                  onSelected: (sel) =>
                      setState(() => _filter = sel ? c : null),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton(
            onPressed: widget.selectedKey == null ? null : widget.onClear,
            child: Text(l10n.beaconSymbolClear),
          ),
        ),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 5,
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
          ),
          itemCount: entries.length,
          itemBuilder: (_, i) {
            final entry = entries[i];
            final sel = widget.selectedKey == entry.key;
            return Material(
              color: sel
                  ? scheme.primaryContainer
                  : scheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(10),
              child: InkWell(
                borderRadius: BorderRadius.circular(10),
                onTap: () => widget.onSelected(entry.key),
                child: Icon(
                  entry.value.icon,
                  color: sel
                      ? scheme.onPrimaryContainer
                      : scheme.onSurfaceVariant,
                ),
              ),
            );
          },
        ),
      ],
    );
  }
}
