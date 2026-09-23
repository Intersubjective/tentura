import 'dart:async';
import 'package:tentura_root/domain/entity/beacon_status.dart';

import 'package:flutter/material.dart';

import 'package:tentura/app/router/root_router.dart';
import 'package:tentura/consts.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/ui/bloc/screen_cubit.dart';
import 'package:tentura/features/attention/ui/widget/request_attention_timeline_sheet.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/utils/ui_utils.dart';
import 'package:tentura/features/my_work/ui/widget/my_work_card_metadata_row.dart';
import 'package:tentura/features/my_work/ui/widget/my_work_status_line.dart';
import 'package:tentura/ui/widget/beacon_card_primitives.dart';
import 'package:tentura/ui/widget/beacon_request_preview_identity.dart';
import 'package:tentura/ui/presenter/beacon_phase_cta.dart';
import 'package:tentura/ui/presenter/beacon_phase_presenter.dart';
import 'package:tentura/ui/test_ids.dart';
import 'package:tentura/domain/entity/beacon_coordination_phase.dart';
import 'package:tentura/features/beacon/ui/dialog/beacon_close_confirm_dialog.dart';
import 'package:tentura/features/beacon/ui/util/beacon_lifecycle_ui.dart';
import 'package:tentura/features/beacon_view/ui/sheet/help_offer_tile_sheet.dart';
import 'package:tentura/features/beacon_view/ui/widget/beacon_hud_author_confirm_sheets.dart';
import 'package:tentura/features/my_work/ui/bloc/my_work_cubit.dart';
import 'package:tentura/features/my_work/ui/widget/my_work_obligation_block.dart';
import 'package:tentura/features/my_work/ui/widget/my_work_review_affordance.dart';
import 'package:tentura/features/my_work/domain/derive_my_work_card_attention.dart';
import 'package:tentura/features/my_work/ui/widget/my_work_card_attention_indicators.dart';
import 'package:tentura/features/my_work/ui/widget/my_work_last_event_row.dart';
import 'package:tentura/features/beacon/ui/dialog/beacon_delete_dialog.dart';
import 'package:tentura/features/beacon/ui/util/beacon_delete_ui.dart';
import 'package:tentura/features/beacon/ui/util/beacon_lineage_overflow_actions.dart';
import 'package:tentura/features/beacon/ui/widget/beacon_overflow_menu.dart';
import 'package:tentura/features/beacon/data/repository/beacon_repository.dart';
import 'package:tentura/features/evaluation/data/repository/evaluation_repository.dart';
import 'package:tentura/features/my_work/domain/entity/my_work_card_view_model.dart';
import 'package:tentura/features/profile/ui/bloc/profile_cubit.dart';

bool myWorkCloseBeaconEnabled(MyWorkCardViewModel vm) =>
    vm.beacon.status == BeaconStatus.open && vm.displayStatus != null;

/// Shared close confirm for a My Work card; the card carries no review
/// counts, so the beacon-scoped unsent count is fetched first.
Future<bool> myWorkConfirmCloseNow({
  required BuildContext context,
  required String beaconId,
  required EvaluationRepository evaluationRepository,
}) async {
  final review = await evaluationRepository.fetchReviewWindowStatus(beaconId);
  if (!context.mounted) return false;
  return showBeaconCloseNowConfirmSheet(
    context: context,
    unsentStartedPackages: review.unsentStartedPackages,
  );
}

/// Footer Forward CTA on authored My Work cards (gated by [Beacon.allowsForward]).
bool myWorkNeedsForwardCta(MyWorkCardViewModel vm) => vm.beacon.allowsForward;

bool myWorkExpectedRequiresReviewWindow(MyWorkCardViewModel vm) =>
    (vm.displayStatus?.everAcknowledgedCommitterCount ?? 0) > 0;

