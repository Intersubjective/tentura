import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/utils/ui_utils.dart';

import 'package:tentura/features/evaluation/domain/entity/evaluation_participant.dart';
import 'package:tentura/features/evaluation/domain/entity/evaluation_value.dart';
import 'package:tentura/features/evaluation/ui/bloc/evaluation_cubit.dart';
import 'package:tentura/features/evaluation/ui/widget/evaluation_detail_sheet.dart';

@RoutePage()
class ReviewContributionsScreen extends StatelessWidget implements AutoRouteWrapper {
  const ReviewContributionsScreen({
    @PathParam('id') this.id = '',
    super.key,
  });

  final String id;

  @override
  Widget wrappedRoute(BuildContext context) => BlocProvider(
        create: (_) {
          final c = EvaluationCubit.fromGetIt(beaconId: id);
          unawaited(c.loadParticipantsOnly());
          return c;
        },
        child: this,
      );

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.evaluationAcknowledgeTitle),
      ),
      body: BlocConsumer<EvaluationCubit, EvaluationState>(
        listener: commonScreenBlocListener,
        builder: (context, state) {
          if (state.isLoading) {
            return const Center(child: CircularProgressIndicator.adaptive());
          }
          return Column(
            children: [
              Expanded(
                child: ListView(
                  padding: kPaddingAll,
                  children: [
                    Text(
                      l10n.evaluationPrivacyBlock,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 12),
                    for (final p in state.participants)
                      _ParticipantTile(
                        participant: p,
                        onTap: () async {
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
                        onPressed: () =>
                            context.read<EvaluationCubit>().finalize(),
                        child: Text(l10n.evaluationSubmitFinish),
                      ),
                      TextButton(
                        onPressed: () =>
                            context.read<EvaluationCubit>().skip(),
                        child: Text(l10n.evaluationSkipForNow),
                      ),
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
    return Card(
      child: ListTile(
        title: Text(participant.title),
        subtitle: Text(
          '${participant.contributionSummary}\n${participant.causalHint}',
          maxLines: 3,
        ),
        trailing: Text(status, style: Theme.of(context).textTheme.labelSmall),
        onTap: onTap,
      ),
    );
  }
}
