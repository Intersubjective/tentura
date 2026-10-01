import 'package:flutter/material.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/features/closure/domain/entity/closure_member.dart';
import 'package:tentura/features/closure/domain/closure_exception.dart';
import 'package:tentura_root/domain/entity/localizable.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/utils/ui_utils.dart';

import '../bloc/closure_author_cubit.dart';
import '../widget/closure_footer.dart';
import '../widget/closure_member_row.dart';
import '../widget/closure_preview.dart';
import '../widget/closure_split_section.dart';
import '../widget/closure_story_field.dart';

/// Body of the author's «Подвести итоги» screen — extracted for widget tests
/// (no AutoRouter). Needs a [ClosureAuthorCubit] above it.
class ClosureAuthorView extends StatelessWidget {
  const ClosureAuthorView({super.key});

  @override
  Widget build(BuildContext context) =>
      BlocConsumer<ClosureAuthorCubit, ClosureAuthorState>(
        listenWhen: (p, c) => p.noticeTick != c.noticeTick,
        listener: (context, state) {
          final e = state.notice;
          if (e is ClosureStaleEpochException) {
            showSnackBar(context, text: L10n.of(context)!.closureAuthorStale);
          } else if (e != null) {
            showSnackBar(
              context,
              text: e is LocalizableException
                  ? (L10n.of(context)!.localeName == 'ru' ? e.toRu : e.toEn)
                  : e.toString(),
              isError: true,
              error: e,
            );
          }
        },
        builder: (context, state) {
          if (state.data == null) {
            return Center(
              child: state.loadError == null
                  ? const CircularProgressIndicator.adaptive()
                  : IconButton(
                      onPressed: context.read<ClosureAuthorCubit>().fetch,
                      icon: const Icon(Icons.refresh),
                    ),
            );
          }
          return _Body(state: state);
        },
      );
}

class _Body extends StatelessWidget {
  const _Body({required this.state});

  final ClosureAuthorState state;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final theme = Theme.of(context);
    final cubit = context.read<ClosureAuthorCubit>();
    final data = state.data!;
    // Active members first, leavers after, original order kept in each group.
    final members = <ClosureMember>[
      ...data.members.where((m) => m.departure == null),
      ...data.members.where((m) => m.departure != null),
    ];
    const gap = SizedBox(height: TenturaSpacing.section);
    // ListView builds its children lazily: long rosters stay cheap.
    return ListView(
      padding: context.tt.cardPadding,
      children: [
        Text(
          l10n.closureAuthorOutcomeHint,
          style: theme.textTheme.bodySmall,
        ),
        if (data.members.length == 2) ...[
          const SizedBox(height: TenturaSpacing.row),
          Text(l10n.closureAuthorTwoMembers, style: theme.textTheme.bodySmall),
        ],
        for (final (i, m) in members.indexed)
          ClosureMemberRow(
            autofocus: i == 0,
            key: ValueKey('closure.author.member.${m.id}'),
            member: m,
            outcome: data.outcomes?[m.id],
            marked: data.myMarks.contains(m.id),
            onOutcome: (o) => cubit.setOutcome(m.id, o),
            onMark: (on) => cubit.setMark(m.id, on: on),
          ),
        gap,
        ClosureSplitSection(state: state),
        gap,
        ClosurePreview(data: data),
        gap,
        ClosureStoryField(initial: data.story, onSave: cubit.saveStory),
        gap,
        ClosureFooter(state: state),
      ],
    );
  }
}
