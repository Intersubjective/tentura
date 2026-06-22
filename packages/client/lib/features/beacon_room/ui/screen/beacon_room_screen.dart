import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:tentura/app/router/root_router.dart';
import 'package:tentura/consts.dart';
import 'package:tentura/features/profile/ui/bloc/profile_cubit.dart';
import 'package:tentura/ui/bloc/screen_cubit.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/utils/ui_utils.dart';

import '../bloc/room_cubit.dart';
import '../widget/beacon_room_body.dart';
import '../widget/beacon_room_overflow_menu.dart';
import '../widget/room_facts_sheet.dart';

@RoutePage()
class BeaconRoomScreen extends StatelessWidget implements AutoRouteWrapper {
  const BeaconRoomScreen({
    @PathParam('id') this.beaconId = '',
    super.key,
  });

  final String beaconId;

  @override
  Widget wrappedRoute(_) => MultiBlocProvider(
    providers: [
      BlocProvider(create: (_) => ScreenCubit.local()),
      BlocProvider(
        create: (_) => RoomCubit(beaconId: beaconId),
      ),
    ],
    child: BlocListener<ScreenCubit, ScreenState>(
      // Route-local nested-router navigation only (see UiEffect port plan Phase 6).
      listener: commonScreenBlocListener,
      child: this,
    ),
  );

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final myProfile = GetIt.I<ProfileCubit>().state.profile;
    return Scaffold(
      appBar: AppBar(
        leading: Builder(
          builder: (ctx) {
            if (ctx.router.canPop()) {
              return const AutoLeadingButton();
            }
            return Semantics(
              button: true,
              label: l10n.buttonClose,
              child: IconButton(
                tooltip: l10n.buttonClose,
                icon: const Icon(Icons.close_rounded),
                onPressed: () =>
                    unawaited(ctx.router.navigatePath(kPathHome)),
              ),
            );
          },
        ),
        title: Text(l10n.beaconRoomTitle),
        actions: [
          const BeaconRoomOverflowMenu(),
          IconButton(
            tooltip: l10n.beaconRoomFactsBrowseTooltip,
            icon: const Icon(Icons.manage_search_outlined),
            onPressed: () => unawaited(
              showRoomFactsSheet(
                context,
                cubit: context.read<RoomCubit>(),
                viewerUserId: myProfile.id,
              ),
            ),
          ),
        ],
      ),
      body: const BeaconRoomBody(),
    );
  }
}
