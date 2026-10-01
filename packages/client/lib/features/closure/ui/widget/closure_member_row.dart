import 'package:flutter/material.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/features/closure/domain/entity/closure_member.dart';
import 'package:tentura/features/closure/domain/entity/closure_outcome.dart';
import 'package:tentura/ui/l10n/l10n.dart';

/// One helper: name, departure badge, bookmark toggle and the outcome picker
/// (a vertical list of three single-choice options).
class ClosureMemberRow extends StatelessWidget {
  const ClosureMemberRow({
    required this.member,
    required this.outcome,
    required this.marked,
    required this.onOutcome,
    required this.onMark,
    this.autofocus = false,
    super.key,
  });

  final ClosureMember member;
  final ClosureOutcome? outcome;
  final bool marked;
  final ValueChanged<ClosureOutcome> onOutcome;
  final ValueChanged<bool> onMark;

  /// Puts keyboard focus on this helper's first option when the screen opens.
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final theme = Theme.of(context);
    final name = member.displayName ?? member.id;
    final departure = switch (member.departure) {
      'voluntary' => l10n.closureAuthorMemberLeft,
      'removed' => l10n.closureAuthorMemberRemoved,
      _ => null,
    };
    final labels = {
      ClosureOutcome.done: l10n.closureAuthorOutcomeDone,
      ClosureOutcome.notDone: l10n.closureAuthorOutcomeNotDone,
      ClosureOutcome.cantJudge: l10n.closureAuthorOutcomeCantJudge,
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: TenturaSpacing.row),
          child: Row(
            children: [
              Flexible(
                child: Text(
                  name,
                  style: theme.textTheme.titleSmall,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (departure != null) ...[
                const SizedBox(width: TenturaSpacing.iconText),
                Text(
                  departure,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ],
          ),
        ),
        for (final (i, o) in ClosureOutcome.values.indexed)
          Row(
            children: [
              Expanded(
                child: _OutcomeOption(
                  label: labels[o]!,
                  semanticsLabel: l10n.closureAuthorOutcomeLabel(
                    name,
                    labels[o]!,
                  ),
                  selected: outcome == o,
                  autofocus: autofocus && i == 0,
                  onTap: () => onOutcome(o),
                ),
              ),
              // The bookmark sits on the first option's line so keyboard
              // focus walks one helper's controls before the next helper's.
              if (i == 0)
                Semantics(
                  container: true,
                  excludeSemantics: true,
                  button: true,
                  toggled: marked,
                  label: l10n.closureAuthorBookmarkLabel(name),
                  onTap: () => onMark(!marked),
                  child: IconButton(
                    onPressed: () => onMark(!marked),
                    icon: Icon(
                      marked ? Icons.bookmark : Icons.bookmark_border,
                    ),
                  ),
                ),
            ],
          ),
      ],
    );
  }
}

/// Under the 48 dp touch target (a tap on the whole row selects): three stacked options per helper
/// keep a long roster scannable.
const _optionMinHeight = kMinInteractiveDimension - 8;

class _OutcomeOption extends StatefulWidget {
  const _OutcomeOption({
    required this.label,
    required this.semanticsLabel,
    required this.selected,
    required this.autofocus,
    required this.onTap,
  });

  final String label;
  final String semanticsLabel;
  final bool selected;
  final bool autofocus;
  final VoidCallback onTap;

  @override
  State<_OutcomeOption> createState() => _OutcomeOptionState();
}

class _OutcomeOptionState extends State<_OutcomeOption> {
  final _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    // `InkWell.autofocus` loses to the route scope taking focus after the
    // first frame, so ask for focus once the frame is done.
    if (widget.autofocus) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _focusNode.requestFocus();
      });
    }
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final label = widget.label;
    final selected = widget.selected;
    final onTap = widget.onTap;
    return Semantics(
      container: true,
      excludeSemantics: true,
      button: true,
      inMutuallyExclusiveGroup: true,
      selected: selected,
      label: widget.semanticsLabel,
      onTap: onTap,
      child: InkWell(
        focusNode: _focusNode,
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: _optionMinHeight),
          child: Row(
            children: [
              Icon(
                selected
                    ? Icons.radio_button_checked
                    : Icons.radio_button_unchecked,
                color: selected
                    ? theme.colorScheme.primary
                    : theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: TenturaSpacing.avatarText),
              Expanded(child: Text(label, style: theme.textTheme.bodyMedium)),
            ],
          ),
        ),
      ),
    );
  }
}
