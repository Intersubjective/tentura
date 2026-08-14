import 'dart:async' show unawaited;

import 'package:flutter/material.dart';
import 'package:meta/meta.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';

import 'package:tentura/app/router/root_router.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/features/profile_view/ui/widget/mutual_friends_button.dart';
import 'package:tentura/ui/bloc/screen_cubit.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/utils/availability_line.dart';
import 'package:tentura/ui/widget/focus_flash_highlight.dart';
import 'package:tentura/ui/widget/tentura_info_hint_button.dart';
import 'package:tentura/ui/widget/unfocus_sheet_body.dart';

import '../../domain/entity/person_forward_row.dart';
import '../bloc/person_forward_cubit.dart';
import '../widget/forward_input_decoration.dart';

@RoutePage()
class PersonForwardScreen extends StatelessWidget implements AutoRouteWrapper {
  const PersonForwardScreen({
    @PathParam('id') this.personId = '',
    super.key,
  });

  final String personId;

  @override
  Widget wrappedRoute(BuildContext context) => BlocProvider(
    create: (_) => PersonForwardCubit(personId: personId),
    child: this,
  );

  @override
  Widget build(BuildContext context) {
    return const PersonForwardPage();
  }
}

class PersonForwardPage extends StatelessWidget {
  const PersonForwardPage({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final tt = context.tt;
    return BlocBuilder<PersonForwardCubit, PersonForwardState>(
      builder: (context, state) {
        final person = state.person;
        final title = person == null
            ? l10n.forwardBeaconTitle
            : l10n.beaconForwardToPersonTitle(person.shownName);
        return Scaffold(
          backgroundColor: tt.bg,
          appBar: TenturaTopBar.of(
            context,
            leading: const AutoLeadingButton(),
            title: Text(title),
            progress: TenturaTopBar.loadingBar(context, state.isLoading),
          ),
          body: SafeArea(
            child: TenturaContentColumn(
              child: personForwardBodyForTest(state: state),
            ),
          ),
        );
      },
    );
  }
}

@visibleForTesting
Widget personForwardBodyForTest({required PersonForwardState state}) =>
    _PersonForwardBody(state: state);

class _PersonForwardBody extends StatelessWidget {
  const _PersonForwardBody({required this.state});

  final PersonForwardState state;

  @override
  Widget build(BuildContext context) {
    final tt = context.tt;
    if (state.person == null && state.isLoading) {
      return const Center(child: CircularProgressIndicator.adaptive());
    }
    if (state.loadError != null && state.person == null) {
      return Center(
        child: Padding(
          padding: EdgeInsets.all(tt.screenHPadding),
          child: Text(
            state.loadError.toString(),
            textAlign: TextAlign.center,
            style: TenturaText.bodySmall(tt.textMuted),
          ),
        ),
      );
    }

    final person = state.person;
    if (person == null) {
      return const SizedBox.shrink();
    }

    final l10n = L10n.of(context)!;
    final todayUtc = context.select<PersonForwardCubit, DateTime>(
      (cubit) => cubit.todayUtc,
    );
    final availability = person.availability;
    final isPaused = availability.blocksNewRequestsOn(todayUtc);
    final limitedLine = otherAvailabilityStatusLine(
      l10n,
      availability,
      todayUtc,
    );

    return ListView(
      padding: EdgeInsets.fromLTRB(
        tt.screenHPadding,
        tt.sectionGap,
        tt.screenHPadding,
        tt.sectionGap,
      ),
      children: [
        if (!person.isMutuallyVisible) ...[
          _UnreachableBanner(personName: person.shownName, personId: person.id),
          SizedBox(height: tt.sectionGap),
        ],
        if (isPaused && person.isMutuallyVisible) ...[
          _AvailabilityPausedBanner(
            personName: person.shownName,
            resumeOn: availability.resumeOn!,
            todayUtc: todayUtc,
          ),
          SizedBox(height: tt.sectionGap),
        ],
        if (limitedLine != null && !isPaused) ...[
          TenturaStatusText(
            limitedLine,
            tone: TenturaTone.neutral,
            maxLines: null,
            softWrap: true,
          ),
          SizedBox(height: tt.sectionGap),
        ],
        if (state.rows.isEmpty)
          _EmptyRequests(
            personName: person.shownName,
            personId: person.id,
            canCreateRequest: !isPaused,
          )
        else ...[
          for (final row in state.rows)
            Padding(
              padding: EdgeInsets.only(bottom: tt.rowGap),
              child: _PersonForwardRowTile(row: row, state: state),
            ),
          SizedBox(height: tt.rowGap),
          _NoteAndSend(state: state),
          SizedBox(height: tt.rowGap),
          _NewRequestButton(
            personName: person.shownName,
            personId: person.id,
            enabled: !isPaused,
          ),
        ],
      ],
    );
  }
}

class _UnreachableBanner extends StatelessWidget {
  const _UnreachableBanner({
    required this.personName,
    required this.personId,
  });

