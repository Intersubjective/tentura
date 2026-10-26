import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/features/closure/ui/bloc/closure_author_cubit.dart';
import 'package:tentura/ui/l10n/l10n.dart';

/// Deadline, extend / close-now / reopen. Never shows who has answered.
class ClosureFooter extends StatelessWidget {
  const ClosureFooter({required this.state, super.key});

  final ClosureAuthorState state;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final theme = Theme.of(context);
    final cubit = context.read<ClosureAuthorCubit>();
    final data = state.data!;
    final fmt = DateFormat.MMMd(
      l10n.localeName,
    ).add_Hm();
    final outcomes = data.outcomes ?? const {};
    // #364: the server lets the author finish only once every member, removed
    // ones included, has an outcome (§P3).
    final needsOutcomes =
        !data.canCloseNow &&
        data.members.any((m) => !outcomes.containsKey(m.id));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.closureAuthorDeadline(fmt.format(data.closesAt.toLocal())),
          style: theme.textTheme.bodyMedium,
        ),
        if (needsOutcomes) ...[
          const SizedBox(height: TenturaSpacing.tight),
          Text(
            l10n.closureAuthorPickOutcomesHint,
            style: theme.textTheme.bodySmall,
          ),
        ],
        // Never beside an enabled «Finish now» (#364: it misled QA).
        // #632: the server sends earlyCloseAt only while the 48 h review grace
        // can matter (not in a small episode, someone left to answer it).
        if (!data.canCloseNow && data.earlyCloseAt != null) ...[
          const SizedBox(height: TenturaSpacing.tight),
          Text(
            l10n.closureAuthorCloseEarlyHint(
              fmt.format(data.earlyCloseAt!.toLocal()),
            ),
            style: theme.textTheme.bodySmall,
          ),
        ],
        // An enabled «Finish now» does not wait for anyone: say so (#733).
        if (data.canCloseNow) ...[
          const SizedBox(height: TenturaSpacing.tight),
          Text(
            l10n.closureAuthorCloseNowNote,
            style: theme.textTheme.bodySmall,
          ),
        ],
        const SizedBox(height: TenturaSpacing.row),
        Wrap(
          spacing: TenturaSpacing.row,
          children: [
            if (data.extensionsUsed < kClosureMaxExtensions)
              OutlinedButton(
                onPressed: cubit.extend,
                child: Text(l10n.closureAuthorExtend),
              ),
            FilledButton(
              onPressed: data.canCloseNow ? cubit.closeNow : null,
              child: Text(l10n.closureAuthorCloseNow),
            ),
            if (data.canReopen)
              TextButton(
                onPressed: cubit.reopen,
                child: Text(l10n.closureAuthorReopen),
              ),
          ],
        ),
      ],
    );
  }
}