Future<void> _confirmAndDeleteMyWorkBeacon(
  BuildContext context, {
  required MyWorkCardViewModel vm,
}) async {
  final b = vm.beacon;
  final repo = GetIt.I<BeaconRepository>();
  final cubit = context.read<MyWorkCubit>();
  await Future<void>.delayed(Duration.zero);
  if (!context.mounted) return;
  if (await BeaconDeleteDialog.show(
        context,
        status: b.status,
        hasEverHadCommitter: beaconDeleteBlockedByCommitters(
          b,
          serverCanDelete: vm.displayStatus?.canDelete,
        ),
        onArchive: () => cubit.archiveBeacon(b.id),
      ) ??
      false) {
    await runBeaconDeleteWithRetry(
      context,
      delete: () => repo.delete(b.id),
    );
  }
}

class MyWorkCardRouter extends StatelessWidget {
  const MyWorkCardRouter({
    required this.vm,
    this.attentionMarked = false,
    super.key,
  });

  final MyWorkCardViewModel vm;
  final bool attentionMarked;

  @override
  Widget build(BuildContext context) {
    final currentUserId = context.read<ProfileCubit>().state.profile.id;
    return switch (vm.kind) {
      MyWorkCardKind.authoredDraft => _DraftAuthoredCard(
        vm: vm,
        currentUserId: currentUserId,
        attentionMarked: attentionMarked,
      ),
      MyWorkCardKind.authoredActive => _AuthoredActiveCard(
        vm: vm,
        currentUserId: currentUserId,
        attentionMarked: attentionMarked,
      ),
      MyWorkCardKind.helpOfferedActive => _HelpOfferedActiveCard(
        vm: vm,
        currentUserId: currentUserId,
        attentionMarked: attentionMarked,
      ),
      MyWorkCardKind.authoredFinished => _FinishedAuthoredCard(
        vm: vm,
        currentUserId: currentUserId,
        attentionMarked: attentionMarked,
      ),
      MyWorkCardKind.helpOfferedFinished => _FinishedHelpOfferedCard(
        vm: vm,
        currentUserId: currentUserId,
        attentionMarked: attentionMarked,
      ),
      MyWorkCardKind.authoredArchived => _FinishedAuthoredCard(
        vm: vm,
        currentUserId: currentUserId,
        attentionMarked: attentionMarked,
      ),
      MyWorkCardKind.helpOfferedArchived => _FinishedHelpOfferedCard(
        vm: vm,
        currentUserId: currentUserId,
        attentionMarked: attentionMarked,
      ),
      MyWorkCardKind.obligationActive => _AuthoredActiveCard(
        vm: vm,
        currentUserId: currentUserId,
        attentionMarked: attentionMarked,
      ),
      MyWorkCardKind.obligationArchived => _FinishedAuthoredCard(
        vm: vm,
        currentUserId: currentUserId,
        attentionMarked: attentionMarked,
      ),
    };
  }
}

void _openBeacon(BuildContext context, String id) {
  unawaited(context.read<MyWorkCubit>().openedBeacon(id));
  unawaited(
    context.router.push(BeaconViewRoute(id: id, entry: kBeaconEntryMyWork)),
  );
}

void _openBeaconOrSelect(
  BuildContext context,
  MyWorkCardViewModel vm, {
  String? viewTab,
  String? peopleTabAttention,
}) {
  if (viewTab != null || peopleTabAttention != null) {
    unawaited(context.read<MyWorkCubit>().openedBeacon(vm.beaconId));
    unawaited(
      context.router.push(
        BeaconViewRoute(
          id: vm.beaconId,
          viewTab: viewTab,
          peopleTabAttention: peopleTabAttention,
          entry: kBeaconEntryMyWork,
        ),
      ),
    );
    return;
  }
  _openBeacon(context, vm.beaconId);
}

Widget? _myWorkAttentionMarker({required bool attentionMarked}) => null;