  final String personName;
  final String personId;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final tt = context.tt;
    return Material(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(tt.cardRadius),
      child: Padding(
        padding: tt.cardPadding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.beaconForwardPersonUnreachable(personName),
              style: TenturaText.bodySmall(tt.textMuted),
            ),
            SizedBox(height: tt.tightGap),
            MutualFriendsButton(userId: personId),
          ],
        ),
      ),
    );
  }
}

class _AvailabilityPausedBanner extends StatelessWidget {
  const _AvailabilityPausedBanner({
    required this.personName,
    required this.resumeOn,
    required this.todayUtc,
  });

  final String personName;
  final DateTime resumeOn;
  final DateTime todayUtc;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final tt = context.tt;
    return Material(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(tt.cardRadius),
      child: Padding(
        padding: tt.cardPadding,
        child: Text(
          personForwardPausedBanner(
            l10n,
            name: personName,
            resumeOn: resumeOn,
            todayUtc: todayUtc,
          ),
          style: TenturaText.bodySmall(tt.textMuted),
        ),
      ),
    );
  }
}

class _PersonForwardRowTile extends StatelessWidget {
  const _PersonForwardRowTile({
    required this.row,
    required this.state,
  });

  final PersonForwardRow row;
  final PersonForwardState state;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final tt = context.tt;
    final enabled = row.isEligible && (state.person?.isMutuallyVisible ?? false);
    final alreadySent = row.block == PersonForwardBlock.alreadySent;
    final showForwardEdgeActions = alreadySent && row.isForwardEdgeCancellable;
    final muted = !enabled;
    final subtitle = _rowSubtitle(l10n, row);
    final flashActive = state.lastDeliveredBeaconId == row.beacon.id;
    return FocusFlashHighlight(
      active: flashActive,
      borderRadius: BorderRadius.circular(tt.cardRadius),
      child: Material(
        color: tt.surface,
        borderRadius: BorderRadius.circular(tt.cardRadius),
        child: InkWell(
          borderRadius: BorderRadius.circular(tt.cardRadius),
          onTap: enabled
              ? () => context
                    .read<PersonForwardCubit>()
                    .selectBeacon(row.beacon.id)
              : alreadySent
              ? () => unawaited(
                  context.router.push(
                    ForwardBeaconRoute(beaconId: row.beacon.id),
                  ),
                )
              : null,
          child: Padding(
            padding: tt.cardPadding,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.article_outlined,
                  size: tt.iconSize,
                  color: muted ? tt.textMuted : tt.text,
                ),
                SizedBox(width: tt.rowGap),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        row.beacon.title.isEmpty
                            ? l10n.beaconUntitled
                            : row.beacon.title,
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          color: muted ? tt.textMuted : tt.text,
                        ),
                      ),
                      SizedBox(height: tt.tightGap),
                      Text(
                        subtitle,
                        style: TenturaText.bodySmall(tt.textMuted),
                      ),
                    ],
                  ),
                ),
                if (showForwardEdgeActions) ...[
                  IconButton(
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                      minWidth: 44,
                      minHeight: 44,
                    ),
                    tooltip: l10n.forwardEditAction,
                    icon: Icon(
                      Icons.edit_outlined,
                      size: tt.iconSize,
                      color: tt.textMuted,
                    ),
                    onPressed: () => unawaited(
                      context.router.push(
                        ForwardBeaconRoute(beaconId: row.beacon.id),
                      ),
                    ),
                  ),
                  IconButton(
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                      minWidth: 44,
                      minHeight: 44,
                    ),
                    tooltip: l10n.forwardCancelAction,
                    style: IconButton.styleFrom(
                      foregroundColor: tt.warn,
                    ),
                    icon: Icon(
                      Icons.cancel_outlined,
                      size: tt.iconSize,
                    ),
                    onPressed: () => unawaited(
                      context
                          .read<PersonForwardCubit>()
                          .cancelSelectedOr(row.beacon.id),
                    ),
                  ),
                ],
                IconButton(
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: 44,
                    minHeight: 44,
                  ),
                  tooltip: enabled ? l10n.beaconForwardPersonSend : subtitle,
                  onPressed: enabled
                      ? () => context.read<PersonForwardCubit>().selectBeacon(
                          row.beacon.id,
                        )
                      : null,
                  icon: Icon(
                    state.selectedBeaconId == row.beacon.id
                        ? Icons.radio_button_checked
                        : Icons.radio_button_unchecked,
                    color:
                        enabled ? Theme.of(context).colorScheme.primary : null,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _NoteAndSend extends StatelessWidget {
  const _NoteAndSend({required this.state});

  final PersonForwardState state;

  Future<void> _handleSend(BuildContext context) async {
    final cubit = context.read<PersonForwardCubit>();
    final trimmedNote = state.note.trim();
    if (trimmedNote.isEmpty && !state.noteSkipped) {
      final personName = state.person?.shownName;
      if (personName == null) return;
      final sent = await _showUncoveredNoteSheet(
        context: context,
        personName: personName,
        onSendWithNote: (note) {
          cubit.setNote(note);
        },
        onSendWithoutNote: cubit.skipNote,
      );
      if (!sent || !context.mounted) return;
    }
    await cubit.send();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final tt = context.tt;
    final todayUtc = context.select<PersonForwardCubit, DateTime>(
      (cubit) => cubit.todayUtc,
    );
    final canSend = state.canSendOn(todayUtc);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          enabled: canSend,
          onChanged: context.read<PersonForwardCubit>().setNote,
          decoration: InputDecoration(
            hintText: l10n.beaconForwardPersonNoteHint,
          ),
          minLines: 1,
          maxLines: 3,
        ),
        SizedBox(height: tt.rowGap),
        FilledButton(
          onPressed: canSend && !state.isLoading
              ? () => unawaited(_handleSend(context))
              : null,
          child: Text(l10n.beaconForwardPersonSend),
        ),
      ],
    );
  }
}

