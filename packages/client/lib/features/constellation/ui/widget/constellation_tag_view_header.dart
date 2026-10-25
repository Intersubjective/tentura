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
            Row(
              children: [
                Expanded(
                  child: Text(
                    widget.title,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      color: swatch.onContainer,
                    ),
                  ),
                ),
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
            ),
            Wrap(
              spacing: tt.tightGap,
              children: [
                for (final (key, others, label) in [
                  (
                    'constellation-tag-view-hide',
                    ConstellationTagViewOthers.hide,
                    l10n.constellationTagViewOthersHide,
                  ),
                  (
                    'constellation-tag-view-dots',
                    ConstellationTagViewOthers.dots,
                    l10n.constellationTagViewOthersDots,
                  ),
                  (
                    'constellation-tag-view-as-is',
                    ConstellationTagViewOthers.asIs,
                    l10n.constellationTagViewOthersAsIs,
                  ),
                ])
                  ChoiceChip(
                    key: Key(key),
                    label: Text(label),
                    selected: widget.others == others,
                    onSelected: (_) => widget.onOthers(others),
                  ),
              ],
            ),
            if (_finding) ...[
              TextField(
                key: const Key('constellation-tag-view-find-field'),
                autofocus: true,
                decoration: InputDecoration(
                  hintText: l10n.constellationTagViewFindHint,
                ),
                onChanged: (value) => setState(() => _query = value),
              ),
              Column(
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
              ),
            ],
          ],
        ),
      ),
    );
  }
}
