import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:tentura/app/router/browse_deep_link.dart';
import 'package:tentura/app/router/root_router.dart';
import 'package:tentura/consts.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/features/profile/ui/bloc/profile_cubit.dart';
import 'package:tentura/ui/effect/ui_effect_port.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/widget/auto_leading_with_fallback.dart';

import '../../domain/use_case/beacon_lobby_case.dart';
import '../bloc/beacon_lobby_cubit.dart';
import '../widget/beacon_lobby_body.dart';

/// The app-bar arrow on Questions (#689): leave Questions so that it is not
/// in the history any more, and the next system Back goes where the Request
/// was opened from.
///
/// With the Request below, go back to it: on the web through the browser's
/// own history, so Questions' entry is left rather than covered by a new
/// one (an in-app pop pushes the Request's URL as a fresh entry, and Back
/// then returned to Questions). With nothing below (a cold link, a reload, a
/// notification), Questions is replaced by its Request over its Home source,
/// in place in the browser history too.
Future<void> leaveBeaconLobby(
  StackRouter router, {
  required String beaconId,
  bool web = kIsWeb,
}) async {
  if (router.canPop()) {
    if (web && router.canNavigateBack) {
      router.back();
      return;
    }
    await router.maybePop();
    return;
  }
  final root = router.root;
  final stack = buildBrowseDeepLinkStack(
    Uri(path: '$kPathBeaconView/$beaconId'),
  );
  root.markUrlStateForReplace();
  await root.replaceAll(
    stack == null
        ? [BeaconViewRoute(id: beaconId)]
        : [stack.home, stack.detail],
  );
}

/// The Questions app-bar arrow; see [leaveBeaconLobby].
class BeaconLobbyBackButton extends StatelessWidget {
  const BeaconLobbyBackButton({required this.beaconId, super.key});

  final String beaconId;

  @override
  Widget build(BuildContext context) => AutoLeadingWithFallback(
    fallbackPath: '$kPathBeaconView/$beaconId',
    onPressed: () => unawaited(
      leaveBeaconLobby(context.router, beaconId: beaconId),
    ),
  );
}

/// Request **Questions** (internally the lobby, U088): questions before
/// helping, for the Request's addressed audience; the whole thread is public
/// to that audience. The author can remove someone from it. Who may read or
/// post is decided by the server policy only.
@RoutePage()
class BeaconLobbyScreen extends StatelessWidget implements AutoRouteWrapper {
  const BeaconLobbyScreen({
    @PathParam('id') this.beaconId = '',
    super.key,
  });

  final String beaconId;

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
      leading: BeaconLobbyBackButton(beaconId: beaconId),
      title: Text(L10n.of(context)!.beaconLobbyTitle),
    ),
    body: SafeArea(
      // The same centred content column as the top bar (#658).
      child: TenturaContentColumn(
        child: BeaconLobbyBody(
          myUserId: context.read<ProfileCubit>().state.profile.id,
        ),
      ),
    ),
  );
}