class _EmptyRequests extends StatelessWidget {
  const _EmptyRequests({
    required this.personName,
    required this.personId,
    required this.canCreateRequest,
  });

  final String personName;
  final String personId;
  final bool canCreateRequest;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final tt = context.tt;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          l10n.beaconForwardPersonEmpty(personName),
          style: TenturaText.bodySmall(tt.textMuted),
          textAlign: TextAlign.center,
        ),
        SizedBox(height: tt.rowGap),
        _NewRequestButton(
          personName: personName,
          personId: personId,
          enabled: canCreateRequest,
        ),
      ],
    );
  }
}

class _NewRequestButton extends StatelessWidget {
  const _NewRequestButton({
    required this.personName,
    required this.personId,
    required this.enabled,
  });

  final String personName;
  final String personId;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final reachable = context.select<PersonForwardCubit, bool>(
      (c) => c.state.person?.isMutuallyVisible ?? false,
    );
    return TextButton.icon(
      onPressed: reachable && enabled
          ? () => context.read<ScreenCubit>().showBeaconCreateFor(personId)
          : null,
      icon: const Icon(Icons.add),
      label: Text(l10n.beaconForwardPersonNewRequest(personName)),
    );
  }
}

String _rowSubtitle(L10n l10n, PersonForwardRow row) => switch (row.block) {
  PersonForwardBlock.none => _lifecycleLabel(l10n, row.beacon),
  PersonForwardBlock.notOpen => l10n.beaconForwardPersonReasonNotOpen,
  PersonForwardBlock.alreadySent => l10n.beaconForwardPersonReasonAlreadySent,
  PersonForwardBlock.alreadyHelping =>
    l10n.beaconForwardPersonReasonAlreadyHelping,
  PersonForwardBlock.declined => l10n.beaconForwardPersonReasonDeclined,
  PersonForwardBlock.withdrawn => l10n.beaconForwardPersonReasonWithdrawn,
  PersonForwardBlock.theirOwn => l10n.beaconForwardPersonReasonTheirOwn,
};

