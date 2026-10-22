import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';

import 'package:tentura/app/router/root_router.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/ui/l10n/l10n.dart';

import '../../domain/entity/beacon_lobby.dart';
import '../../domain/use_case/beacon_lobby_case.dart';
import '../bloc/beacon_lobby_entry_cubit.dart';

/// Row on a Request's Overview that opens Questions. Shown only when the
/// server policy says the viewer may read Questions (the client never
/// re-implements who is in the audience).
class BeaconLobbyEntryRow extends StatelessWidget {
  const BeaconLobbyEntryRow({required this.beaconId, super.key});

  final String beaconId;

  @override
  Widget build(BuildContext context) =>
      // Not wired (isolated widget tests of the Request page): no row.
      !GetIt.I.isRegistered<BeaconLobbyCase>()
      ? const SizedBox.shrink()
      : BlocProvider(
          key: ValueKey(beaconId),
          create: (_) {
            final cubit = BeaconLobbyEntryCubit(
              GetIt.I<BeaconLobbyCase>(),
              beaconId: beaconId,
            );
            unawaited(cubit.load());
            return cubit;
          },
          child: BlocBuilder<BeaconLobbyEntryCubit, BeaconLobbyAccess?>(
            builder: (context, access) {
              if (access == null || !access.canRead) {
                return const SizedBox.shrink();
              }
              final l10n = L10n.of(context)!;
              return ListTile(
                key: const Key('beaconLobbyEntry'),
                leading: const Icon(TenturaIcons.comments),
                title: Text(l10n.beaconLobbyTitle),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(l10n.beaconLobbyEntrySubtitle),
                    TenturaMetaText(
                      l10n.beaconLobbyEntryCount(access.messageCount),
                    ),
                  ],
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () =>
                    context.router.push(BeaconLobbyRoute(beaconId: beaconId)),
              );
            },
          ),
        );
}
