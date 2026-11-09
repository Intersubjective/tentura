import 'dart:async';

import 'package:flutter/gestures.dart' show HitTestResult;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderMetaData;
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/features/people_tags/domain/entity/people_tags_entities.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/navigation/app_navigator.dart';

import '../../domain/entity/constellation_field.dart';
import '../bloc/constellation_tag_lens_cubit.dart';
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

enum ConstellationTagRowLayout { scroll, wrap }

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
    this.layout = ConstellationTagRowLayout.scroll,
    this.onShowAll,
    super.key,
  });

  static const modeToggleKey = ValueKey('constellation-tag-mode-toggle');
  static const allTagsButtonKey = Key('constellation-tag-all-tags');
  static const scrollRowKey = Key('constellation-tags-scroll');

  static const clearAllKey = Key('constellation-tags-clear-all');
  static const selectAllKey = Key('constellation-tags-select-all');

  final List<PersonTag> ownTags;
  final List<ConstellationAutoTagKind> autoTags;
  final ConstellationTagFilter filter;
  final ValueChanged<String> onToggleOwn;
  final ValueChanged<ConstellationAutoTagKind> onToggleAuto;
  final ValueChanged<ConstellationTagFilterMode> onModeChanged;
  final VoidCallback onAddTag;
  final ValueChanged<PersonTag>? onPlaceMagnet;
  final void Function(PersonTag tag, Offset globalPosition)? onMagnetDrop;
  final ConstellationTagRowLayout layout;
  final VoidCallback? onShowAll;

  Widget _ownChip(
    PersonTag tag, {
    required bool selected,
    double? maxChipWidth,
  }) {
    final chip = _Toggle(
      selected: selected,
      onTap: () => onToggleOwn(tag.id),
      child: PersonTagChip(
        glyph: tag.glyph,
        name: tag.name,
        colorIndex: tag.color,
        maxWidth: maxChipWidth,
        selected: selected,
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

  List<Widget> _wrapChipChildren(BuildContext context) {
    final l10n = L10n.of(context)!;
    final tt = context.tt;
    final maxChipWidth =
        MediaQuery.sizeOf(context).width - 2 * tt.screenHPadding;
    final chips = <Widget>[];
    if (ownTags.isEmpty) {
      chips.add(
        TextButton(
          onPressed: onAddTag,
          child: Text(l10n.constellationTagRowAdd),
        ),
      );
    } else {
      for (final tag in ownTags) {
        chips.add(
          MetaData(
            metaData: ConstellationTagChipDrop(tag.id),
            behavior: HitTestBehavior.translucent,
            child: _ownChip(
              tag,
              maxChipWidth: maxChipWidth,
              selected: filter.selectedOwn.contains(tag.id),
            ),
          ),
        );
      }
    }
    for (final kind in autoTags) {
      final isSelected = filter.selectedAuto.contains(kind);
      chips.add(
        _Toggle(
          selected: isSelected,
          onTap: () => onToggleAuto(kind),
          child: AutoTagChip(
            name: constellationAutoTagName(l10n, kind),
            selected: isSelected,
            enabled: isSelected,
          ),
        ),
      );
    }
    return chips;
  }

  List<Widget> _scrollChipChildren(BuildContext context) {
    final l10n = L10n.of(context)!;
    final tt = context.tt;
    final gap = SizedBox(width: tt.iconTextGap * 2);
    final chips = <Widget>[];
    if (ownTags.isEmpty) {
      chips.add(
        TextButton(
          onPressed: onAddTag,
          child: Text(l10n.constellationTagRowAdd),
        ),
      );
    } else {
      for (final tag in ownTags) {
        if (chips.isNotEmpty) chips.add(gap);
        chips.add(
          _scrollFocusChip(
            child: MetaData(
              metaData: ConstellationTagChipDrop(tag.id),
              behavior: HitTestBehavior.translucent,
              child: _ownChip(
                tag,
                selected: filter.selectedOwn.contains(tag.id),
              ),
            ),
          ),
        );
      }
    }
    for (final kind in autoTags) {
      if (chips.isNotEmpty) chips.add(gap);
      final isSelected = filter.selectedAuto.contains(kind);
      chips.add(
        _scrollFocusChip(
          child: _Toggle(
            selected: isSelected,
            onTap: () => onToggleAuto(kind),
            child: AutoTagChip(
              name: constellationAutoTagName(l10n, kind),
              selected: isSelected,
              enabled: isSelected,
            ),
          ),
        ),
      );
    }
    return chips;
  }

  Widget _scrollFocusChip({required Widget child}) => Builder(
    builder: (chipContext) => Focus(
      onFocusChange: (focused) {
        if (focused) {
          Scrollable.ensureVisible(
            chipContext,
            alignment: 0.5,
          );
        }
      },
      child: child,
    ),
  );

  Widget _modeToggle(BuildContext context) {
    final l10n = L10n.of(context)!;
    final isAnd = filter.mode == ConstellationTagFilterMode.and;
    return TextButton(
      key: modeToggleKey,
      onPressed: () => onModeChanged(
        isAnd ? ConstellationTagFilterMode.or : ConstellationTagFilterMode.and,
      ),
      child: Text(
        isAnd ? l10n.constellationTagModeAnd : l10n.constellationTagModeOr,
      ),
    );
  }

  Widget _allTagsButton(BuildContext context) {
    final l10n = L10n.of(context)!;
    final selectedCount =
        filter.selectedOwn.length + filter.selectedAuto.length;
    final semanticsLabel = selectedCount == 0
        ? l10n.constellationTagAllTags
        : l10n.constellationTagAllTagsSelected(selectedCount);
    return Semantics(
      button: true,
      label: semanticsLabel,
      child: Tooltip(
        message: l10n.constellationTagAllTags,
        child: IconButton(
          key: allTagsButtonKey,
          onPressed: onShowAll,
          icon: Badge(
            isLabelVisible: selectedCount > 0,
            label: Text('$selectedCount'),
            child: const Icon(Icons.label_outline),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final tt = context.tt;
    final theme = Theme.of(context);
    final selectedCount =
        filter.selectedOwn.length + filter.selectedAuto.length;
    final maxRowHeight = tt.buttonHeight + 2 * tt.tightGap;

    if (layout == ConstellationTagRowLayout.wrap) {
      return Wrap(
        spacing: tt.iconTextGap * 2,
        runSpacing: tt.tightGap * 2,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          ..._wrapChipChildren(context),
          if (selectedCount >= 2) _modeToggle(context),
        ],
      );
    }

    final scrollChips = _scrollChipChildren(context);
    return Material(
      color: theme.colorScheme.surface,
      child: Semantics(
        container: true,
        label: l10n.constellationTagsSection,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: maxRowHeight),
          child: Row(
            children: [
              Padding(
                padding: EdgeInsetsDirectional.only(start: tt.screenHPadding),
                child: _allTagsButton(context),
              ),
              if (selectedCount >= 2) _modeToggle(context),
              Expanded(
                child: TenturaEdgeFadedRow(
                  fadeKeyPrefix: 'constellation.tags',
                  color: theme.colorScheme.surface,
                  child: SingleChildScrollView(
                    key: scrollRowKey,
                    scrollDirection: Axis.horizontal,
                    padding: EdgeInsetsDirectional.only(
                      end: tt.screenHPadding,
                      start: tt.tightGap,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: scrollChips,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

Future<void> showConstellationAllTagsSheet({
  required BuildContext context,
  required ConstellationTagLensCubit lensCubit,
  required List<PersonTag> ownTags,
  required List<ConstellationAutoTagKind> autoTags,
  required VoidCallback onAddTag,
}) {
  final l10n = L10n.of(context)!;
  return showTenturaAdaptiveSheet<void>(
    context: context,
    builder: (sheetContext) {
      final tt = sheetContext.tt;
      return BlocBuilder<ConstellationTagLensCubit, ConstellationTagFilter>(
        bloc: lensCubit,
        builder: (context, filter) {
          final ownIds = ownTags.map((t) => t.id).toSet();
          final autoSet = autoTags.toSet();
          final allSelected =
              (ownIds.isEmpty || filter.selectedOwn.containsAll(ownIds)) &&
              (autoSet.isEmpty || filter.selectedAuto.containsAll(autoSet));
          return SingleChildScrollView(
            key: const Key('constellation-all-tags-sheet-scroll'),
            child: Padding(
              padding: EdgeInsets.all(tt.screenHPadding),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    l10n.constellationTagsSheetTitle,
                    style: Theme.of(sheetContext).textTheme.titleMedium,
                  ),
                  SizedBox(height: tt.sectionGap),
                  Wrap(
                    spacing: tt.iconTextGap * 2,
                    runSpacing: tt.tightGap,
                    children: [
                      TextButton(
                        key: ConstellationTagRow.clearAllKey,
                        onPressed: filter.isEmpty
                            ? null
                            : () => lensCubit.clearAll(),
                        child: Text(l10n.constellationTagsClearAll),
                      ),
                      TextButton(
                        key: ConstellationTagRow.selectAllKey,
                        onPressed: allSelected
                            ? null
                            : () => lensCubit.selectAll(
                                ownTagIds: ownIds,
                                autoKinds: autoTags,
                              ),
                        child: Text(l10n.constellationTagsSelectAll),
                      ),
                    ],
                  ),
                  SizedBox(height: tt.rowGap),
                  ConstellationTagRow(
                    layout: ConstellationTagRowLayout.wrap,
                    ownTags: ownTags,
                    autoTags: autoTags,
                    filter: filter,
                    onToggleOwn: lensCubit.toggleOwn,
                    onToggleAuto: lensCubit.toggleAuto,
                    onModeChanged: lensCubit.setMode,
                    onAddTag: onAddTag,
                  ),
                  SizedBox(height: tt.sectionGap),
                  Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: TextButton(
                      key: const Key('constellation-tags-manage'),
                      onPressed: () {
                        Navigator.of(sheetContext).pop();
                        unawaited(
                          GetIt.I<AppNavigator>().openPeopleTags(),
                        );
                      },
                      child: Text(l10n.constellationTagsManage),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      );
    },
  );
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
      child: child,
    ),
  );
}