String _lifecycleLabel(L10n l10n, Beacon beacon) => switch (beacon.status) {
  BeaconStatus.open => l10n.beaconLifecycleOpen,
  BeaconStatus.needsMoreHelp => l10n.coordinationMoreHelpNeeded,
  BeaconStatus.enoughHelp => l10n.coordinationEnoughHelp,
  BeaconStatus.cancelled => l10n.beaconLifecycleCancelled,
  BeaconStatus.closed => l10n.beaconLifecycleClosed,
  BeaconStatus.deleted => l10n.beaconLifecycleDeleted,
  BeaconStatus.draft => l10n.beaconLifecycleDraft,
  BeaconStatus.reviewOpen => l10n.beaconLifecycleReviewOpen,
};

enum _PersonForwardUncoveredSheetResult { sent, dismissed }

Future<bool> _showUncoveredNoteSheet({
  required BuildContext context,
  required String personName,
  required void Function(String note) onSendWithNote,
  required VoidCallback onSendWithoutNote,
}) async {
  final result = await showTenturaAdaptiveSheet<_PersonForwardUncoveredSheetResult>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    useRootNavigator: true,
    builder: (ctx) => _PersonForwardUncoveredNoteSheet(
      personName: personName,
      onSendWithNote: onSendWithNote,
      onSendWithoutNote: onSendWithoutNote,
    ),
  );
  return result == _PersonForwardUncoveredSheetResult.sent;
}

class _PersonForwardUncoveredNoteSheet extends StatefulWidget {
  const _PersonForwardUncoveredNoteSheet({
    required this.personName,
    required this.onSendWithNote,
    required this.onSendWithoutNote,
  });

  final String personName;
  final void Function(String note) onSendWithNote;
  final VoidCallback onSendWithoutNote;

  @override
  State<_PersonForwardUncoveredNoteSheet> createState() =>
      _PersonForwardUncoveredNoteSheetState();
}

class _PersonForwardUncoveredNoteSheetState
    extends State<_PersonForwardUncoveredNoteSheet> {
  final _noteController = TextEditingController();

  @override
  void dispose() {
    _noteController.dispose();
    super.dispose();
  }

  bool get _isDirty => _noteController.text.trim().isNotEmpty;

  bool get _canSendWithNote => _noteController.text.trim().isNotEmpty;

  void _sendWithNote() {
    if (!_canSendWithNote) return;
    widget.onSendWithNote(_noteController.text.trim());
    Navigator.of(context).pop(_PersonForwardUncoveredSheetResult.sent);
  }

  void _sendWithoutNote() {
    widget.onSendWithoutNote();
    Navigator.of(context).pop(_PersonForwardUncoveredSheetResult.sent);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final tt = context.tt;
    final bottom = MediaQuery.viewInsetsOf(context).bottom;

    return UnfocusSheetBody(
      child: TenturaSheetDismissGuard(
        isDirty: _isDirty,
        useRootNavigator: true,
        child: Padding(
          padding: EdgeInsets.only(
            left: tt.screenHPadding,
            right: tt.screenHPadding,
            top: tt.sectionGap,
            bottom: bottom + tt.sectionGap,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      l10n.forwardUncoveredRecipientsTitle,
                      style: TenturaText.title(tt.text),
                    ),
                  ),
                  TenturaInfoHintButton(
                    fullText: l10n.forwardUncoveredSharedNoteInfo,
                    semanticsLabel: l10n.forwardUncoveredSharedNoteInfo,
                  ),
                ],
              ),
              SizedBox(height: tt.rowGap),
              Text(
                widget.personName,
                style: TenturaText.body(tt.text),
              ),
              SizedBox(height: tt.rowGap),
              TextField(
                controller: _noteController,
                onChanged: (_) => setState(() {}),
                minLines: 2,
                maxLines: 4,
                decoration: forwardNoteInputDecoration(
                  context,
                  hintText: l10n.forwardSharedNoteHint,
                ),
              ),
              SizedBox(height: tt.rowGap),
              SizedBox(
                height: tt.buttonHeight,
                child: FilledButton(
                  onPressed: _canSendWithNote ? _sendWithNote : null,
                  child: Text(l10n.forwardToCount(1)),
                ),
              ),
              SizedBox(height: tt.rowGap),
              TextButton(
                onPressed: _sendWithoutNote,
                child: Text(l10n.forwardSendWithoutSharedNote),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
