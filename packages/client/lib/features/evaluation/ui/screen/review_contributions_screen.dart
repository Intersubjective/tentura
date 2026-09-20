import 'dart:async';

import 'package:intl/intl.dart';

import 'package:flutter/material.dart';

import 'package:tentura/app/router/root_router.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/contacts/contact_name_overlay.dart';
import 'package:tentura/domain/entity/image_entity.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/evaluation/domain/entity/evaluation_participant.dart';
import 'package:tentura/features/evaluation/domain/entity/evaluation_value.dart';
import 'package:tentura/features/evaluation/domain/review_package_state.dart';
import 'package:tentura/features/evaluation/ui/bloc/evaluation_cubit.dart';
import 'package:tentura/features/evaluation/ui/presenter/evaluation_participant_context.dart';
import 'package:tentura/features/evaluation/ui/presenter/evaluation_value_presenter.dart';
import 'package:tentura/features/evaluation/ui/widget/evaluation_detail_sheet.dart';
import 'package:tentura/features/evaluation/ui/widget/evaluation_privacy_info_row.dart';
import 'package:tentura/features/evaluation/ui/widget/review_open_clear_listener.dart';
import 'package:tentura/features/profile/ui/bloc/profile_cubit.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/test_ids.dart';
import 'package:tentura/ui/widget/self_aware_profile_avatar.dart';
import 'package:tentura/ui/widget/self_user_highlight.dart';

@RoutePage()
class ReviewContributionsScreen extends StatefulWidget
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
    child: ReviewOpenClearListener(beaconId: id, child: this),
  );

  @override
  State<ReviewContributionsScreen> createState() =>
      _ReviewContributionsScreenState();
}

class _ReviewContributionsScreenState extends State<ReviewContributionsScreen> {
  /// Optional cards the reviewer chose to hide (D8). Screen-local on purpose:
  /// it is never persisted, never told to the cubit, and the stored rows stay
  /// in the package.
  final _skipped = <String>{};

