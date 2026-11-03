import 'package:flutter/material.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/ui/l10n/l10n.dart';

import '../../domain/constellation_people.dart';
import '../../domain/constellation_tag_view_scope.dart';

/// Top bar of the tag view: the viewed tags in the tag's colour with their
/// member count, the choice for everyone else, a name search over the members
/// and the way back to the Field.
class ConstellationTagViewHeader extends StatefulWidget {
  const ConstellationTagViewHeader({
    required this.title,
    required this.colorIndex,
    required this.others,
    required this.members,
    required this.onOthers,
    required this.onFound,
    required this.onForward,
    required this.onExit,
    super.key,
  });

  /// "Tags · count".
  final String title;
  final int colorIndex;
  final ConstellationTagViewOthers others;
  final List<ConstellationFieldPerson> members;
  final ValueChanged<ConstellationTagViewOthers> onOthers;
  final ValueChanged<String> onFound;
  final VoidCallback onForward;
  final VoidCallback onExit;

  @override
  State<ConstellationTagViewHeader> createState() =>
      _ConstellationTagViewHeaderState();
}

class _ConstellationTagViewHeaderState
    extends State<ConstellationTagViewHeader> {
  var _finding = false;
  var _query = '';

  static const _othersChoices = [
    (
      'constellation-tag-view-hide',
      ConstellationTagViewOthers.hide,
    ),
    (
      'constellation-tag-view-dots',
      ConstellationTagViewOthers.dots,
    ),
    (
      'constellation-tag-view-as-is',
      ConstellationTagViewOthers.asIs,
    ),
  ];

  List<Widget> _othersChips(L10n l10n) => [
    for (final (key, others) in _othersChoices)
      ChoiceChip(
        key: Key(key),
        label: Text(switch (others) {
          ConstellationTagViewOthers.hide =>
            l10n.constellationTagViewOthersHide,
          ConstellationTagViewOthers.dots =>
            l10n.constellationTagViewOthersDots,
          ConstellationTagViewOthers.asIs =>
            l10n.constellationTagViewOthersAsIs,
        }),
        selected: widget.others == others,
        onSelected: (_) => widget.onOthers(others),
      ),
  ];

  Widget _othersRow(L10n l10n, TenturaTokens tt) {
    final chips = _othersChips(l10n);
    final windowClass = windowClassForWidth(MediaQuery.sizeOf(context).width);
    if (windowClass == WindowClass.compact) {
      return TenturaEdgeFadedRow(
        fadeKeyPrefix: 'constellation.tag_view.others',
        color: context.tagColors.swatchFor(widget.colorIndex).container,
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (var i = 0; i < chips.length; i++) ...[
                if (i > 0) SizedBox(width: tt.tightGap),
                chips[i],
              ],
            ],
          ),
        ),
      );
    }
    return Wrap(spacing: tt.tightGap, children: chips);
  }

  Widget _findResults(
    List<ConstellationFieldPerson> matches,
    TenturaTokens tt,
  ) {
    final list = Column(
      key: const Key('constellation-tag-view-find-results'),
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final person in matches)
          ListTile(
            dense: true,
            title: Text(person.name),
            onTap: () => widget.onFound(person.id),
          ),
      ],
    );
    final windowClass = windowClassForWidth(MediaQuery.sizeOf(context).width);
    if (windowClass != WindowClass.compact) return list;
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: tt.fieldFindResultsMaxHeight),
      child: SingleChildScrollView(child: list),
    );
  }

  Widget _titleRow(
    BuildContext context,
    L10n l10n,
    Color onContainer,
  ) {
    final windowClass = windowClassForWidth(MediaQuery.sizeOf(context).width);
    final titleStyle = Theme.of(context).textTheme.titleSmall?.copyWith(
      color: onContainer,
    );
    if (windowClass != WindowClass.compact) {
      return Row(
        children: [
          Expanded(child: Text(widget.title, style: titleStyle)),
          TextButton(
            onPressed: () => setState(() => _finding = !_finding),
            child: Text(l10n.constellationTagViewFind),
          ),
          TextButton(
            onPressed: widget.onForward,
            child: Text(l10n.constellationTagLensForward),
          ),
          TextButton(
            key: const Key('constellation-tag-view-exit'),
            onPressed: widget.onExit,
            child: Text(l10n.constellationTagViewExit),
          ),
        ],
      );
    }
    return Row(
      children: [
        Expanded(
          child: Text(
            widget.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: titleStyle,
          ),
        ),
        IconButton(
          key: const Key('constellation-tag-view-exit'),
          onPressed: widget.onExit,
          tooltip: l10n.constellationTagViewExit,
          icon: const Icon(Icons.close),
        ),
        MenuAnchor(
          menuChildren: [
            MenuItemButton(
              onPressed: () => setState(() => _finding = !_finding),
              child: Text(l10n.constellationTagViewFind),
            ),
            MenuItemButton(
              onPressed: widget.onForward,
              child: Text(l10n.constellationTagLensForward),
            ),
          ],
          builder: (context, controller, child) => IconButton(
            key: const Key('constellation-tag-view-overflow'),
            onPressed: () {
              if (controller.isOpen) {
                controller.close();
              } else {
                controller.open();
              }
            },
            icon: const Icon(Icons.more_vert),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final tt = context.tt;
    final swatch = context.tagColors.swatchFor(widget.colorIndex);
    final matches = [
      for (final person in widget.members)
        if (constellationPersonMatches(person, _query)) person,
    ];
    return Material(
      color: swatch.container,
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: tt.screenHPadding,
          vertical: tt.tightGap,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _titleRow(context, l10n, swatch.onContainer),
            _othersRow(l10n, tt),
            if (_finding) ...[
              TextField(
                key: const Key('constellation-tag-view-find-field'),
                autofocus: true,
                decoration: InputDecoration(
                  hintText: l10n.constellationTagViewFindHint,
                ),
                onChanged: (value) => setState(() => _query = value),
              ),
              _findResults(matches, tt),
            ],
          ],
        ),
      ),
    );
  }
}
