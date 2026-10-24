import 'package:flutter/material.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/features/people_tags/domain/entity/people_tags_entities.dart';
import 'package:tentura/ui/l10n/l10n.dart';

import '../../domain/constellation_tag_filter.dart';
import '../../domain/entity/constellation_field.dart';

String constellationAutoTagName(L10n l10n, ConstellationAutoTagKind kind) =>
    switch (kind) {
      ConstellationAutoTagKind.mutualContact =>
        l10n.constellationAutoTagMutualContact,
      ConstellationAutoTagKind.iTrust => l10n.constellationAutoTagITrust,
      ConstellationAutoTagKind.trustsMe => l10n.constellationAutoTagTrustsMe,
    };

/// The Field's tag row: the viewer's own tags, then the automatic ones.
/// Tapping a chip toggles it in the tag lens.
class ConstellationTagRow extends StatelessWidget {
  const ConstellationTagRow({
    required this.ownTags,
    required this.autoTags,
    required this.filter,
    required this.onToggleOwn,
    required this.onToggleAuto,
    required this.onModeChanged,
    required this.onAddTag,
    super.key,
  });

  static const modeToggleKey = ValueKey('constellation-tag-mode-toggle');

  final List<PersonTag> ownTags;
  final List<ConstellationAutoTagKind> autoTags;
  final ConstellationTagFilter filter;
  final ValueChanged<String> onToggleOwn;
  final ValueChanged<ConstellationAutoTagKind> onToggleAuto;
  final ValueChanged<ConstellationTagFilterMode> onModeChanged;
  final VoidCallback onAddTag;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final tt = context.tt;
    final isAnd = filter.mode == ConstellationTagFilterMode.and;
    final selectedCount =
        filter.selectedOwn.length + filter.selectedAuto.length;
    return Wrap(
      spacing: tt.iconTextGap * 2,
      runSpacing: tt.tightGap * 2,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        if (ownTags.isEmpty)
          TextButton(
            onPressed: onAddTag,
            child: Text(l10n.constellationTagRowAdd),
          )
        else
          for (final tag in ownTags)
            _Toggle(
              selected: filter.selectedOwn.contains(tag.id),
              onTap: () => onToggleOwn(tag.id),
              child: PersonTagChip(
                glyph: tag.glyph,
                name: tag.name,
                colorIndex: tag.color,
              ),
            ),
        for (final kind in autoTags)
          _Toggle(
            selected: filter.selectedAuto.contains(kind),
            onTap: () => onToggleAuto(kind),
            child: AutoTagChip(
              name: constellationAutoTagName(l10n, kind),
              enabled: filter.selectedAuto.contains(kind),
            ),
          ),
        if (selectedCount >= 2)
          TextButton(
            key: modeToggleKey,
            onPressed: () => onModeChanged(
              isAnd
                  ? ConstellationTagFilterMode.or
                  : ConstellationTagFilterMode.and,
            ),
            child: Text(
              isAnd
                  ? l10n.constellationTagModeAnd
                  : l10n.constellationTagModeOr,
            ),
          ),
      ],
    );
  }
}

class _Toggle extends StatelessWidget {
  const _Toggle({
    required this.selected,
    required this.onTap,
    required this.child,
  });

  final bool selected;
  final VoidCallback onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    selected: selected,
    child: InkWell(
      onTap: onTap,
      customBorder: const StadiumBorder(),
      child: DecoratedBox(
        decoration: ShapeDecoration(
          shape: StadiumBorder(
            side: selected
                ? BorderSide(
                    color: Theme.of(context).colorScheme.primary,
                    width: 2,
                  )
                : BorderSide.none,
          ),
        ),
        child: child,
      ),
    ),
  );
}