/// Last-event preview — stays inside the card [InkWell] child.
///
/// The what's-new emphasis line is gone: uncleared optional events are rows in
/// the shared active-event block now, each with its own × (U15). What stays
/// here is the preview D08 allows an optional update to change.
Widget _myWorkWhatsNewSection(
  BuildContext context, {
  required MyWorkCardViewModel vm,
  required String currentUserId,
}) {
  final tt = context.tt;
  return Padding(
    padding: EdgeInsets.only(top: tt.tightGap),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Semantics(
            identifier: TestIds.myWorkWhatsNew(vm.beaconId),
            child: MyWorkLastEventBody(
              beacon: vm.beacon,
              viewModel: vm,
              currentUserId: currentUserId,
              muted: true,
            ),
          ),
        ),
        // Beside the preview, not in the header: the identity row's trailing
        // slot is a fixed-width menu box (`kBeaconCardMenuSlotWidth`) and
        // overflows the moment anything joins the menu in it.
        MyWorkCardAttentionIndicators(vm: vm),
      ],
    ),
  );
}

/// Composes shell footer: obligations first, then existing controls.
/// Returns null only when every section is absent (D-SC8).
Widget? _composeMyWorkFooter(
  BuildContext context, {
  required MyWorkCardViewModel vm,
  Widget? existingFooter,
  bool suppressReviewHelpOffersFallback = false,
  bool suppressReviewFallback = false,
}) {
  final view = myWorkCardAttentionView(
    beaconId: vm.beaconId,
    attention: context.select(
      (MyWorkCubit c) => c.state.attentionByBeacon[vm.beaconId],
    ),
    viewerArchived: vm.viewerArchived,
  );
  final obligations = view.obligations;
  final optionalEvents = view.optionalEvents;
  final showObligations = myWorkObligationBlockVisible(
    vm: vm,
    obligations: obligations,
    optionalEvents: optionalEvents,
    suppressReviewHelpOffersFallback: suppressReviewHelpOffersFallback,
    suppressReviewFallback: suppressReviewFallback,
  );
  if (!showObligations && existingFooter == null) {
    return null;
  }
  final tt = context.tt;
  return Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      if (showObligations)
        MyWorkObligationBlock(
          vm: vm,
          obligations: obligations,
          optionalEvents: optionalEvents,
          // The server's total, not the rows in hand (U14b addition 4).
          optionalTotal: view.optionalTotal,
          onClearEvent: (receiptId) => unawaited(
            context.read<MyWorkCubit>().clearOptionalEvent(
              vm.beaconId,
              receiptId,
            ),
          ),
          onOpenTimeline: () => unawaited(
            showRequestAttentionTimelineSheet(context, beaconId: vm.beaconId),
          ),
          suppressReviewHelpOffersFallback: suppressReviewHelpOffersFallback,
          suppressReviewFallback: suppressReviewFallback,
          onReviewHelpOffers: () => _openBeaconReviewHelpOffers(context, vm),
          onReviewContributions: () =>
              _openReviewContributions(context, vm.beaconId),
          onRespondHelpOffer: (offererId) => unawaited(
            showHelpOfferTileSheetFromDesk(
              context: context,
              beaconId: vm.beaconId,
              offerUserId: offererId,
              beacon: vm.beacon,
            ),
          ),
        ),
      if (showObligations && existingFooter != null) SizedBox(height: tt.rowGap),
      if (existingFooter != null) existingFooter,
    ],
  );
}

void _openBeaconReviewHelpOffers(
  BuildContext context,
  MyWorkCardViewModel vm,
) {
  _openBeaconOrSelect(
    context,
    vm,
    viewTab: kBeaconViewTabHelpOffers,
    peopleTabAttention: '1',
  );
}

void _openEditDraft(BuildContext context, String id) {
  unawaited(context.router.push(BeaconCreateRoute(draftId: id)));
}

void _openSendDraft(BuildContext context, String id) {
  unawaited(
    context.router.push(
      BeaconCreateRoute(
        draftId: id,
        initialTab: kBeaconCreateTabRecipients,
      ),
    ),
  );
}

void _openReviewContributions(BuildContext context, String id) {
  unawaited(context.router.push(ReviewContributionsRoute(id: id)));
}

({BeaconPhaseStatusPresentation? phaseStatus}) _myWorkCardHeaderStatus(
  MyWorkStatusLineData data, {
  String? roomSubtitle,
}) {
  final pres = myWorkHeaderPhaseStatus(data, roomSubtitle: roomSubtitle);
  if (pres.statusLine.trim().isEmpty) {
    return (phaseStatus: null);
  }
  return (phaseStatus: pres);
}

