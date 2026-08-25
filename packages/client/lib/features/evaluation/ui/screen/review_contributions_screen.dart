import 'dart:async';

import 'package:intl/intl.dart';

import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/contacts/contact_name_overlay.dart';
import 'package:tentura/domain/entity/image_entity.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/evaluation/domain/entity/evaluation_participant.dart';
import 'package:tentura/features/evaluation/domain/entity/evaluation_value.dart';
import 'package:tentura/features/evaluation/ui/bloc/evaluation_cubit.dart';
import 'package:tentura/features/evaluation/ui/presenter/evaluation_value_presenter.dart';
import 'package:tentura/features/evaluation/ui/widget/evaluation_detail_sheet.dart';
import 'package:tentura/features/evaluation/ui/widget/evaluation_privacy_info_row.dart';
import 'package:tentura/features/profile/ui/bloc/profile_cubit.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/test_ids.dart';
import 'package:tentura/ui/widget/self_aware_profile_avatar.dart';
import 'package:tentura/ui/widget/self_user_highlight.dart';

@RoutePage()
class ReviewContributionsScreen extends StatelessWidget
    implements AutoRouteWrapper {
  const ReviewContributionsScreen({
    @PathParam('id') required this.id,
    @QueryParam('draft') this.draft = false,
    super.key,
  });

  final String id;
  final bool draft;

  @override
  Widget wrappedRoute(BuildContext context) => BlocProvider(
    create: (_) {
      final cubit = EvaluationCubit.fromGetIt(
        beaconId: id,
        isDraftMode: draft,
      );
      unawaited(cubit.loadParticipantsOnly());
      return cubit;
    },
    child: this,
  );

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final tt = context.tt;
    final cubit = context.read<EvaluationCubit>();
    final actionButtonStyle = FilledButton.styleFrom(
      minimumSize: Size.fromHeight(tt.buttonHeight),
    );

    return Scaffold(
      appBar: TenturaTopBar.of(
        leading: const _EvaluationLeadingButton(),
        context,
        title: Text(
          draft
              ? l10n.evaluationAcknowledgeTitleDraft
              : l10n.evaluationAcknowledgeTitle,
        ),
        progress: BlocSelector<EvaluationCubit, EvaluationState, bool>(
          selector: (state) => state.isLoading,
          builder: (context, loading) =>
              TenturaTopBar.loadingBar(context, loading),
        ),
      ),
      body: SafeArea(
        child: TenturaContentColumn(
          child: BlocBuilder<EvaluationCubit, EvaluationState>(
            builder: (context, state) {
              if (state.isLoading && state.participants.isEmpty) {
                return const Center(
                  child: CircularProgressIndicator.adaptive(),
                );
              }
              if (state.participants.isEmpty) {
                return Center(
                  child: Padding(
                    padding: tt.cardPadding,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (state.beaconTitle.isNotEmpty) ...[
                          Text(
                            state.beaconTitle,
                            style: Theme.of(context).textTheme.titleMedium,
                            textAlign: TextAlign.center,
                          ),
                          SizedBox(height: tt.sectionGap),
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
              final items = _participantItems(context, state);
              final canSend = !state.isLoading && state.canFinalize;
              return Column(
                children: [
                  Expanded(
                    child: ListView.builder(
                      padding: tt.cardPadding,
                      itemCount: items.length,
                      itemBuilder: (_, index) => items[index],
                    ),
                  ),
                  Padding(
                    padding: tt.cardPadding,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          l10n.evaluationProgress(
                            state.reviewedCount,
                            state.totalCount,
                          ),
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        if (!canSend && !state.isDraftMode) ...[
                          SizedBox(height: tt.tightGap),
                          Text(
                            l10n.evaluationProgressIncompleteHint,
                            textAlign: TextAlign.center,
                            style: TenturaText.status(
                              Theme.of(context).colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                        SizedBox(height: tt.rowGap),
                        FilledButton(
                          key: TestIds.key(TestIds.evaluationSubmit),
                          style: actionButtonStyle,
                          onPressed: canSend ? cubit.finalize : null,
                          child: Text(
                            draft
                                ? l10n.evaluationDraftDone
                                : l10n.evaluationSubmitFinish,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  List<Widget> _participantItems(
    BuildContext context,
    EvaluationState state,
  ) {
    final l10n = L10n.of(context)!;
    final byRole = <EvaluationParticipantRole, List<EvaluationParticipant>>{};
    for (final participant in state.participants) {
      byRole.putIfAbsent(participant.role, () => []).add(participant);
    }
    final output = <Widget>[];
    if (state.beaconTitle.isNotEmpty) {
      output.add(
        Text(state.beaconTitle, style: Theme.of(context).textTheme.titleMedium),
      );
      output.add(SizedBox(height: context.tt.iconTextGap));
    }

    output.add(
      Padding(
        padding: EdgeInsets.only(bottom: context.tt.rowGap),
        child: EvaluationPrivacyInfoRow(
          shortLabel: state.isDraftMode
              ? l10n.evaluationReviewListPrivacyTitleDraft
              : l10n.evaluationReviewListPrivacyTitle,
          fullText: state.isDraftMode
              ? l10n.evaluationReviewListPrivacyDraft
              : l10n.evaluationReviewListPrivacyLive(
                  l10n.evaluationCannotEvaluate,
                ),
        ),
      ),
    );

    final closesRaw = state.windowInfo?.closesAt;
    final closes = closesRaw == null ? null : DateTime.tryParse(closesRaw);
    if (!state.isDraftMode && closes != null) {
      final formatted = DateFormat.yMMMd(
        Localizations.localeOf(context).toLanguageTag(),
      ).format(closes.toLocal());
      output.add(
        Padding(
          padding: EdgeInsets.only(bottom: context.tt.rowGap),
          child: Text(
            l10n.evaluationReviewDeadline(formatted),
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      );
    }
    void addRole(EvaluationParticipantRole role, String title) {
      final participants = byRole[role];
      if (participants == null || participants.isEmpty) {
        return;
      }
      output.add(
        Padding(
          padding: EdgeInsets.only(top: context.tt.rowGap),
          child: Semantics(
            header: true,
            child: Text(title, style: Theme.of(context).textTheme.titleSmall),
          ),
        ),
      );
      for (final participant in participants) {
        output.add(
          _ParticipantTile(
            participant: participant,
            isDraftMode: state.isDraftMode,
            isLoading: state.isLoading,
            onTap: () => _openDetail(context, participant),
            onCannotEvaluateToggle: () =>
                _toggleCannotEvaluate(context, participant),
          ),
        );
      }
    }

    addRole(EvaluationParticipantRole.author, l10n.evaluationSectionAuthor);
    addRole(
      EvaluationParticipantRole.committer,
      l10n.evaluationSectionHelpOfferer,
    );
    addRole(
      EvaluationParticipantRole.forwarder,
      l10n.evaluationSectionForwarder,
    );
    return output;
  }

  Future<void> _openDetail(
    BuildContext context,
    EvaluationParticipant participant,
  ) async {
    await showEvaluationDetailSheet(
      context: context,
      participant: participant,
      isDraftMode: draft,
      onSave: (value, note, acknowledgedHelpTags) =>
          context.read<EvaluationCubit>().submitOne(
            evaluatedUserId: participant.userId,
            value: value,
            note: note,
            acknowledgedHelpTags: acknowledgedHelpTags,
          ),
    );
  }

  Future<void> _toggleCannotEvaluate(
    BuildContext context,
    EvaluationParticipant participant,
  ) async {
    final cubit = context.read<EvaluationCubit>();
    final selected = participant.currentValue == EvaluationValue.noBasis &&
        (draft || participant.isSubmitted || participant.hasAnswered);
    if (selected) {
      await cubit.clearOne(evaluatedUserId: participant.userId);
      return;
    }
    final hasExistingWork =
        (participant.currentValue != null &&
            participant.currentValue != EvaluationValue.noBasis) ||
        participant.note.trim().isNotEmpty ||
        participant.reasonTags.isNotEmpty ||
        participant.acknowledgedHelpTags.isNotEmpty;
    if (hasExistingWork) {
      final shouldReplace = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(L10n.of(context)!.evaluationCannotEvaluate),
          content: Text(
            L10n.of(context)!.evaluationCannotEvaluateReplacement,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(L10n.of(context)!.buttonCancel),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(L10n.of(context)!.evaluationCannotEvaluate),
            ),
          ],
        ),
      );
      if (shouldReplace != true || !context.mounted) {
        return;
      }
    }
    await cubit.submitOne(
      evaluatedUserId: participant.userId,
      value: EvaluationValue.noBasis,
      note: '',
      acknowledgedHelpTags: const <String>[],
    );
  }
}

class _EvaluationLeadingButton extends StatelessWidget {
  const _EvaluationLeadingButton();

  @override
  Widget build(BuildContext context) => const AutoLeadingButton();
}

class _ParticipantTile extends StatelessWidget {
  const _ParticipantTile({
    required this.participant,
    required this.isDraftMode,
    required this.isLoading,
    required this.onTap,
    required this.onCannotEvaluateToggle,
  });

  final EvaluationParticipant participant;
  final bool isDraftMode;
  final bool isLoading;
  final VoidCallback onTap;
  final VoidCallback onCannotEvaluateToggle;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final theme = Theme.of(context);
    final tt = context.tt;
    final value = participant.currentValue;
    final profile = Profile(
      id: participant.userId,
      displayName: participant.displayName,
      contactName: contactNameOf(participant.userId),
      image: participant.imageId.isEmpty
          ? null
          : ImageEntity(id: participant.imageId, authorId: participant.userId),
    );
    final ready = isDraftMode ? participant.hasAnswered : participant.isSubmitted;
    final presentation = value == null || !ready || value == EvaluationValue.noBasis
        ? null
        : presentEvaluationValue(value, l10n);
    final cannotEvaluateSelected = value == EvaluationValue.noBasis && ready;
    final statusLabel = cannotEvaluateSelected
        ? l10n.evaluationNoBasisLabel
        : !ready && value != null
        ? l10n.evaluationBannerDraftReview
        : presentation?.label ?? l10n.evaluationNotReviewed;

    return Opacity(
      opacity: cannotEvaluateSelected ? 0.55 : 1,
      child: Card(
        margin: EdgeInsets.only(bottom: tt.rowGap),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final subtitleStatus =
                constraints.maxWidth < 500 ||
                MediaQuery.textScalerOf(context).scale(1) >= 2;
            final subtitle = <Widget>[];
            if (participant.contributionSummary.isNotEmpty) {
              subtitle.add(Text(participant.contributionSummary));
            }
            if (participant.note.trim().isNotEmpty && ready) {
              subtitle.add(Text(participant.note.trim()));
            }
            if (subtitleStatus) {
              subtitle.add(
                Text(statusLabel, style: theme.textTheme.labelLarge),
              );
            }
            return Column(
              children: [
                ListTile(
                  key: TestIds.key(
                    TestIds.evaluationParticipant(participant.userId),
                  ),
                  leading: SelfAwareAvatar.small(profile: profile),
                  title: BlocBuilder<ProfileCubit, ProfileState>(
                    builder: (context, state) => Text(
                      SelfUserHighlight.displayName(
                        l10n,
                        profile,
                        state.profile.id,
                      ),
                      style: SelfUserHighlight.nameStyle(
                        theme,
                        theme.textTheme.bodyLarge,
                        SelfUserHighlight.profileIsSelf(
                          profile,
                          state.profile.id,
                        ),
                      ),
                    ),
                  ),
                  subtitle: subtitle.isEmpty
                      ? null
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: subtitle,
                        ),
                  trailing: subtitleStatus
                      ? null
                      : Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (presentation != null)
                              Icon(
                                presentation.icon,
                                size: tt.iconSize,
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            SizedBox(width: tt.tightGap),
                            Text(
                              statusLabel,
                              style: theme.textTheme.labelLarge,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                  onTap: isLoading || cannotEvaluateSelected ? null : onTap,
                ),
                const TenturaHairlineDivider(),
                Padding(
                  padding: tt.cardPadding,
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: TenturaCommandButton(
                      key: TestIds.key(
                        TestIds.evaluationCannotEvaluate(participant.userId),
                      ),
                      label: l10n.evaluationCannotEvaluate,
                      selected: cannotEvaluateSelected,
                      onPressed: isLoading ? null : onCannotEvaluateToggle,
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
