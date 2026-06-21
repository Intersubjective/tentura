import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';

import 'package:tentura/consts.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/beacon_lifecycle.dart';
import 'package:tentura/ui/bloc/screen_cubit.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/utils/ui_utils.dart';
import 'package:tentura/features/my_work/ui/widget/my_work_card_metadata_row.dart';
import 'package:tentura/ui/widget/beacon_card_primitives.dart';
import 'package:tentura/features/my_work/ui/widget/my_work_status_line.dart';
import 'package:tentura/features/beacon/ui/dialog/beacon_close_confirm_dialog.dart';
import 'package:tentura/features/beacon/ui/util/beacon_lifecycle_ui.dart';
import 'package:tentura/features/my_work/ui/bloc/my_work_cubit.dart';
import 'package:tentura/features/beacon/ui/dialog/beacon_delete_dialog.dart';
import 'package:tentura/features/beacon/ui/util/beacon_lineage_overflow_actions.dart';
import 'package:tentura/features/beacon/ui/widget/beacon_overflow_menu.dart';
import 'package:tentura/ui/dialog/share_code_dialog.dart';
import 'package:tentura/features/beacon/data/repository/beacon_repository.dart';
import 'package:tentura/features/evaluation/data/repository/evaluation_repository.dart';
import 'package:tentura/features/my_work/domain/entity/my_work_card_view_model.dart';
import 'package:tentura/features/profile/ui/bloc/profile_cubit.dart';

class MyWorkCardRouter extends StatelessWidget {
  const MyWorkCardRouter({required this.vm, super.key});

  final MyWorkCardViewModel vm;

  @override
  Widget build(BuildContext context) {
    final currentUserId = context.read<ProfileCubit>().state.profile.id;
    return switch (vm.kind) {
      MyWorkCardKind.authoredDraft => _DraftAuthoredCard(
        vm: vm,
        currentUserId: currentUserId,
      ),
      MyWorkCardKind.authoredActive => _AuthoredActiveCard(
        vm: vm,
        currentUserId: currentUserId,
      ),
      MyWorkCardKind.helpOfferedActive => _HelpOfferedActiveCard(
        vm: vm,
        currentUserId: currentUserId,
      ),
      MyWorkCardKind.authoredFinished => _FinishedAuthoredCard(
        vm: vm,
        currentUserId: currentUserId,
      ),
      MyWorkCardKind.helpOfferedFinished => _FinishedHelpOfferedCard(
        vm: vm,
        currentUserId: currentUserId,
      ),
      MyWorkCardKind.authoredArchived => _FinishedAuthoredCard(
        vm: vm,
        currentUserId: currentUserId,
      ),
      MyWorkCardKind.helpOfferedArchived => _FinishedHelpOfferedCard(
        vm: vm,
        currentUserId: currentUserId,
      ),
    };
  }
}

void _openBeacon(BuildContext context, String id) {
  unawaited(
    context.router.pushPath(
      '$kPathBeaconView/$id?$kQueryBeaconEntry=$kBeaconEntryMyWork',
    ),
  );
}

void _openBeaconReviewHelpOffers(BuildContext context, String id) {
  unawaited(
    context.router.pushPath(
      '$kPathBeaconView/$id?$kQueryBeaconViewTab=help_offers&$kQueryBeaconPeopleTabAttention=1&$kQueryBeaconEntry=$kBeaconEntryMyWork',
    ),
  );
}

void _openEditDraft(BuildContext context, String id) {
  unawaited(
    context.router.pushPath('$kPathBeaconNew?$kQueryBeaconDraftId=$id'),
  );
}

void _openReviewContributions(BuildContext context, String id) {
  unawaited(context.router.pushPath('$kPathReviewContributions/$id'));
}

({String? statusLine, TenturaTone statusTone}) _myWorkCardHeaderStatus(
  MyWorkStatusLineData data, {
  String? roomSubtitle,
}) {
  final line = myWorkStatusDisplayLine(data, roomSubtitle: roomSubtitle);
  if (line.isEmpty) {
    return (statusLine: null, statusTone: TenturaTone.neutral);
  }
  return (
    statusLine: line,
    statusTone: myWorkStatusTone(data),
  );
}