Widget _myWorkSharedPreviewHeader(
  BuildContext context, {
  required MyWorkCardViewModel vm,
  required String currentUserId,
  required BeaconPhaseStatusPresentation? phaseStatus,
  required Widget menu,
  String? statusSemanticsIdentifier,
}) {
  final l10n = L10n.of(context)!;
  final data = BeaconRequestPreviewData.fromBeacon(
    l10n,
    vm.beacon,
    now: DateTime.now(),
    phaseStatus: phaseStatus,
  );
  return BeaconRequestPreviewIdentity(
    data: data,
    currentUserId: currentUserId,
    trailing: menu,
    titleMaxLines: 1,
    statusSemanticsIdentifier: statusSemanticsIdentifier,
  );
}

Widget? _myWorkArchiveFooter(BuildContext context, MyWorkCardViewModel vm) {
  if (!vm.showArchiveAffordance) return null;
  final l10n = L10n.of(context)!;
  final cubit = context.read<MyWorkCubit>();
  if (vm.viewerArchived) {
    return Align(
      alignment: Alignment.centerRight,
      child: TenturaTextAction(
        label: l10n.myWorkUnarchive,
        tone: TenturaTone.neutral,
        onPressed: () => cubit.unarchiveBeacon(vm.beaconId),
      ),
    );
  }
  return Align(
    alignment: Alignment.centerRight,
    child: TenturaTextAction(
      label: l10n.myWorkArchive,
      tone: TenturaTone.neutral,
      onPressed: () => cubit.archiveBeacon(vm.beaconId),
    ),
  );
}

class _AuthoredActiveCard extends StatelessWidget {
  const _AuthoredActiveCard({
    required this.vm,
    required this.currentUserId,
    required this.attentionMarked,
  });

  final MyWorkCardViewModel vm;
  final String currentUserId;
  final bool attentionMarked;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final b = vm.beacon;

    final evaluationRepo = GetIt.I<EvaluationRepository>();
    final statusLine = myWorkStatusLine(l10n: l10n, vm: vm);
    final headerStatus = _myWorkCardHeaderStatus(
      statusLine,
      roomSubtitle: vm.roomInboxSubtitle.isEmpty ? null : vm.roomInboxSubtitle,
    );

    // The package state owns the review affordance; the phase CTA never
    // duplicates it.
    final hasReviewCta =
        myWorkReviewAffordanceKind(vm.reviewPackageState) !=
        MyWorkReviewAffordanceKind.none;
    final needsForwardCta = myWorkNeedsForwardCta(vm);
    final showCloseNowCta = vm.showCloseNowCta;
    final phaseAction = myWorkEffectivePrimaryAction(
      vm: vm,
      viewerUserId: currentUserId,
    );
    final phaseCtaLabel =
        (phaseAction == BeaconPhasePrimaryAction.forward && !b.allowsForward) ||
            phaseAction == BeaconPhasePrimaryAction.reviewContributions
        ? null
        : myWorkPhasePrimaryCtaLabel(
            l10n: l10n,
            vm: vm,
            viewerUserId: currentUserId,
          );

