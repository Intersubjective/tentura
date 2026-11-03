import 'package:flutter/gestures.dart' show HitTestResult;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderMetaData;

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/features/people_tags/domain/entity/people_tags_entities.dart';
import 'package:tentura/ui/l10n/l10n.dart';

import '../../domain/constellation_tag_filter.dart';
import '../../domain/entity/constellation_field.dart';
import 'constellation_tag_magnet_control.dart';

String constellationAutoTagName(L10n l10n, ConstellationAutoTagKind kind) =>
    switch (kind) {
      ConstellationAutoTagKind.mutualContact =>
        l10n.constellationAutoTagMutualContact,
      ConstellationAutoTagKind.iTrust => l10n.constellationAutoTagITrust,
      ConstellationAutoTagKind.trustsMe => l10n.constellationAutoTagTrustsMe,
    };

/// Marks the chip of own tag [tagId] as a place a person node can be dropped.
@immutable
class ConstellationTagChipDrop {
  const ConstellationTagChipDrop(this.tagId);

  final String tagId;
}

/// The own tag whose chip is under [globalPosition], or null.
String? constellationTagChipDropAt(
  BuildContext context,
  Offset globalPosition,
) {
  final result = HitTestResult();
  WidgetsBinding.instance.hitTestInView(
    result,
    globalPosition,
    View.of(context).viewId,
  );
  for (final entry in result.path) {
    final target = entry.target;
    if (target is RenderMetaData &&
        target.metaData is ConstellationTagChipDrop) {
      return (target.metaData as ConstellationTagChipDrop).tagId;
    }
  }
  return null;
}

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
    this.onPlaceMagnet,
    this.onMagnetDrop,
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
  final ValueChanged<PersonTag>? onPlaceMagnet;
  final void Function(PersonTag tag, Offset globalPosition)? onMagnetDrop;

  Widget _ownChip(PersonTag tag) {
    final chip = _Toggle(
      selected: filter.selectedOwn.contains(tag.id),
      onTap: () => onToggleOwn(tag.id),
      child: PersonTagChip(
        glyph: tag.glyph,
        name: tag.name,
        colorIndex: tag.color,
      ),
    );
    final place = onPlaceMagnet;
    if (place == null) return chip;
    return Builder(
      builder: (context) => ConstellationTagMagnetControl(
        actionLabel: L10n.of(context)!.constellationPlaceAsMagnet,
        onAction: () => place(tag),
        onDrop: (position) => onMagnetDrop?.call(tag, position),
        child: chip,
      ),
    );
  }

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
            MetaData(
              metaData: ConstellationTagChipDrop(tag.id),
              behavior: HitTestBehavior.translucent,
              child: _ownChip(tag),
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
