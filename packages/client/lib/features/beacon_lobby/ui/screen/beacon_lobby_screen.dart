import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';

import 'package:tentura/consts.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/features/profile/ui/bloc/profile_cubit.dart';
import 'package:tentura/ui/effect/ui_effect_port.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/widget/auto_leading_with_fallback.dart';

import '../../domain/use_case/beacon_lobby_case.dart';
import '../bloc/beacon_lobby_cubit.dart';
import '../widget/beacon_lobby_body.dart';

/// U088 — the Request lobby: questions before helping, for the author and
/// the people with a live help offer. The author can remove someone from it.
@RoutePage()
class BeaconLobbyScreen extends StatelessWidget implements AutoRouteWrapper {
  const BeaconLobbyScreen({
    @PathParam('id') this.beaconId = '',
    this.knownNames = const {},
    super.key,
  });

  final String beaconId;

  /// Display names by user id (help offerers), for the removed list.
  final Map<String, String> knownNames;

  @override
  Widget wrappedRoute(BuildContext context) => BlocProvider(
    create: (_) {
      final cubit = BeaconLobbyCubit(
        GetIt.I<BeaconLobbyCase>(),
        GetIt.I<UiEffectPort>(),
        beaconId: beaconId,
      );
      unawaited(cubit.load());
      return cubit;
    },
    child: this,
  );

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: TenturaTopBar.of(
      context,
      leading: AutoLeadingWithFallback(
        fallbackPath: '$kPathBeaconView/$beaconId',
      ),
      title: Text(L10n.of(context)!.beaconLobbyTitle),
    ),
    body: SafeArea(
      child: BeaconLobbyBody(
        myUserId: context.read<ProfileCubit>().state.profile.id,
        knownNames: knownNames,
      ),
    ),
  );
}