    final Widget? footerActions;
    if (showCloseNowCta ||
        phaseCtaLabel != null ||
        hasReviewCta ||
        needsForwardCta) {
      footerActions = Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (showCloseNowCta) ...[
            Align(
              alignment: Alignment.centerRight,
              child: TenturaCommandButton(
                key: TestIds.key(TestIds.myWorkCloseNow(b.id)),
                label: l10n.beaconCloseNowCta,
                onPressed: () async {
                  try {
                    final confirmed = await myWorkConfirmCloseNow(
                      context: context,
                      beaconId: b.id,
                      evaluationRepository: evaluationRepo,
                    );
                    if (!confirmed) return;
                    await evaluationRepo.beaconCloseNow(b.id);
                    if (context.mounted) {
                      await context.read<MyWorkCubit>().fetch(
                        showLoading: false,
                      );
                    }
                  } catch (e) {
                    if (context.mounted) {
                      showSnackBar(
                        context,
                        isError: true,
                        text: e.toString(),
                        error: e,
                      );
                    }
                  }
                },
              ),
            ),
            if (hasReviewCta || needsForwardCta || phaseCtaLabel != null)
              const SizedBox(height: kSpacingSmall),
          ],
          if (hasReviewCta) ...[
            MyWorkReviewAffordance(
              vm: vm,
              isAuthor: true,
              onOpenReview: () =>
                  _openReviewContributions(context, vm.beaconId),
            ),
            if (needsForwardCta || phaseCtaLabel != null)
              const SizedBox(height: kSpacingSmall),
          ],
          if (phaseCtaLabel != null)
            Align(
              alignment: Alignment.centerRight,
              child: TenturaCommandButton(
                label: phaseCtaLabel,
                onPressed: () => switch (phaseAction) {
                  BeaconPhasePrimaryAction.reviewOffers =>
                    _openBeaconReviewHelpOffers(context, vm),
                  BeaconPhasePrimaryAction.reviewContributions =>
                    _openReviewContributions(context, vm.beaconId),
                  BeaconPhasePrimaryAction.forward => b.allowsForward
                      ? unawaited(
                          context.router.push(
                            ForwardBeaconRoute(beaconId: b.id),
                          ),
                        )
                      : _openBeaconOrSelect(context, vm),
                  BeaconPhasePrimaryAction.resolveBlocker => _openBeaconOrSelect(
                    context,
                    vm,
                  ),
                  _ => _openBeaconOrSelect(context, vm),
                },
              ),
            )
          else if (needsForwardCta)
            SizedBox(
              width: double.infinity,
              child: TenturaCommandButton(
                label: l10n.inboxCardOpenBeacon,
                icon: const Icon(Icons.arrow_forward),
                onPressed: () => unawaited(
                  context.router.push(ForwardBeaconRoute(beaconId: b.id)),
                ),
              ),
            ),
        ],
      );
    } else {
      footerActions = null;
    }

    return BeaconCardShell(
      onTap: () => _openBeaconOrSelect(context, vm),
      marker: _myWorkAttentionMarker(attentionMarked: attentionMarked),
      footer: _composeMyWorkFooter(
        context,
        vm: vm,
        existingFooter: footerActions,
        suppressReviewHelpOffersFallback:
            phaseAction == BeaconPhasePrimaryAction.reviewOffers,
        suppressReviewFallback: hasReviewCta,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _myWorkSharedPreviewHeader(
            context,
            vm: vm,
            currentUserId: currentUserId,
            phaseStatus: headerStatus.phaseStatus,
            statusSemanticsIdentifier: TestIds.myWorkRoomStatus(b.id),
            menu: BeaconOverflowMenu(
              beacon: b,
              onCloseBeacon: myWorkCloseBeaconEnabled(vm)
                  ? () async {
                      await Future<void>.delayed(Duration.zero);
                      if (!context.mounted) return;
                      if (await BeaconCloseConfirmDialog.show(context) !=
                          true) {
                        return;
                      }
                      if (!context.mounted) return;
                      try {
                        await evaluationRepo.beaconClose(
                          beaconId: b.id,
                          expectedRequiresReviewWindow:
                              myWorkExpectedRequiresReviewWindow(vm),
                        );
                      } catch (e) {
                        if (context.mounted) {
                          showSnackBar(
                            context,
                            isError: true,
                            text: e.toString(),
                            error: e,
                          );
                        }
                      }
                    }
                  : null,
              onCancelBeacon: beaconAllowsCancel(
                b,
                serverCanCancel: vm.displayStatus?.canCancel,
              )
                  ? () async {
                      await Future<void>.delayed(Duration.zero);
                      if (!context.mounted) return;
                      try {
                        await evaluationRepo.beaconCancel(b.id);
                      } catch (e) {
                        if (context.mounted) {
                          showSnackBar(
                            context,
                            isError: true,
                            text: e.toString(),
                            error: e,
                          );
                        }
                      }
                    }
                  : null,
              onEdit: beaconAllowsEdit(b)
                  ? () => unawaited(
                      context.router.push(BeaconCreateRoute(editId: b.id)),
                    )
                  : null,
              onForward: b.allowsForward
                  ? () => unawaited(
                      context.router.push(ForwardBeaconRoute(beaconId: b.id)),
                    )
                  : null,
              onForwardsGraph: () =>
                  context.read<ScreenCubit>().showForwardsGraphFor(b.id),
              onCreateFrom: beaconAllowsLineageOverflow(b)
                  ? () async {
                      await runBeaconCreateFromAction(
                        context,
                        fork: () => forkBeaconViaRepository(b),
                      );
                    }
                  : null,
              onDelete: () => _confirmAndDeleteMyWorkBeacon(context, vm: vm),
            ),
          ),
          const SizedBox(height: 6),
          MyWorkCardMetadataRow(
            beacon: b,
            viewModel: vm,
            currentUserId: currentUserId,
            hidePeople: true,
          ),
          _myWorkWhatsNewSection(
            context,
            vm: vm,
            currentUserId: currentUserId,
          ),
        ],
      ),
    );
  }
}