Widget? _myWorkArchiveFooter(BuildContext context, MyWorkCardViewModel vm) {
  if (!vm.showArchiveAffordance) return null;
  final l10n = L10n.of(context)!;
  final cubit = context.read<MyWorkCubit>();
  if (vm.isArchived) {
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
  });

  final MyWorkCardViewModel vm;
  final String currentUserId;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final b = vm.beacon;

    final repo = GetIt.I<BeaconRepository>();
    final evaluationRepo = GetIt.I<EvaluationRepository>();
    final statusLine = myWorkStatusLine(l10n: l10n, vm: vm);
    final headerStatus = _myWorkCardHeaderStatus(
      statusLine,
      roomSubtitle:
          vm.roomInboxSubtitle.isEmpty ? null : vm.roomInboxSubtitle,
    );

    final hasReviewCta = vm.showReviewHelpOffersCta;
    final needsForwardCta = !vm.authorHasForwardedOnce;
    final footerActions = (hasReviewCta || needsForwardCta)
        ? Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (hasReviewCta)
                Align(
                  alignment: Alignment.centerRight,
                  child: TenturaCommandButton(
                    label: l10n.myWorkReviewHelpOffersCta,
                    onPressed: () =>
                        _openBeaconReviewHelpOffers(context, b.id),
                  ),
                ),
              if (hasReviewCta && needsForwardCta)
                const SizedBox(height: kSpacingSmall),
              if (needsForwardCta)
                SizedBox(
                  width: double.infinity,
                  child: TenturaCommandButton(
                    label: l10n.inboxCardOpenBeacon,
                    icon: const Icon(Icons.arrow_forward),
                    onPressed: () => unawaited(
                      context.router.pushPath('$kPathForwardBeacon/${b.id}'),
                    ),
                  ),
                ),
            ],
          )
        : null;

    return BeaconCardShell(
      onTap: () => _openBeacon(context, b.id),
      footer: footerActions,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          BeaconCardHeaderRow(
            beacon: b,
            titleMaxLines: 1,
            statusLine: headerStatus.statusLine,
            statusTone: headerStatus.statusTone,
            menu: BeaconOverflowMenu(
              beacon: b,
              onShare: () => unawaited(
                ShareCodeDialog.show(
                  context,
                  link: Uri.parse(kServerName).replace(
                    queryParameters: {'id': b.id},
                    path: kPathAppLinkView,
                  ),
                  header: b.id,
                ),
              ),
              onCloseBeacon: b.lifecycle == BeaconLifecycle.open
                  ? () async {
                      await Future<void>.delayed(Duration.zero);
                      if (!context.mounted) return;
                      if (await BeaconCloseConfirmDialog.show(context) != true) {
                        return;
                      }
                      if (!context.mounted) return;
                      try {
                        await evaluationRepo.beaconClose(
                          beaconId: b.id,
                          expectedRequiresReviewWindow: b.helpOfferCount > 0,
                        );
                      } catch (e) {
                        if (context.mounted) {
                          showSnackBar(context, isError: true, text: e.toString());
                        }
                      }
                    }
                  : null,
              onCancelBeacon: beaconAllowsCancel(b)
                  ? () async {
                      await Future<void>.delayed(Duration.zero);
                      if (!context.mounted) return;
                      try {
                        await evaluationRepo.beaconCancel(b.id);
                      } catch (e) {
                        if (context.mounted) {
                          showSnackBar(context, isError: true, text: e.toString());
                        }
                      }
                    }
                  : null,
              onEdit: b.lifecycle == BeaconLifecycle.open
                  ? () => unawaited(
                      context.router.pushPath(
                        '$kPathBeaconNew?$kQueryBeaconEditId=${b.id}',
                      ),
                    )
                  : null,
              onForward: b.allowsForward
                  ? () => unawaited(
                      context.router.pushPath('$kPathForwardBeacon/${b.id}'),
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
              onLineageSuggestions: beaconAllowsLineageOverflow(b)
                  ? () => runBeaconLineageSuggestionsPreview(
                      context,
                      beaconId: b.id,
                    )
                  : null,
              onDelete: () async {
                await Future<void>.delayed(Duration.zero);
                if (!context.mounted) return;
                if (await BeaconDeleteDialog.show(
                      context,
                      lifecycle: b.lifecycle,
                      hasEverHadCommitter: beaconDeleteBlockedByCommitters(b),
                    ) ??
                    false) {
                  try {
                    await repo.delete(b.id);
                  } catch (e) {
                    if (context.mounted) {
                      showSnackBar(context, isError: true, text: e.toString());
                    }
                  }
                }
              },
            ),
          ),
          const SizedBox(height: 6),
          MyWorkCardMetadataRow(
            beacon: b,
            viewModel: vm,
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
  });

  final MyWorkCardViewModel vm;
  final String currentUserId;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final b = vm.beacon;
    final statusLine = myWorkStatusLine(l10n: l10n, vm: vm);
    final headerStatus = _myWorkCardHeaderStatus(
      statusLine,
      roomSubtitle:
          vm.roomInboxSubtitle.isEmpty ? null : vm.roomInboxSubtitle,
    );

    return BeaconCardShell(
      onTap: () => _openBeacon(context, b.id),
      footer: vm.showReviewCta
          ? Align(
              alignment: Alignment.centerRight,
              child: TenturaCommandButton(
                label: l10n.myWorkReviewCta,
                onPressed: () => _openReviewContributions(context, b.id),
              ),
            )
          : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          BeaconCardHeaderRow(
            beacon: b,
            titleMaxLines: 1,
            statusLine: headerStatus.statusLine,
            statusTone: headerStatus.statusTone,
            menu: BeaconOverflowMenu(
              beacon: b,
              onForward: b.allowsForward
                  ? () => unawaited(
                      context.router.pushPath('$kPathForwardBeacon/${b.id}'),
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
              onLineageSuggestions: beaconAllowsLineageOverflow(b)
                  ? () => runBeaconLineageSuggestionsPreview(
                      context,
                      beaconId: b.id,
                    )
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
  });

  final MyWorkCardViewModel vm;
  final String currentUserId;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final theme = Theme.of(context);
    final b = vm.beacon;
    final statusLine = myWorkStatusLine(l10n: l10n, vm: vm);
    final headerStatus = _myWorkCardHeaderStatus(
      statusLine,
      roomSubtitle:
          vm.roomInboxSubtitle.isEmpty ? null : vm.roomInboxSubtitle,
    );

    return BeaconCardShell(
      muted: true,
      onTap: () => _openEditDraft(context, b.id),
      footer: Align(
        alignment: Alignment.centerRight,
        child: TenturaTextAction(
          label: l10n.myWorkEditDraft,
          onPressed: () => _openEditDraft(context, b.id),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          BeaconCardHeaderRow(
            beacon: b,
            titleMaxLines: 1,
            statusLine: headerStatus.statusLine,
            statusTone: headerStatus.statusTone,
            menu: BeaconOverflowMenu(
              beacon: b,
              editActionLabel: l10n.myWorkEditDraft,
              onEdit: () => _openEditDraft(context, b.id),
              onDelete: () async {
                await Future<void>.delayed(Duration.zero);
                if (!context.mounted) return;
                final repo = GetIt.I<BeaconRepository>();
                if (await BeaconDeleteDialog.show(
                      context,
                      lifecycle: b.lifecycle,
                      hasEverHadCommitter: beaconDeleteBlockedByCommitters(b),
                    ) ??
                    false) {
                  try {
                    await repo.delete(b.id);
                  } catch (e) {
                    if (context.mounted) {
                      showSnackBar(context, isError: true, text: e.toString());
                    }
                  }
                }
              },
            ),
          ),
          const SizedBox(height: 6),
          MyWorkCardMetadataRow(
            beacon: b,
            viewModel: vm,
            currentUserId: currentUserId,
          ),
          const SizedBox(height: kSpacingSmall),
          Text(
            l10n.myWorkDraftStatusLine(b.helpOfferCount),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
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
  });

  final MyWorkCardViewModel vm;
  final String currentUserId;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final b = vm.beacon;
    final repo = GetIt.I<BeaconRepository>();
    final evaluationRepo = GetIt.I<EvaluationRepository>();
    final statusLine = myWorkStatusLine(l10n: l10n, vm: vm);
    final headerStatus = _myWorkCardHeaderStatus(
      statusLine,
      roomSubtitle:
          vm.roomInboxSubtitle.isEmpty ? null : vm.roomInboxSubtitle,
    );
    return BeaconCardShell(
      muted: true,
      onTap: () => _openBeacon(context, b.id),
      footer: _myWorkArchiveFooter(context, vm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          BeaconCardHeaderRow(
            beacon: b,
            titleMaxLines: 1,
            statusLine: headerStatus.statusLine,
            statusTone: headerStatus.statusTone,
            menu: BeaconOverflowMenu(
              beacon: b,
              onShare: () => unawaited(
                ShareCodeDialog.show(
                  context,
                  link: Uri.parse(kServerName).replace(
                    queryParameters: {'id': b.id},
                    path: kPathAppLinkView,
                  ),
                  header: b.id,
                ),
              ),
              onCloseBeacon: b.lifecycle == BeaconLifecycle.open
                  ? () async {
                      await Future<void>.delayed(Duration.zero);
                      if (!context.mounted) return;
                      if (await BeaconCloseConfirmDialog.show(context) != true) {
                        return;
                      }
                      if (!context.mounted) return;
                      try {
                        await evaluationRepo.beaconClose(
                          beaconId: b.id,
                          expectedRequiresReviewWindow: b.helpOfferCount > 0,
                        );
                      } catch (e) {
                        if (context.mounted) {
                          showSnackBar(context, isError: true, text: e.toString());
                        }
                      }
                    }
                  : null,
              onCancelBeacon: beaconAllowsCancel(b)
                  ? () async {
                      await Future<void>.delayed(Duration.zero);
                      if (!context.mounted) return;
                      try {
                        await evaluationRepo.beaconCancel(b.id);
                      } catch (e) {
                        if (context.mounted) {
                          showSnackBar(context, isError: true, text: e.toString());
                        }
                      }
                    }
                  : null,
              onEdit: b.lifecycle == BeaconLifecycle.open
                  ? () => unawaited(
                      context.router.pushPath(
                        '$kPathBeaconNew?$kQueryBeaconEditId=${b.id}',
                      ),
                    )
                  : null,
              onForward: b.allowsForward
                  ? () => unawaited(
                      context.router.pushPath('$kPathForwardBeacon/${b.id}'),
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
              onLineageSuggestions: beaconAllowsLineageOverflow(b)
                  ? () => runBeaconLineageSuggestionsPreview(
                      context,
                      beaconId: b.id,
                    )
                  : null,
              onDelete: () async {
                await Future<void>.delayed(Duration.zero);
                if (!context.mounted) return;
                if (await BeaconDeleteDialog.show(
                      context,
                      lifecycle: b.lifecycle,
                      hasEverHadCommitter: beaconDeleteBlockedByCommitters(b),
                    ) ??
                    false) {
                  try {
                    await repo.delete(b.id);
                  } catch (e) {
                    if (context.mounted) {
                      showSnackBar(context, isError: true, text: e.toString());
                    }
                  }
                }
              },
            ),
          ),
          const SizedBox(height: 6),
          MyWorkCardMetadataRow(
            beacon: b,
            viewModel: vm,
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
  });

  final MyWorkCardViewModel vm;
  final String currentUserId;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final b = vm.beacon;
    final statusLine = myWorkStatusLine(l10n: l10n, vm: vm);
    final headerStatus = _myWorkCardHeaderStatus(
      statusLine,
      roomSubtitle:
          vm.roomInboxSubtitle.isEmpty ? null : vm.roomInboxSubtitle,
    );
    return BeaconCardShell(
      muted: true,
      onTap: () => _openBeacon(context, b.id),
      footer: _myWorkArchiveFooter(context, vm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          BeaconCardHeaderRow(
            beacon: b,
            titleMaxLines: 1,
            statusLine: headerStatus.statusLine,
            statusTone: headerStatus.statusTone,
            menu: BeaconOverflowMenu(
              beacon: b,
              onForward: b.allowsForward
                  ? () => unawaited(
                      context.router.pushPath('$kPathForwardBeacon/${b.id}'),
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
              onLineageSuggestions: beaconAllowsLineageOverflow(b)
                  ? () => runBeaconLineageSuggestionsPreview(
                      context,
                      beaconId: b.id,
                    )
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
          ),
        ],
      ),
    );
  }
}
