import 'dart:async';

import 'package:flutter/material.dart';

import 'package:tentura/domain/entity/beacon_participant.dart';
import 'package:tentura/domain/entity/beacon_room_consts.dart';
import 'package:tentura/ui/l10n/l10n.dart';

import '../bloc/room_cubit.dart';
import 'beacon_room_promise_sheet.dart';

/// Room app-bar overflow (⋯): coordination actions while in chat.
class BeaconRoomOverflowMenu extends StatelessWidget {
  const BeaconRoomOverflowMenu({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    return BlocBuilder<RoomCubit, RoomState>(
      buildWhen: (prev, curr) =>
          prev.participants != curr.participants ||
          prev.myUserId != curr.myUserId,
      builder: (context, state) {
        final myUserId = state.myUserId;
        if (myUserId.isEmpty) {
          return const SizedBox.shrink();
        }
        BeaconParticipant? myParticipant;
        for (final p in state.participants) {
          if (p.userId == myUserId) {
            myParticipant = p;
            break;
          }
        }
        if (myParticipant == null) {
          return const SizedBox.shrink();
        }
        final isAuthorOrSteward =
            myParticipant.role == BeaconParticipantRoleBits.author ||
            myParticipant.role == BeaconParticipantRoleBits.steward;
        if (!hasPublishedPromiseTargets(
          participants: state.participants,
          myUserId: myUserId,
          isAuthorOrSteward: isAuthorOrSteward,
        )) {
          return const SizedBox.shrink();
        }
        return PopupMenuButton<String>(
          tooltip: l10n.coordinationCreatePromiseAction,
          onSelected: (value) {
            if (value != 'create_promise') return;
            unawaited(
              Future<void>.delayed(Duration.zero).then((_) {
                if (!context.mounted) return;
                final cubit = context.read<RoomCubit>();
                unawaited(
                  showBeaconRoomPromiseSheet(
                    context,
                    beaconId: cubit.state.beaconId,
                    participants: cubit.state.participants,
                    myUserId: myUserId,
                    isAuthorOrSteward: isAuthorOrSteward,
                  ),
                );
              }),
            );
          },
          itemBuilder: (_) => [
            PopupMenuItem<String>(
              value: 'create_promise',
              child: Row(
                children: [
                  Icon(
                    Icons.front_hand_outlined,
                    size: 22,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                  const SizedBox(width: 12),
                  Expanded(child: Text(l10n.coordinationCreatePromiseAction)),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}