  bool get draft => widget.draft;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final tt = context.tt;

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
              if (!draft && _isLifecycleEnd(state.packageState)) {
                // The window vanished or closed (D12/D13): there is no
                // read-only checklist, so the whole body explains why.
                return _LifecyclePackageBody(
                  state: state,
                  onOpenRequest: () => _onPackageDone(context, state),
                );
              }
              if (state.participants.isEmpty) {
                // Also the `empty` package state: nothing to review, no CTA.
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
              return LayoutBuilder(
                builder: (context, constraints) => Column(
                  children: [
                    Expanded(
                      child: ListView.builder(
                        padding: tt.cardPadding,
                        itemCount: items.length,
                        itemBuilder: (_, index) => items[index],
                      ),
                    ),
                    // At large text scales the status copy alone can be taller
                    // than the screen. The checklist keeps the majority of the
                    // viewport; the bar scrolls inside its share instead of
                    // squeezing the list down to nothing.
                    ConstrainedBox(
                      constraints: BoxConstraints(
                        maxHeight: constraints.maxHeight * _maxBottomBarShare,
                      ),
                      child: SingleChildScrollView(
                        child: Padding(
                          padding: tt.cardPadding,
                          child: _PackageBottomBar(
                            state: state,
                            onSend: context.read<EvaluationCubit>().finalize,
                            onDone: () => _onPackageDone(context, state),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
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
    for (final participant in state.requiredParticipants) {
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
        child: Text(
          l10n.evaluationListIntro,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );

    output.add(
      Padding(
        padding: EdgeInsets.only(bottom: context.tt.rowGap),
        child: EvaluationPrivacyInfoRow(
          shortLabel: state.isDraftMode
              ? l10n.evaluationReviewListPrivacyTitleDraft
              : l10n.evaluationReviewListPrivacyTitle,
          fullText: state.isDraftMode
              ? l10n.evaluationReviewListPrivacyDraft
              : l10n.evaluationReviewListPrivacyLive,
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
    void addHeader(String title) {
      output.add(
        Padding(
          padding: EdgeInsets.only(top: context.tt.rowGap),
          child: Semantics(
            header: true,
            child: Text(title, style: Theme.of(context).textTheme.titleSmall),
          ),
        ),
      );
    }

    void addTile(EvaluationParticipant participant, {required bool optional}) {
      output.add(
        _ParticipantTile(
          participant: participant,
          isDraftMode: state.isDraftMode,
          isLoading: state.isLoading,
          onTap: () => _openDetail(context, participant),
          onCannotEvaluate: optional
              ? null
              : () => _markCannotEvaluate(context, participant),
          onSkip: optional ? () => _skip(participant) : null,
          onUndoCannotEvaluate: () => _undoCannotEvaluate(context, participant),
        ),
      );
    }

    if (state.windowInfo?.viewerPackageOptional ?? false) {
      output.add(
        Padding(
          padding: EdgeInsets.only(bottom: context.tt.rowGap),
          child: Text(
            l10n.evaluationOwnPackageOptional,
            style: TenturaText.bodySmall(
              Theme.of(context).colorScheme.onSurfaceVariant,
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
      addHeader(title);
      for (final participant in participants) {
        addTile(participant, optional: false);
      }
    }

    if (byRole.isNotEmpty) {
      addHeader(l10n.evaluationSectionRequired);
      addRole(EvaluationParticipantRole.author, l10n.evaluationSectionAuthor);
      addRole(
        EvaluationParticipantRole.committer,
        l10n.evaluationSectionHelpOfferer,
      );
      // A leaver who is still a required target reads as a helper: same
      // section, same prompt (UNIT 09).
      addRole(
        EvaluationParticipantRole.formerCommitter,
        l10n.evaluationSectionHelpOfferer,
      );
      addRole(
        EvaluationParticipantRole.forwarder,
        l10n.evaluationSectionForwarder,
      );
    }

    final optional = [
      for (final participant in state.optionalParticipants)
        if (!_skipped.contains(participant.userId)) participant,
    ];
    if (optional.isNotEmpty) {
      addHeader(l10n.evaluationSectionOptional);
      output.add(
        Padding(
          padding: EdgeInsets.only(bottom: context.tt.rowGap),
          child: Text(
            l10n.evaluationOptionalHint,
            style: TenturaText.bodySmall(
              Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      );
      for (final participant in optional) {
        addTile(participant, optional: true);
      }
    }
    return output;
  }

  /// Hides an optional card for this visit only (D8): the stored row, if any,
  /// stays in the package and is still sent.
  void _skip(EvaluationParticipant participant) =>
      setState(() => _skipped.add(participant.userId));

  static bool _isLifecycleEnd(ReviewPackageState packageState) =>
      packageState == ReviewPackageState.paused ||
      packageState == ReviewPackageState.closed ||
      packageState == ReviewPackageState.closedUnsent;

  void _onPackageDone(BuildContext context, EvaluationState state) {
    final router = context.router;
    if (router.canPop()) {
      unawaited(router.maybePop());
    } else {
      // Deep-link entry: there is no checklist to pop back from.
      unawaited(router.replace(BeaconViewRoute(id: state.beaconId)));
    }
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

  Future<void> _undoCannotEvaluate(
    BuildContext context,
    EvaluationParticipant participant,
  ) => context.read<EvaluationCubit>().clearOne(
    evaluatedUserId: participant.userId,
  );

  Future<void> _markCannotEvaluate(
    BuildContext context,
    EvaluationParticipant participant,
  ) async {
    final cubit = context.read<EvaluationCubit>();
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

/// The share of the viewport the bottom bar may take before it scrolls itself.
const _maxBottomBarShare = 0.4;

/// The bottom bar states the package state in words and offers exactly one
/// action for it (#162). Checklist completeness is progress, never the gate.
class _PackageBottomBar extends StatelessWidget {
  const _PackageBottomBar({
    required this.state,
    required this.onSend,
    required this.onDone,
  });

  final EvaluationState state;
  final VoidCallback onSend;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final theme = Theme.of(context);
    final tt = context.tt;
    final buttonStyle = FilledButton.styleFrom(
      minimumSize: Size.fromHeight(tt.buttonHeight),
    );
    final canSend = !state.isLoading && state.canFinalize;

    Widget status(String text) => Text(
      text,
      key: TestIds.key(TestIds.evaluationPackageStatus),
      textAlign: TextAlign.center,
      style: theme.textTheme.bodySmall,
    );

    Widget muted(String text) => Text(
      text,
      textAlign: TextAlign.center,
      style: TenturaText.status(theme.colorScheme.onSurfaceVariant),
    );

    Widget cta(String label, {required bool enabled}) => FilledButton(
      key: TestIds.key(TestIds.evaluationSubmit),
      style: buttonStyle,
      onPressed: enabled ? onSend : null,
      child: Text(label),
    );

    Widget column(List<Widget> children) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: children,
    );

    if (state.isDraftMode) {
      return column([
        status(l10n.evaluationProgress(state.reviewedCount, state.totalCount)),
        SizedBox(height: tt.rowGap),
        cta(l10n.evaluationDraftDone, enabled: canSend),
      ]);
    }

    final required = state.requiredParticipants.toList();
    final optional = state.optionalParticipants.toList();
    final requiredAnswered = required.where((p) => p.hasAnswer).length;
    final progress = l10n.evaluationProgressSplit(
      requiredAnswered,
      required.length,
      optional.where((p) => p.hasAnswer).length,
      optional.length,
    );

    switch (state.packageState) {
      case ReviewPackageState.inProgress:
        return column([
          status(progress),
          SizedBox(height: tt.tightGap),
          muted(
            l10n.evaluationProgressRemainingHint(
              required.length - requiredAnswered,
            ),
          ),
          SizedBox(height: tt.rowGap),
          cta(l10n.evaluationSubmitFinish, enabled: false),
        ]);

      case ReviewPackageState.readyToSend:
        return column([
          status(progress),
          SizedBox(height: tt.rowGap),
          cta(l10n.evaluationSubmitFinish, enabled: canSend),
          SizedBox(height: tt.tightGap),
          muted(l10n.evaluationPackageSentHint),
        ]);

      case ReviewPackageState.sent:
        final sentAt = state.windowInfo?.sentAt;
        return column([
          status(
            sentAt == null
                ? progress
                : l10n.evaluationPackageSentAt(
                    DateFormat.yMMMd(
                      Localizations.localeOf(context).toLanguageTag(),
                    ).format(sentAt.toLocal()),
                  ),
          ),
          SizedBox(height: tt.tightGap),
          muted(l10n.evaluationPackageSentHint),
          SizedBox(height: tt.rowGap),
          FilledButton.tonal(
            key: TestIds.key(TestIds.evaluationDone),
            style: buttonStyle,
            onPressed: onDone,
            child: Text(l10n.evaluationPackageDone),
          ),
        ]);

      case ReviewPackageState.changedNotSent:
        return column([
          status(l10n.evaluationPackageDirtyTitle),
          SizedBox(height: tt.tightGap),
          muted(l10n.evaluationPackageDirtyBody),
          SizedBox(height: tt.rowGap),
          cta(l10n.evaluationSubmitChanges, enabled: canSend),
        ]);

      // `empty` and the lifecycle states never reach here: the body states
      // them instead.
      case ReviewPackageState.empty:
      case ReviewPackageState.notEnrolled:
      case ReviewPackageState.paused:
      case ReviewPackageState.closed:
      case ReviewPackageState.closedUnsent:
        return column([status(progress)]);
    }
  }
}

/// Replaces the checklist once the window is paused or closed: no list, no
/// send action (D13).
class _LifecyclePackageBody extends StatelessWidget {
  const _LifecyclePackageBody({
    required this.state,
    required this.onOpenRequest,
  });

  final EvaluationState state;
  final VoidCallback onOpenRequest;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final tt = context.tt;
    final textTheme = Theme.of(context).textTheme;
    final paused = state.packageState == ReviewPackageState.paused;
    return Center(
      child: SingleChildScrollView(
        padding: tt.cardPadding,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (paused) ...[
              Text(
                l10n.evaluationPausedTitle,
                style: textTheme.titleMedium,
                textAlign: TextAlign.center,
              ),
              SizedBox(height: tt.tightGap),
            ],
            Text(
              switch (state.packageState) {
                ReviewPackageState.paused => l10n.evaluationPausedBody,
                ReviewPackageState.closed => l10n.evaluationClosedSentBody,
                _ => l10n.evaluationClosedUnsentBody,
              },
              textAlign: TextAlign.center,
            ),
            SizedBox(height: tt.rowGap),
            if (paused)
              FilledButton.tonal(
                onPressed: onOpenRequest,
                child: Text(l10n.evaluationPausedAction),
              )
            else
              TextButton(
                onPressed: () => context.router.push(
                  ReceivedReviewsRoute(id: state.beaconId),
                ),
                child: Text(l10n.reviewWindowViewReceivedReviewsAction),
              ),
          ],
        ),
      ),
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
    required this.onCannotEvaluate,
    required this.onSkip,
    required this.onUndoCannotEvaluate,
  });

  final EvaluationParticipant participant;
  final bool isDraftMode;
  final bool isLoading;
  final VoidCallback onTap;

  /// Required cards only: opting out of reviewing this person.
  final VoidCallback? onCannotEvaluate;

  /// Optional cards only: hiding the card for this visit (D8).
  final VoidCallback? onSkip;
  final VoidCallback onUndoCannotEvaluate;

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
    // Live readiness is the stored row, the same predicate the send gate uses.
    final ready = isDraftMode ? participant.hasAnswered : participant.hasAnswer;
    final presentation =
        value == null || !ready || value == EvaluationValue.noBasis
        ? null
        : presentEvaluationValue(value, l10n);
    final cannotEvaluateSelected = value == EvaluationValue.noBasis && ready;
    final statusLabel = cannotEvaluateSelected
        ? l10n.evaluationNoBasisLabel
        : !ready && value != null
        ? l10n.evaluationBannerDraftReview
        : presentation?.label ?? l10n.evaluationNotReviewed;

    return Card(
      margin: EdgeInsets.only(bottom: tt.rowGap),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final subtitleStatus =
              constraints.maxWidth < 500 ||
              MediaQuery.textScalerOf(context).scale(1) >= 2;
          final subtitle = <Widget>[];
          final participantContext = presentParticipantContext(
            l10n: l10n,
            locale: Localizations.localeOf(context),
            participant: participant,
          );
          subtitle.add(Text(participantContext.line));
          final offerLine = participantContext.offerLine;
          if (offerLine != null) subtitle.add(Text(offerLine));
          final endedLine = participantContext.endedLine;
          if (endedLine != null) subtitle.add(Text(endedLine));
          if (participant.note.trim().isNotEmpty && ready) {
            subtitle.add(Text(participant.note.trim()));
          }
          if (subtitleStatus) {
            subtitle.add(Text(statusLabel, style: theme.textTheme.labelLarge));
          }
          final header = ListTile(
            key: TestIds.key(
              TestIds.evaluationParticipant(participant.userId),
            ),
            leading: SelfAwareAvatar.small(profile: profile),
            title: BlocBuilder<ProfileCubit, ProfileState>(
              builder: (context, state) => Text(
                SelfUserHighlight.displayName(l10n, profile, state.profile.id),
                style: SelfUserHighlight.nameStyle(
                  theme,
                  theme.textTheme.bodyLarge,
                  SelfUserHighlight.profileIsSelf(profile, state.profile.id),
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
                        Text(
                          presentation.emoji,
                          style: TextStyle(fontSize: tt.iconSize, height: 1),
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
          );
          return Column(
            children: [
              // Muted only in the header: the undo action below must keep
              // full contrast while the card reads as set aside.
              cannotEvaluateSelected
                  ? Opacity(opacity: 0.55, child: header)
                  : header,
              const TenturaHairlineDivider(),
              Padding(
                padding: tt.cardPadding,
                child: cannotEvaluateSelected
                    ? _CannotEvaluateFooter(
                        userId: participant.userId,
                        isLoading: isLoading,
                        onUndo: onUndoCannotEvaluate,
                      )
                    : _ReviewActions(
                        userId: participant.userId,
                        isLoading: isLoading,
                        stacked: subtitleStatus,
                        hasReview:
                            value != null && value != EvaluationValue.noBasis,
                        onReview: onTap,
                        onCannotEvaluate: onCannotEvaluate,
                        onSkip: onSkip,
                      ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// Card actions while the participant can still be reviewed: the review CTA is
/// the primary affordance, opting out is a demoted text action (issue #161).
class _ReviewActions extends StatelessWidget {
  const _ReviewActions({
    required this.userId,
    required this.isLoading,
    required this.stacked,
    required this.hasReview,
    required this.onReview,
    required this.onCannotEvaluate,
    required this.onSkip,
  });

  final String userId;
  final bool isLoading;

  /// Compact width or large text scale: full-width buttons on their own rows
  /// instead of a side-by-side pair that would overflow.
  final bool stacked;
  final bool hasReview;
  final VoidCallback onReview;
  final VoidCallback? onCannotEvaluate;

  /// Optional cards hide instead of opting out: skipping keeps the stored row.
  final VoidCallback? onSkip;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final tt = context.tt;
    final review = FilledButton(
      key: TestIds.key(TestIds.evaluationReviewAction(userId)),
      onPressed: isLoading ? null : onReview,
      child: Text(
        hasReview
            ? l10n.evaluationCardActionEdit
            : l10n.evaluationCardActionReview,
        textAlign: TextAlign.center,
      ),
    );
    final skip = onSkip;
    final optOut = skip == null
        ? TextButton(
            key: TestIds.key(TestIds.evaluationCannotEvaluate(userId)),
            onPressed: isLoading ? null : onCannotEvaluate,
            child: Text(
              l10n.evaluationCannotEvaluate,
              textAlign: TextAlign.center,
            ),
          )
        : TextButton(
            onPressed: isLoading ? null : skip,
            child: Text(
              l10n.evaluationOptionalSkip,
              textAlign: TextAlign.center,
            ),
          );
    if (stacked) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          review,
          SizedBox(height: tt.tightGap),
          optOut,
        ],
      );
    }
    return Wrap(
      spacing: tt.rowGap,
      runSpacing: tt.tightGap,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [review, optOut],
    );
  }
}

/// Card footer once the reviewer opted out: states the consequence in words
/// and offers the way back.
class _CannotEvaluateFooter extends StatelessWidget {
  const _CannotEvaluateFooter({
    required this.userId,
    required this.isLoading,
    required this.onUndo,
  });

  final String userId;
  final bool isLoading;
  final VoidCallback onUndo;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final tt = context.tt;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.evaluationCannotEvaluateExplanation,
          style: TenturaText.bodySmall(
            Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        SizedBox(height: tt.tightGap),
        Align(
          alignment: AlignmentDirectional.centerEnd,
          child: TextButton(
            key: TestIds.key(TestIds.evaluationUndoCannotEvaluate(userId)),
            onPressed: isLoading ? null : onUndo,
            child: Text(l10n.evaluationCannotEvaluateUndo),
          ),
        ),
      ],
    );
  }
}
