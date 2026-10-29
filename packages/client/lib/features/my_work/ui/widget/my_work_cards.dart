import 'dart:async';
import 'package:tentura_root/domain/entity/beacon_status.dart';

import 'package:flutter/material.dart';

import 'package:tentura/app/router/root_router.dart';
import 'package:tentura/consts.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/features/updates/updates_receipt_display_copy.dart';
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
import 'package:tentura/domain/attention/entity/attention_receipt.dart';
import 'package:tentura/domain/attention/entity/my_work_beacon_attention.dart';
import 'package:tentura/features/my_work/domain/my_work_offer_accepted.dart';
import 'package:tentura/ui/widget/offer_accepted_event_subcard.dart';
import 'package:tentura/domain/entity/beacon_activity_event_consts.dart';
import 'package:tentura/domain/entity/beacon_coordination_phase.dart';
import 'package:tentura/features/beacon/ui/dialog/beacon_close_confirm_dialog.dart';
import 'package:tentura/features/beacon/ui/util/beacon_lifecycle_ui.dart';
import 'package:tentura/features/beacon_view/ui/sheet/help_offer_tile_sheet.dart';
import 'package:tentura/features/beacon_view/ui/widget/beacon_hud_author_confirm_sheets.dart';
import 'package:tentura/features/my_work/ui/bloc/my_work_cubit.dart';
import 'package:tentura/features/my_work/ui/widget/my_work_obligation_block.dart';
import 'package:tentura/features/my_work/ui/widget/my_work_plan_step_rows.dart';
import 'package:tentura/features/beacon_plan/ui/util/plan_presenter.dart'
    show planErrorText;
import 'package:tentura/features/my_work/domain/derive_my_work_card_attention.dart';
import 'package:tentura/features/my_work/ui/widget/my_work_card_attention_indicators.dart';
import 'package:tentura/features/my_work/ui/widget/my_work_last_event_row.dart';
import 'package:tentura/features/my_work/ui/widget/my_work_latest_message_line.dart';
import 'package:tentura/features/beacon/ui/dialog/beacon_delete_dialog.dart';
import 'package:tentura/features/beacon/ui/util/beacon_delete_ui.dart';
import 'package:tentura/features/beacon/ui/util/beacon_lineage_overflow_actions.dart';
import 'package:tentura/features/beacon/ui/widget/beacon_overflow_menu.dart';
import 'package:tentura/features/beacon/data/repository/beacon_repository.dart';
import 'package:tentura/features/closure/data/repository/closure_repository.dart';
import 'package:tentura/features/my_work/domain/entity/my_work_card_view_model.dart';
import 'package:tentura/features/profile/ui/bloc/profile_cubit.dart';

bool myWorkCloseBeaconEnabled(MyWorkCardViewModel vm) =>
    vm.beacon.status == BeaconStatus.open && vm.displayStatus != null;

/// Footer Forward CTA on authored and helper My Work cards (gated by
/// `Beacon.viewerCanForward`).
bool myWorkNeedsForwardCta(MyWorkCardViewModel vm) =>
    vm.beacon.viewerCanForward;

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
    if (!context.mounted) return;
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
  // #656: unread Questions updates are answered in Questions; they stay on
  // the card until Questions is opened.
  final latest = context
      .read<MyWorkCubit>()
      .state
      .attentionByBeacon[vm.beaconId]
      ?.latestUnseen;
  if (latest != null && isQuestionsAttentionReceipt(latest)) {
    unawaited(context.router.push(BeaconLobbyRoute(beaconId: vm.beaconId)));
    return;
  }
  _openBeacon(context, vm.beaconId);
}

Widget? _myWorkAttentionMarker({required bool attentionMarked}) => null;