class _HelpOfferedActiveCard extends StatelessWidget {
  const _HelpOfferedActiveCard({
    required this.vm,
    required this.currentUserId,
    required this.attentionMarked,
  });

  final MyWorkCardViewModel vm;
  final String currentUserId;
  final bool attentionMarked;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final b = vm.beacon;
    final statusLine = myWorkStatusLine(l10n: l10n, vm: vm);
    final headerStatus = _myWorkCardHeaderStatus(
      statusLine,
      roomSubtitle: vm.roomInboxSubtitle.isEmpty ? null : vm.roomInboxSubtitle,
    );

    final hasReviewCta =
        myWorkReviewAffordanceKind(vm.reviewPackageState) !=
        MyWorkReviewAffordanceKind.none;

    return BeaconCardShell(
      onTap: () => _openBeaconOrSelect(context, vm),
      marker: _myWorkAttentionMarker(attentionMarked: attentionMarked),
      footer: _composeMyWorkFooter(
        context,
        vm: vm,
        existingFooter: hasReviewCta
            ? MyWorkReviewAffordance(
                vm: vm,
                isAuthor: false,
                onOpenReview: () =>
                    _openReviewContributions(context, vm.beaconId),
              )
            : null,
        suppressReviewFallback: hasReviewCta,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _myWorkSharedPreviewHeader(
            context,
            vm: vm,
            currentUserId: currentUserId,
            phaseStatus: headerStatus.phaseStatus,
            statusSemanticsIdentifier: TestIds.myWorkRoomStatus(b.id),
            menu: BeaconOverflowMenu(
              beacon: b,
              onForward: b.allowsForward
                  ? () => unawaited(
                      context.router.push(ForwardBeaconRoute(beaconId: b.id)),
                    )
                  : null,
              onForwardsGraph: () =>
                  context.read<ScreenCubit>().showForwardsGraphFor(b.id),
              onCreateFrom: beaconAllowsLineageOverflow(b)
                  ? () async {
                      await runBeaconCreateFromAction(
                        context,
                        fork: () => forkBeaconViaRepository(b),
                      );
                    }
                  : null,
              onComplaint: () =>
                  context.read<ScreenCubit>().showComplaint(b.id),
            ),
          ),
          const SizedBox(height: 6),
          MyWorkCardMetadataRow(
            beacon: b,
            viewModel: vm,
            currentUserId: currentUserId,
            hidePeople: true,
          ),
          _myWorkWhatsNewSection(
            context,
            vm: vm,
            currentUserId: currentUserId,
          ),
        ],
      ),
    );
  }
}

class _DraftAuthoredCard extends StatelessWidget {
  const _DraftAuthoredCard({
    required this.vm,
    required this.currentUserId,
    required this.attentionMarked,
  });

