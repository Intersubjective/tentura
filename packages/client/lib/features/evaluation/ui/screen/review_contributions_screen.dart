import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:tentura/domain/entity/image_entity.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/evaluation/domain/entity/evaluation_participant.dart';
import 'package:tentura/features/evaluation/domain/entity/evaluation_value.dart';
import 'package:tentura/features/evaluation/ui/bloc/evaluation_cubit.dart';
import 'package:tentura/features/evaluation/ui/widget/evaluation_detail_sheet.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/utils/ui_utils.dart';
import 'package:tentura/ui/widget/avatar_rated.dart';

@RoutePage()
class ReviewContributionsScreen extends StatelessWidget implements AutoRouteWrapper {
  const ReviewContributionsScreen({
    @PathParam('id') this.id = '',
    @QueryParam('draft') this.draft = false,
    super.key,
  });

  final String id;
  final bool draft;

  @override
  Widget wrappedRoute(BuildContext context) => BlocProvider(
        create: (_) {
          final c = EvaluationCubit.fromGetIt(
            beaconId: id,
            isDraftMode: draft,
          );
          unawaited(c.loadParticipantsOnly());
          return c;
        },
        child: this,
      );

  Future<void> _onSubmitFinish(
    BuildContext context,
    EvaluationCubit cubit,
    EvaluationState state,
  ) async {
    final l10n = L10n.of(context)!;
    final allNoBasis = state.participants.isNotEmpty &&
        state.participants.every(
          (p) => p.currentValue == EvaluationValue.noBasis,
        );
    if (allNoBasis && context.mounted) {
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(l10n.evaluationAllNoBasisConfirmTitle),
          content: Text(l10n.evaluationAllNoBasisConfirmBody),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: Text(MaterialLocalizations.of(ctx).okButtonLabel),
            ),
          ],
        ),
      );
    }
    await cubit.finalize();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    return Scaffold(
      appBar: AppBar(
        title: Text(
          draft
              ? l10n.evaluationAcknowledgeTitleDraft
              : l10n.evaluationAcknowledgeTitle,
        ),
      ),
      body: BlocConsumer<EvaluationCubit, EvaluationState>(
        listener: commonScreenBlocListener,
        builder: (context, state) {
          if (state.isLoading && state.participants.isEmpty) {
            return const Center(child: CircularProgressIndicator.adaptive());
          }
          if (state.participants.isEmpty) {
            return Center(
              child: Padding(
                padding: kPaddingAll,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (state.beaconTitle.isNotEmpty) ...[
                      Text(
                        state.beaconTitle,
                        style: Theme.of(context).textTheme.titleMedium,
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 12),
                    ],
                    Text(
                      l10n.evaluationEmptyTargets,
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            );
          }
          final theme = Theme.of(context);
          return Column(
            children: [
              Expanded(
                child: ListView(
                  padding: kPaddingAll,
                  children: [
                    if (state.beaconTitle.isNotEmpty) ...[
                      Text(
                        state.beaconTitle,
                        style: theme.textTheme.titleMedium,
                      ),
                      const SizedBox(height: 6),
                    ],
                    if (!draft) ...[
                      Builder(
                        builder: (ctx) {
                          final closesRaw = state.windowInfo?.closesAt;
                          if (closesRaw == null || closesRaw.isEmpty) {
                            return const SizedBox.shrink();
                          }
                          final closes = DateTime.tryParse(closesRaw);
                          if (closes == null) {
                            return const SizedBox.shrink();
                          }
                          final formatted = DateFormat.yMMMd(
                            Localizations.localeOf(ctx).toLanguageTag(),
                          ).format(closes.toLocal());
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: Text(
                              l10n.evaluationReviewDeadline(formatted),
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          );
                        },
                      ),
                    ],
                    Text(
                      l10n.evaluationPrivacyBlock,
                      style: theme.textTheme.bodySmall,
                    ),
                    const SizedBox(height: 12),
                    ..._participantSections(
                      context: context,
                      participants: state.participants,
                      onOpen: (p) async {
                        await showEvaluationDetailSheet(
                          context: context,
                          participant: p,
                          onSave: (v, tags, note) => context
                              .read<EvaluationCubit>()
                              .submitOne(
                                evaluatedUserId: p.userId,
                                value: v,
                                reasonTags: tags,
                                note: note,
                              ),
                        );
                      },
                    ),
                  ],
                ),
              ),
              SafeArea(
                child: Padding(
                  padding: kPaddingAll,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        l10n.evaluationProgress(
                          state.reviewedCount,
                          state.totalCount,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 8),
                      FilledButton(
                        onPressed: () => draft
                            ? context.read<EvaluationCubit>().finalize()
                            : _onSubmitFinish(
                                context,
                                context.read<EvaluationCubit>(),
                                state,
                              ),
                        child: Text(
                          draft
                              ? l10n.evaluationDraftDone
                              : l10n.evaluationSubmitFinish,
                        ),
                      ),
                      if (!draft) ...[
                        TextButton(
                          onPressed: () =>
                              context.read<EvaluationCubit>().skip(),
                          child: Text(l10n.evaluationSkipForNow),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

List<Widget> _participantSections({
  required BuildContext context,
  required List<EvaluationParticipant> participants,
  required Future<void> Function(EvaluationParticipant p) onOpen,
}) {
  final l10n = L10n.of(context)!;
  final theme = Theme.of(context);
  final byRole = <EvaluationParticipantRole, List<EvaluationParticipant>>{};
  for (final p in participants) {
    byRole.putIfAbsent(p.role, () => []).add(p);
  }
  void addRole(
    EvaluationParticipantRole role,
    String sectionTitle,
    List<Widget> out,
  ) {
    final list = byRole[role];
    if (list == null || list.isEmpty) {
      return;
    }
    out.add(
      Padding(
        padding: const EdgeInsets.only(top: 8, bottom: 4),
        child: Text(
          sectionTitle,
          style: theme.textTheme.titleSmall,
        ),
      ),
    );
    for (final p in list) {
      out.add(
        _ParticipantTile(
          participant: p,
          onTap: () => onOpen(p),
        ),
      );
    }
  }

  final out = <Widget>[];
  addRole(
    EvaluationParticipantRole.author,
    l10n.evaluationSectionAuthor,
    out,
  );
  addRole(
    EvaluationParticipantRole.committer,
    l10n.evaluationSectionCommitter,
    out,
  );
  addRole(
    EvaluationParticipantRole.forwarder,
    l10n.evaluationSectionForwarder,
    out,
  );
  return out;
}

class _ParticipantTile extends StatelessWidget {
  const _ParticipantTile({
    required this.participant,
    required this.onTap,
  });

  final EvaluationParticipant participant;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final status = participant.currentValue == null
        ? l10n.evaluationNotReviewed
        : (participant.currentValue == EvaluationValue.noBasis
            ? l10n.evaluationNoBasisLabel
            : l10n.evaluationReviewed);
    final profile = Profile(
      id: participant.userId,
      title: participant.title,
      image: participant.imageId.isNotEmpty
          ? ImageEntity(id: participant.imageId, authorId: participant.userId)
          : null,
    );
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: AvatarRated.small(
          profile: profile,
          withRating: false,
        ),
        title: Text(participant.title),
        subtitle: Text(
          '${participant.contributionSummary}\n${participant.causalHint}',
          maxLines: 3,
        ),
        isThreeLine: true,
        trailing: Text(status, style: Theme.of(context).textTheme.labelSmall),
        onTap: onTap,
      ),
    );
  }
}