/// #487 — a child Request says which Request it is part of, so it does not
/// read as an unrelated sibling of its parent on the list. Nothing for a
/// top-level Request or a parent the viewer cannot read. Tapping the line
/// opens the parent Request (not the child the rest of the card opens).
Widget _myWorkPartOfParentLine(BuildContext context, MyWorkCardViewModel vm) {
  final title = vm.parentTitle.trim();
  if (title.isEmpty) return const SizedBox.shrink();
  final tt = context.tt;
  final theme = Theme.of(context);
  final parentId = vm.parentBeaconId;
  final text = Text(
    L10n.of(context)!.myWorkPartOfParent(title),
    maxLines: 1,
    overflow: TextOverflow.ellipsis,
    style: theme.textTheme.bodySmall!.copyWith(color: tt.textMuted),
  );
  return Padding(
    // On the text keyline with the title and HUD rows. The link's own
    // 48 dp band supplies the gap above it.
    padding: EdgeInsetsDirectional.only(
      start: tt.avatarSize + tt.avatarTextGap,
      top: parentId.isEmpty ? tt.tightGap : 0,
    ),
    child: parentId.isEmpty
        ? text
        : Align(
            alignment: AlignmentDirectional.centerStart,
            child: Semantics(
              link: true,
              child: InkWell(
                key: ValueKey('myWorkPartOfParent:$parentId'),
                onTap: () => _openBeacon(context, parentId),
                // A full-height target (review r1 #6), so a slightly high or
                // low tap opens the parent rather than the card's child.
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    minHeight: kMinInteractiveDimension,
                  ),
                  child: Align(
                    alignment: AlignmentDirectional.centerStart,
                    widthFactor: 1,
                    child: text,
                  ),
                ),
              ),
            ),
          ),
  );
}

/// Live obligations render as rows with their own CTA; a YOU line saying
/// «ответьте на предложения» above them would be the same thing twice.
bool _myWorkHasObligationRows(BuildContext context, MyWorkCardViewModel vm) =>
    myWorkCardAttentionView(
      beaconId: vm.beaconId,
      attention: context.select<MyWorkCubit, MyWorkBeaconAttention?>(
        (c) => c.state.attentionByBeacon[vm.beaconId],
      ),
      viewerArchived: vm.viewerArchived,
    ).obligations.isNotEmpty;

/// Whether the card carries a last-event line at all.
///
/// Not for a lifecycle change — «Срок обзора истёк» under «Закрыт · 9 сент»
/// says the status a second time — and not the «обновлено N назад» fallback
/// when there is no event: the header's freshness slot («неакт. 13 д») is
/// that same fact.
bool myWorkWhatsNewLineVisible(MyWorkCardViewModel vm) {
  final last = vm.lastActivityEvent;
  return last != null &&
      last.event.type != BeaconActivityEventTypeBits.beaconLifecycleChanged;
}

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
  final row = Padding(
    padding: EdgeInsets.only(top: tt.tightGap),
    child: Row(
      children: [
        Expanded(
          child: myWorkWhatsNewLineVisible(vm)
              ? Semantics(
                  identifier: TestIds.myWorkWhatsNew(vm.beaconId),
                  child: MyWorkLastEventBody(
                    beacon: vm.beacon,
                    viewModel: vm,
                    currentUserId: currentUserId,
                    muted: true,
                    // On the text keyline with the title and HUD rows.
                    alignToCardKeyline: true,
                  ),
                )
              : const SizedBox.shrink(),
        ),
        // Beside the preview, not in the header: the identity row's trailing
        // slot is a fixed-width menu box (`kBeaconCardMenuSlotWidth`) and
        // overflows the moment anything joins the menu in it.
        MyWorkCardAttentionIndicators(vm: vm),
      ],
    ),
  );
  if (!vm.hasRoomLatestMessage) return row;
  // U087 — the latest message and the unread count, above the event line.
  return Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Semantics(
        identifier: TestIds.myWorkLatestMessage(vm.beaconId),
        child: MyWorkLatestMessageLine(vm: vm, currentUserId: currentUserId),
      ),
      row,
    ],
  );
}