  final MyWorkCardViewModel vm;
  final String currentUserId;
  final bool attentionMarked;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final theme = Theme.of(context);
    final b = vm.beacon;
    final statusLine = myWorkStatusLine(l10n: l10n, vm: vm);
    final headerStatus = _myWorkCardHeaderStatus(
      statusLine,
      roomSubtitle: vm.roomInboxSubtitle.isEmpty ? null : vm.roomInboxSubtitle,
    );

    return BeaconCardShell(
      muted: true,
      onTap: () => _openEditDraft(context, b.id),
      marker: _myWorkAttentionMarker(attentionMarked: attentionMarked),
      footer: _composeMyWorkFooter(
        context,
        vm: vm,
        existingFooter: Wrap(
          alignment: WrapAlignment.end,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: context.tt.rowGap,
          runSpacing: context.tt.tightGap,
          children: [
            TenturaTextAction(
              label: l10n.myWorkEditDraft,
              onPressed: () => _openEditDraft(context, b.id),
            ),
            TenturaCommandButton(
              label: l10n.myWorkSendDraft,
              icon: const Icon(Icons.send_outlined),
              onPressed: () => _openSendDraft(context, b.id),
            ),
          ],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _myWorkSharedPreviewHeader(
            context,
            vm: vm,
            currentUserId: currentUserId,
            phaseStatus: headerStatus.phaseStatus,
            statusSemanticsIdentifier: TestIds.myWorkRoomStatus(b.id),
            menu: BeaconOverflowMenu(
              beacon: b,
              editActionLabel: l10n.myWorkEditDraft,
              onEdit: () => _openEditDraft(context, b.id),
              onDelete: () => _confirmAndDeleteMyWorkBeacon(context, vm: vm),
            ),
          ),
          const SizedBox(height: 6),
          MyWorkCardMetadataRow(
            beacon: b,
            viewModel: vm,
            currentUserId: currentUserId,
            hidePeople: true,
          ),
          const SizedBox(height: kSpacingSmall),
          Text(
            l10n.myWorkDraftStatusLine(b.helpOfferCount),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          _myWorkWhatsNewSection(
            context,
            vm: vm,
            currentUserId: currentUserId,
          ),
        ],
      ),
    );
  }
}

class _FinishedAuthoredCard extends StatelessWidget {
  const _FinishedAuthoredCard({
    required this.vm,
    required this.currentUserId,
    required this.attentionMarked,
  });

