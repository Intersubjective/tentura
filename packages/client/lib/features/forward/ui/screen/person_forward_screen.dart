import 'dart:async' show unawaited;

import 'package:flutter/material.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';

import 'package:tentura/app/router/root_router.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/features/profile_view/ui/widget/mutual_friends_button.dart';
import 'package:tentura/ui/bloc/screen_cubit.dart';
import 'package:tentura/ui/l10n/l10n.dart';

import '../../domain/entity/person_forward_row.dart';
import '../bloc/person_forward_cubit.dart';

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
              child: _PersonForwardBody(state: state),
            ),
          ),
        );
      },
    );
  }
}

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

    return ListView(
      padding: EdgeInsets.fromLTRB(
        tt.screenHPadding,
        tt.sectionGap,
        tt.screenHPadding,
        tt.sectionGap,
      ),
      children: [
        if (!person.isSeeingMe) ...[
          _UnreachableBanner(personName: person.shownName, personId: person.id),
          SizedBox(height: tt.sectionGap),
        ],
        if (state.rows.isEmpty)
          _EmptyRequests(personName: person.shownName, personId: person.id)
        else ...[
          for (final row in state.rows)
            Padding(
              padding: EdgeInsets.only(bottom: tt.rowGap),
              child: _PersonForwardRowTile(row: row, state: state),
            ),
          SizedBox(height: tt.rowGap),
          _NoteAndSend(state: state),
          SizedBox(height: tt.rowGap),
          _NewRequestButton(personName: person.shownName, personId: person.id),
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
    final enabled = row.isEligible && (state.person?.isSeeingMe ?? false);
    final alreadySent = row.block == PersonForwardBlock.alreadySent;
    final muted = !enabled;
    final subtitle = _rowSubtitle(l10n, row);
    return Material(
      color: tt.surface,
      borderRadius: BorderRadius.circular(tt.cardRadius),
      child: InkWell(
        borderRadius: BorderRadius.circular(tt.cardRadius),
        onTap: enabled
            ? () =>
                  context.read<PersonForwardCubit>().selectBeacon(row.beacon.id)
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
              IconButton(
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
                  color: enabled ? Theme.of(context).colorScheme.primary : null,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NoteAndSend extends StatelessWidget {
  const _NoteAndSend({required this.state});

  final PersonForwardState state;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final tt = context.tt;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          enabled: state.canSend,
          onChanged: context.read<PersonForwardCubit>().setNote,
          decoration: InputDecoration(
            hintText: l10n.beaconForwardPersonNoteHint,
          ),
          minLines: 1,
          maxLines: 3,
        ),
        SizedBox(height: tt.rowGap),
        FilledButton(
          onPressed: state.canSend && !state.isLoading
              ? () => unawaited(context.read<PersonForwardCubit>().send())
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
  });

  final String personName;
  final String personId;

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
        _NewRequestButton(personName: personName, personId: personId),
      ],
    );
  }
}

class _NewRequestButton extends StatelessWidget {
  const _NewRequestButton({
    required this.personName,
    required this.personId,
  });

  final String personName;
  final String personId;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final person = context.select<PersonForwardCubit, bool>(
      (c) => c.state.person?.isSeeingMe ?? false,
    );
    return TextButton.icon(
      onPressed: person
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