/// Composes shell footer: obligations first, then existing controls.
/// Returns null only when every section is absent (D-SC8).
Widget? _composeMyWorkFooter(
  BuildContext context, {
  required MyWorkCardViewModel vm,
  Widget? existingFooter,
  bool suppressReviewHelpOffersFallback = false,
  String? currentUserId,
}) {
  final now = DateTime.now();
  // B077: the helper's «your offer was accepted» event leads the footer as
  // its own sub-card until dismissed; the matching receipt is not repeated in
  // the generic rows under it.
  final offerAcceptedAt = currentUserId == null
      ? null
      : myWorkOfferAcceptedAt(vm);
  final view = myWorkCardAttentionView(
    beaconId: vm.beaconId,
    attention: context.select<MyWorkCubit, MyWorkBeaconAttention?>(
      (c) => c.state.attentionByBeacon[vm.beaconId],
    ),
    viewerArchived: vm.viewerArchived,
    planSlice: vm.planSlice,
    now: now,
  );
  final planRows = view.hasPlanRows ? _myWorkPlanRows(context, vm, now) : null;
  final obligations = view.obligations;
  final acceptedReceipts = offerAcceptedAt == null
      ? const <AttentionReceipt>[]
      : [
          for (final r in view.optionalEvents)
            if (r.presentationKey == OfferAcceptedEventSubcard.presentationKey)
              r,
        ];
  final optionalEvents = [
    for (final r in view.optionalEvents)
      if (!acceptedReceipts.contains(r)) r,
  ];
  final optionalTotal = view.optionalTotal - acceptedReceipts.length;
  final acceptedEvent = offerAcceptedAt == null
      ? null
      : OfferAcceptedEventSubcard(
          key: ValueKey('offer-accepted-${vm.beaconId}'),
          beaconId: vm.beaconId,
          viewerId: currentUserId!,
          author: vm.beacon.author,
          // #507: a steward's accept names the steward.
          acceptorId: vm.coordinationAuthor?.id,
          acceptor: vm.coordinationAuthor,
          acceptedAt: offerAcceptedAt,
          requestTitle: vm.beacon.title,
          // One gesture: the receipt behind it is cleared too, so the
          // Updates feed and the card's count agree with what was dismissed.
          onDismissed: () {
            for (final r in acceptedReceipts) {
              unawaited(
                context.read<MyWorkCubit>().clearOptionalEvent(
                  vm.beaconId,
                  r.id,
                ),
              );
            }
          },
        );
  final showObligations = myWorkObligationBlockVisible(
    vm: vm,
    obligations: obligations,
    optionalEvents: optionalEvents,
    suppressReviewHelpOffersFallback: suppressReviewHelpOffersFallback,
    hasPlanRows: planRows != null,
  );
  if (!showObligations && existingFooter == null && acceptedEvent == null) {
    return null;
  }
  final tt = context.tt;
  return Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      ?acceptedEvent,
      if (showObligations)
        MyWorkObligationBlock(
          vm: vm,
          obligations: obligations,
          optionalEvents: optionalEvents,
          planRows: planRows,
          // The server's total, not the rows in hand (U14b addition 4).
          optionalTotal: optionalTotal,
          onClearEvent: (receiptId) => unawaited(
            context.read<MyWorkCubit>().clearOptionalEvent(
              vm.beaconId,
              receiptId,
            ),
          ),
          onOpenTimeline: () => unawaited(
            showRequestAttentionTimelineSheet(context, beaconId: vm.beaconId),
          ),
          // #656: a Questions message opens Questions, not the Chat.
          onOpenQuestions: () => unawaited(
            context.router.push(BeaconLobbyRoute(beaconId: vm.beaconId)),
          ),
          suppressReviewHelpOffersFallback: suppressReviewHelpOffersFallback,
          onReviewHelpOffers: () => _openBeaconReviewHelpOffers(context, vm),
          onRespondHelpOffer: (offererId) => unawaited(
            showHelpOfferTileSheetFromDesk(
              context: context,
              beaconId: vm.beaconId,
              offerUserId: offererId,
              beacon: vm.beacon,
            ),
          ),
        ),
      if (showObligations && existingFooter != null)
        SizedBox(height: tt.rowGap),
      ?existingFooter,
    ],
  );
}