  final MyWorkCardViewModel vm;
  final String currentUserId;
  final bool attentionMarked;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final b = vm.beacon;
    final evaluationRepo = GetIt.I<EvaluationRepository>();
    final statusLine = myWorkStatusLine(l10n: l10n, vm: vm);
    final headerStatus = _myWorkCardHeaderStatus(
      statusLine,
      roomSubtitle: vm.roomInboxSubtitle.isEmpty ? null : vm.roomInboxSubtitle,
    );
    return BeaconCardShell(
      muted: true,
      onTap: () => _openBeaconOrSelect(context, vm),
      marker: _myWorkAttentionMarker(attentionMarked: attentionMarked),
      footer: _composeMyWorkFooter(
        context,
        vm: vm,
        existingFooter: _myWorkArchiveFooter(context, vm),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _myWorkSharedPreviewHeader(
            context,
            vm: vm,
            currentUserId: currentUserId,
            phaseStatus: headerStatus.phaseStatus,
            statusSemanticsIdentifier: TestIds.myWorkRoomStatus(b.id),
            menu: BeaconOverflowMenu(
              beacon: b,
              onCloseBeacon: myWorkCloseBeaconEnabled(vm)
                  ? () async {
                      await Future<void>.delayed(Duration.zero);
                      if (!context.mounted) return;
                      if (await BeaconCloseConfirmDialog.show(context) !=
                          true) {
                        return;
                      }
                      if (!context.mounted) return;
                      try {
                        await evaluationRepo.beaconClose(
                          beaconId: b.id,
                          expectedRequiresReviewWindow:
                              myWorkExpectedRequiresReviewWindow(vm),
                        );
                      } catch (e) {
                        if (context.mounted) {
                          showSnackBar(
                            context,
                            isError: true,
                            text: e.toString(),
                            error: e,
                          );
                        }
                      }
                    }
                  : null,
              onCancelBeacon: beaconAllowsCancel(
                b,
                serverCanCancel: vm.displayStatus?.canCancel,
              )
                  ? () async {
                      await Future<void>.delayed(Duration.zero);
                      if (!context.mounted) return;
                      try {
                        await evaluationRepo.beaconCancel(b.id);
                      } catch (e) {
                        if (context.mounted) {
                          showSnackBar(
                            context,
                            isError: true,
                            text: e.toString(),
                            error: e,
                          );
                        }
                      }
                    }
                  : null,
              onEdit: beaconAllowsEdit(b)
                  ? () => unawaited(
                      context.router.push(BeaconCreateRoute(editId: b.id)),
                    )
                  : null,
              onForward: b.allowsForward
                  ? () => unawaited(
                      context.router.push(ForwardBeaconRoute(beaconId: b.id)),
                    )
                  : null,
              onForwardsGraph: () =>
                  context.read<ScreenCubit>().showForwardsGraphFor(b.id),
              onCreateFrom: beaconAllowsLineageOverflow(b)
                  ? () async {
                      await runBeaconCreateFromAction(
                        context,
                        fork: () => forkBeaconViaRepository(b),
                      );
                    }
                  : null,
              onDelete: () => _confirmAndDeleteMyWorkBeacon(context, vm: vm),
            ),
          ),
          const SizedBox(height: 6),
          MyWorkCardMetadataRow(
            beacon: b,
            viewModel: vm,
            currentUserId: currentUserId,
            hidePeople: true,
          ),
          _myWorkWhatsNewSection(
            context,
            vm: vm,
            currentUserId: currentUserId,
          ),
        ],
      ),
    );
  }
}

class _FinishedHelpOfferedCard extends StatelessWidget {
  const _FinishedHelpOfferedCard({
    required this.vm,
    required this.currentUserId,
    required this.attentionMarked,
  });

  final MyWorkCardViewModel vm;
  final String currentUserId;
  final bool attentionMarked;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final b = vm.beacon;
    final statusLine = myWorkStatusLine(l10n: l10n, vm: vm);
    final headerStatus = _myWorkCardHeaderStatus(
      statusLine,
      roomSubtitle: vm.roomInboxSubtitle.isEmpty ? null : vm.roomInboxSubtitle,
    );
    return BeaconCardShell(
      muted: true,
      onTap: () => _openBeaconOrSelect(context, vm),
      marker: _myWorkAttentionMarker(attentionMarked: attentionMarked),
      footer: _composeMyWorkFooter(
        context,
        vm: vm,
        existingFooter: _myWorkArchiveFooter(context, vm),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _myWorkSharedPreviewHeader(
            context,
            vm: vm,
            currentUserId: currentUserId,
            phaseStatus: headerStatus.phaseStatus,
            statusSemanticsIdentifier: TestIds.myWorkRoomStatus(b.id),
            menu: BeaconOverflowMenu(
              beacon: b,
              onForward: b.allowsForward
                  ? () => unawaited(
                      context.router.push(ForwardBeaconRoute(beaconId: b.id)),
                    )
                  : null,
              onForwardsGraph: () =>
                  context.read<ScreenCubit>().showForwardsGraphFor(b.id),
              onCreateFrom: beaconAllowsLineageOverflow(b)
                  ? () async {
                      await runBeaconCreateFromAction(
                        context,
                        fork: () => forkBeaconViaRepository(b),
                      );
                    }
                  : null,
              onComplaint: () =>
                  context.read<ScreenCubit>().showComplaint(b.id),
            ),
          ),
          const SizedBox(height: 6),
          MyWorkCardMetadataRow(
            beacon: b,
            viewModel: vm,
            currentUserId: currentUserId,
            hidePeople: true,
          ),
          _myWorkWhatsNewSection(
            context,
            vm: vm,
            currentUserId: currentUserId,
          ),
        ],
      ),
    );
  }
}
