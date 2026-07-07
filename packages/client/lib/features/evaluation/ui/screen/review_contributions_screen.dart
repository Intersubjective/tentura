import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/contacts/contact_name_overlay.dart';
import 'package:tentura/domain/entity/image_entity.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/evaluation/domain/entity/evaluation_participant.dart';
import 'package:tentura/features/evaluation/domain/entity/evaluation_value.dart';
import 'package:tentura/features/evaluation/ui/bloc/evaluation_cubit.dart';
import 'package:tentura/features/evaluation/ui/widget/evaluation_detail_sheet.dart';
import 'package:tentura/features/evaluation/ui/widget/evaluation_privacy_info_row.dart';
import 'package:tentura/features/profile/ui/bloc/profile_cubit.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/widget/self_aware_profile_avatar.dart';
import 'package:tentura/ui/widget/self_user_highlight.dart';

@RoutePage()
class ReviewContributionsScreen extends StatelessWidget
    implements AutoRouteWrapper {
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
    final allNoBasis =
        state.participants.isNotEmpty &&
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
    final tt = context.tt;
    final cubit = context.read<EvaluationCubit>();
    final actionButtonStyle = FilledButton.styleFrom(
      minimumSize: Size.fromHeight(tt.buttonHeight),
    );
    return Scaffold(
      appBar: TenturaTopBar.of(
        context,
        leading: const AutoLeadingButton(),
        title: Text(
          draft
              ? l10n.evaluationAcknowledgeTitleDraft
              : l10n.evaluationAcknowledgeTitle,
        ),
        progress: BlocSelector<EvaluationCubit, EvaluationState, bool>(
          bloc: cubit,
          selector: (state) => state.isLoading,
          builder: TenturaTopBar.loadingBar,
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
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
                                  style: Theme.of(
                                    context,
                                  ).textTheme.titleMedium,
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
                    final listItems = _ReviewListItems.build(
                      context: context,
                      l10n: l10n,
                      state: state,
                      draft: draft,
                      onOpen: (p) async {
                        await showEvaluationDetailSheet(
                          context: context,
                          participant: p,
                          onSave: (v, tags, note, ackTags) =>
                              context.read<EvaluationCubit>().submitOne(
                                evaluatedUserId: p.userId,
                                value: v,
                                reasonTags: tags,
                                note: note,
                                acknowledgedHelpTags: ackTags.isEmpty
                                    ? null
                                    : ackTags,
                              ),
                        );
                      },
                    );
                    return Column(
                      children: [
                        Expanded(
                          child: ListView.builder(
                            padding: tt.cardPadding,
                            itemCount: listItems.length,
                            itemBuilder: listItems.itemBuilder,
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
                              ),
                              SizedBox(height: tt.rowGap),
                              FilledButton(
                                style: actionButtonStyle,
                                onPressed: state.isLoading
                                    ? null
                                    : () => draft
                                          ? cubit.finalize()
                                          : _onSubmitFinish(
                                              context,
                                              cubit,
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
                                  onPressed: state.isLoading
                                      ? null
                                      : cubit.skip,
                                  child: Text(l10n.evaluationSkipForNow),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ),
          ],
        ),
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
  final tt = context.tt;
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
        padding: EdgeInsets.only(
          top: tt.rowGap,
          bottom: tt.tightGap * 2,
        ),
        child: Semantics(
          header: true,
          child: Text(
            sectionTitle,
            style: theme.textTheme.titleSmall,
          ),
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
    l10n.evaluationSectionHelpOfferer,
    out,
  );
  addRole(
    EvaluationParticipantRole.forwarder,
    l10n.evaluationSectionForwarder,
    out,
  );
  return out;
}

class _ReviewListItems {
  const _ReviewListItems(this._builders);

  final List<Widget Function(BuildContext)> _builders;

  int get length => _builders.length;

  Widget itemBuilder(BuildContext context, int index) =>
      _builders[index](context);

  static _ReviewListItems build({
    required BuildContext context,
    required L10n l10n,
    required EvaluationState state,
    required bool draft,
    required Future<void> Function(EvaluationParticipant p) onOpen,
  }) {
    final theme = Theme.of(context);
    final tt = context.tt;
    final builders = <Widget Function(BuildContext)>[];

    if (state.beaconTitle.isNotEmpty) {
      builders.add(
        (_) => Text(
          state.beaconTitle,
          style: theme.textTheme.titleMedium,
        ),
      );
      builders.add((_) => SizedBox(height: tt.iconTextGap));
    }

    if (!draft) {
      final closesRaw = state.windowInfo?.closesAt;
      if (closesRaw != null && closesRaw.isNotEmpty) {
        final closes = DateTime.tryParse(closesRaw);
        if (closes != null) {
          builders.add(
            (ctx) {
              final formatted = DateFormat.yMMMd(
                Localizations.localeOf(ctx).toLanguageTag(),
              ).format(closes.toLocal());
              return Padding(
                padding: EdgeInsets.only(bottom: tt.rowGap),
                child: Text(
                  l10n.evaluationReviewDeadline(formatted),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              );
            },
          );
        }
      }
    }

    builders.add(
      (_) => EvaluationPrivacyInfoRow(
        shortLabel: l10n.evaluationPrivacyShort,
        fullText: l10n.evaluationPrivacyBlock,
      ),
    );
    builders.add((_) => SizedBox(height: tt.sectionGap));

    for (final section in _participantSections(
      context: context,
      participants: state.participants,
      onOpen: onOpen,
    )) {
      builders.add((_) => section);
    }

    return _ReviewListItems(builders);
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
    final profile = Profile(
      id: participant.userId,
      displayName: participant.displayName,
      contactName: contactNameOf(participant.userId),
      image: participant.imageId.isNotEmpty
          ? ImageEntity(id: participant.imageId, authorId: participant.userId)
          : null,
    );
    final tt = context.tt;
    final meId = context.read<ProfileCubit>().state.profile.id;
    final displayName = SelfUserHighlight.displayName(l10n, profile, meId);
    return Card(
      margin: EdgeInsets.only(bottom: tt.rowGap),
      child: Semantics(
        label: '$displayName. $status',
        child: ListTile(
          leading: SelfAwareAvatar.small(
            profile: profile,
          ),
          title: BlocBuilder<ProfileCubit, ProfileState>(
            buildWhen: (p, c) => p.profile.id != c.profile.id,
            builder: (context, state) {
              return Text(
                SelfUserHighlight.displayName(
                  l10n,
                  profile,
                  state.profile.id,
                ),
                style: SelfUserHighlight.nameStyle(
                  Theme.of(context),
                  Theme.of(context).textTheme.bodyLarge,
                  SelfUserHighlight.profileIsSelf(profile, state.profile.id),
                ),
              );
            },
          ),
          subtitle: Text(
            '${participant.contributionSummary}\n${participant.causalHint}',
            maxLines: 3,
          ),
          isThreeLine: true,
          trailing: Text(status, style: Theme.of(context).textTheme.labelSmall),
          onTap: onTap,
        ),
      ),
    );
  }
}