/// The Request plan rows of [vm] (#220 §5.8), for a card whose attention
/// view has them (`MyWorkCardAttentionView.hasPlanRows`).
MyWorkPlanStepRows _myWorkPlanRows(
  BuildContext context,
  MyWorkCardViewModel vm,
  DateTime now,
) {
  final slice = vm.planSlice!;
  final l10n = L10n.of(context)!;
  final people = {
    for (final p in [
      vm.beacon.author,
      ...vm.beacon.admittedHelperUsers,
      ...vm.beacon.helpOfferUsers,
    ])
      p.id: p,
  };
  final cubit = context.read<MyWorkCubit>();
  Future<void> run(Future<void> Function() action) async {
    try {
      await action();
    } catch (e) {
      if (context.mounted) {
        showSnackBar(context, isError: true, text: planErrorText(e, l10n));
      }
    }
  }

  return MyWorkPlanStepRows(
    slice: slice,
    now: now,
    viewerId: context.read<ProfileCubit>().state.profile.id,
    nameOf: (id) {
      final name = people[id]?.shownName.trim() ?? '';
      return name.isEmpty ? l10n.myWorkPlanSomeone : name;
    },
    onDone: (stepId) =>
        unawaited(run(() => cubit.planStepDone(vm.beaconId, stepId))),
    onAck: (uptoSeq) =>
        unawaited(run(() => cubit.planAck(vm.beaconId, uptoSeq))),
    onOpenStep: (_) =>
        _openBeaconOrSelect(context, vm, viewTab: kBeaconViewTabPlan),
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
    // Same tile as the event rows' avatars, so the whole card hangs off one
    // keyline.
    identitySize: context.tt.avatarSize,
    trailing: menu,
    // Two lines: at one, "Teen Garden Food Drive Fundra…" ×3 hid the part
    // that told the Requests apart.
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
        onPressed: () => cubit.unarchiveBeacon(vm.beaconId),
      ),
    );
  }
  return Align(
    alignment: Alignment.centerRight,
    child: TenturaTextAction(
      label: l10n.myWorkArchive,
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

    final closureRepo = GetIt.I<ClosureRepository>();
    final statusLine = myWorkStatusLine(l10n: l10n, vm: vm);
    final headerStatus = _myWorkCardHeaderStatus(
      statusLine,
      roomSubtitle: vm.roomInboxSubtitle.isEmpty ? null : vm.roomInboxSubtitle,
    );

    final needsForwardCta = myWorkNeedsForwardCta(vm);
    final showCloseNowCta = vm.showCloseNowCta;
    final phaseAction = myWorkEffectivePrimaryAction(
      vm: vm,
      viewerUserId: currentUserId,
    );
    final phaseCtaLabel =
        phaseAction == BeaconPhasePrimaryAction.forward && !b.viewerCanForward
        ? null
        : myWorkPhasePrimaryCtaLabel(
            l10n: l10n,
            vm: vm,
            viewerUserId: currentUserId,
          );

    final Widget? footerActions;
    if (showCloseNowCta || phaseCtaLabel != null || needsForwardCta) {
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
                    final confirmed = await showBeaconCloseNowConfirmSheet(
                      context: context,
                    );
                    if (!confirmed) return;
                    await closureRepo.beaconCloseNow(b.id);
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
                  BeaconPhasePrimaryAction.forward =>
                    b.viewerCanForward
                        ? unawaited(
                            context.router.push(
                              ForwardBeaconRoute(beaconId: b.id),
                            ),
                          )
                        : _openBeaconOrSelect(context, vm),
                  BeaconPhasePrimaryAction.resolveBlocker =>
                    _openBeaconOrSelect(
                      context,
                      vm,
                    ),
                  _ => _openBeaconOrSelect(context, vm),
                },
              ),
            )
          else if (needsForwardCta)
            // Secondary to whatever the card is asking (answering an offer):
            // a quiet action at the end, not a full-width command.
            Align(
              alignment: Alignment.centerRight,
              child: TenturaTextAction(
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
      bodyMinHeight: 0,
      onTap: () => _openBeaconOrSelect(context, vm),
      marker: _myWorkAttentionMarker(attentionMarked: attentionMarked),
      footer: _composeMyWorkFooter(
        context,
        vm: vm,
        existingFooter: footerActions,
        suppressReviewHelpOffersFallback:
            phaseAction == BeaconPhasePrimaryAction.reviewOffers,
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
                        await closureRepo.beaconClose(beaconId: b.id);
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
              onCancelBeacon:
                  beaconAllowsCancel(
                    b,
                    serverCanCancel: vm.displayStatus?.canCancel,
                  )
                  ? () async {
                      await Future<void>.delayed(Duration.zero);
                      if (!context.mounted) return;
                      try {
                        await closureRepo.beaconCancel(b.id);
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
              onForward: b.viewerCanForward
                  ? () => unawaited(
                      context.router.push(ForwardBeaconRoute(beaconId: b.id)),
                    )
                  : null,
              onForwardsGraph: () =>
                  context.read<ScreenCubit>().showForwardsGraphFor(
                    b.id,
                    kind: b.kind,
                  ),
              onCreateFrom: beaconAllowsLineageOverflow(b)
                  ? () async {
                      await runBeaconCreateFromAction(
                        context,
                        sourceBeaconId: b.id,
                      );
                    }
                  : null,
              onDelete: () => _confirmAndDeleteMyWorkBeacon(context, vm: vm),
            ),
          ),
          _myWorkPartOfParentLine(context, vm),
          const SizedBox(height: 6),
          MyWorkCardMetadataRow(
            beacon: b,
            viewModel: vm,
            currentUserId: currentUserId,
            hidePeople: true,
            hideYou: _myWorkHasObligationRows(context, vm),
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

    // #597: the same quiet Forward as on the author's card, so a helper can
    // pass the Request on without opening the overflow menu.
    final archiveFooter = _myWorkArchiveFooter(context, vm);
    final forwardCta = myWorkNeedsForwardCta(vm)
        ? Align(
            alignment: Alignment.centerRight,
            child: TenturaTextAction(
              label: l10n.inboxCardOpenBeacon,
              icon: const Icon(Icons.arrow_forward),
              onPressed: () => unawaited(
                context.router.push(ForwardBeaconRoute(beaconId: b.id)),
              ),
            ),
          )
        : null;
    final footerActions = forwardCta != null && archiveFooter != null
        ? Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [forwardCta, archiveFooter],
          )
        : forwardCta ?? archiveFooter;

    return BeaconCardShell(
      bodyMinHeight: 0,
      onTap: () => _openBeaconOrSelect(context, vm),
      marker: _myWorkAttentionMarker(attentionMarked: attentionMarked),
      footer: _composeMyWorkFooter(
        context,
        vm: vm,
        existingFooter: footerActions,
        currentUserId: currentUserId,
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
              onForward: b.viewerCanForward
                  ? () => unawaited(
                      context.router.push(ForwardBeaconRoute(beaconId: b.id)),
                    )
                  : null,
              onForwardsGraph: () =>
                  context.read<ScreenCubit>().showForwardsGraphFor(
                    b.id,
                    kind: b.kind,
                  ),
              onCreateFrom: beaconAllowsLineageOverflow(b)
                  ? () async {
                      await runBeaconCreateFromAction(
                        context,
                        sourceBeaconId: b.id,
                      );
                    }
                  : null,
              onComplaint: () =>
                  context.read<ScreenCubit>().showComplaint(b.id),
            ),
          ),
          _myWorkPartOfParentLine(context, vm),
          const SizedBox(height: 6),
          MyWorkCardMetadataRow(
            beacon: b,
            viewModel: vm,
            currentUserId: currentUserId,
            hidePeople: true,
            hideYou: _myWorkHasObligationRows(context, vm),
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
    final b = vm.beacon;
    final statusLine = myWorkStatusLine(l10n: l10n, vm: vm);
    final headerStatus = _myWorkCardHeaderStatus(
      statusLine,
      roomSubtitle: vm.roomInboxSubtitle.isEmpty ? null : vm.roomInboxSubtitle,
    );

    return BeaconCardShell(
      bodyMinHeight: 0,
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
          _myWorkPartOfParentLine(context, vm),
          const SizedBox(height: 6),
          MyWorkCardMetadataRow(
            beacon: b,
            viewModel: vm,
            currentUserId: currentUserId,
            hidePeople: true,
            hideYou: _myWorkHasObligationRows(context, vm),
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
    final closureRepo = GetIt.I<ClosureRepository>();
    final statusLine = myWorkStatusLine(l10n: l10n, vm: vm);
    final headerStatus = _myWorkCardHeaderStatus(
      statusLine,
      roomSubtitle: vm.roomInboxSubtitle.isEmpty ? null : vm.roomInboxSubtitle,
    );
    return BeaconCardShell(
      bodyMinHeight: 0,
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
                        await closureRepo.beaconClose(beaconId: b.id);
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
              onCancelBeacon:
                  beaconAllowsCancel(
                    b,
                    serverCanCancel: vm.displayStatus?.canCancel,
                  )
                  ? () async {
                      await Future<void>.delayed(Duration.zero);
                      if (!context.mounted) return;
                      try {
                        await closureRepo.beaconCancel(b.id);
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
              onForward: b.viewerCanForward
                  ? () => unawaited(
                      context.router.push(ForwardBeaconRoute(beaconId: b.id)),
                    )
                  : null,
              onForwardsGraph: () =>
                  context.read<ScreenCubit>().showForwardsGraphFor(
                    b.id,
                    kind: b.kind,
                  ),
              onCreateFrom: beaconAllowsLineageOverflow(b)
                  ? () async {
                      await runBeaconCreateFromAction(
                        context,
                        sourceBeaconId: b.id,
                      );
                    }
                  : null,
              onDelete: () => _confirmAndDeleteMyWorkBeacon(context, vm: vm),
            ),
          ),
          _myWorkPartOfParentLine(context, vm),
          const SizedBox(height: 6),
          MyWorkCardMetadataRow(
            beacon: b,
            viewModel: vm,
            currentUserId: currentUserId,
            hidePeople: true,
            hideYou: _myWorkHasObligationRows(context, vm),
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
      bodyMinHeight: 0,
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
              onForward: b.viewerCanForward
                  ? () => unawaited(
                      context.router.push(ForwardBeaconRoute(beaconId: b.id)),
                    )
                  : null,
              onForwardsGraph: () =>
                  context.read<ScreenCubit>().showForwardsGraphFor(
                    b.id,
                    kind: b.kind,
                  ),
              onCreateFrom: beaconAllowsLineageOverflow(b)
                  ? () async {
                      await runBeaconCreateFromAction(
                        context,
                        sourceBeaconId: b.id,
                      );
                    }
                  : null,
              onComplaint: () =>
                  context.read<ScreenCubit>().showComplaint(b.id),
            ),
          ),
          _myWorkPartOfParentLine(context, vm),
          const SizedBox(height: 6),
          MyWorkCardMetadataRow(
            beacon: b,
            viewModel: vm,
            currentUserId: currentUserId,
            hidePeople: true,
            hideYou: _myWorkHasObligationRows(context, vm),
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
