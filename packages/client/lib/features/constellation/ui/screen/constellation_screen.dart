import 'dart:async';

import 'package:flutter/material.dart';
import 'package:auto_route/auto_route.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/features/beacon_create/ui/bloc/beacon_create_cubit.dart';
import 'package:tentura/features/forward/ui/bloc/forward_cubit.dart';
import 'package:tentura/features/graph/ui/bloc/graph_person_context_cubit.dart';
import 'package:tentura/features/home/ui/bloc/home_tab_reselect_cubit.dart';
import 'package:tentura/features/profile/ui/bloc/profile_cubit.dart';
import 'package:tentura/features/profile_view/domain/use_case/profile_view_case.dart';
import 'package:tentura/ui/utils/ui_utils.dart';

import '../../domain/port/constellation_member_webs_port.dart';
import '../../domain/use_case/constellation_anchor_case.dart';
import '../../domain/use_case/constellation_field_case.dart';
import '../bloc/constellation_composer_cubit.dart';
import '../bloc/constellation_cubit.dart';
import '../widget/constellation_app_bar.dart';
import '../widget/constellation_body.dart';

@RoutePage()
class ConstellationScreen extends StatefulWidget implements AutoRouteWrapper {
  const ConstellationScreen({super.key});

  @override
  Widget wrappedRoute(BuildContext context) => localScreenCubitScope(
    // `ConstellationCubit`/`GraphPersonContextCubit` capture `viewer` once,
    // at construction time, not reactively — so if this screen is the very
    // first thing built after a cold load (e.g. a deep link straight into
    // this tab, before `ProfileCubit`'s own async fetch resolves), a
    // synchronous `GetIt.I<ProfileCubit>().state.profile` read would freeze
    // in an empty placeholder (empty id, empty display name) for the whole
    // Cubit's lifetime. Gate construction on the profile actually being
    // loaded instead.
    child: BlocBuilder<ProfileCubit, ProfileState>(
      bloc: GetIt.I<ProfileCubit>(),
      buildWhen: (previous, current) =>
          previous.profile.id != current.profile.id,
      builder: (context, profileState) {
        final viewer = profileState.profile;
        if (viewer.id.isEmpty) {
          return const Center(child: CircularProgressIndicator());
        }
        return BlocProvider(
          create: (_) => ConstellationCubit(
            case_: GetIt.I<ConstellationFieldCase>(),
            anchorCase: GetIt.I<ConstellationAnchorCase>(),
            memberWebsPort: GetIt.I<ConstellationMemberWebsPort>(),
            viewer: viewer,
          ),
          child: MultiBlocProvider(
            providers: [
              BlocProvider(
                create: (context) => GraphPersonContextCubit(
                  profileViewCase: GetIt.I<ProfileViewCase>(),
                  viewerId: viewer.id,
                ),
              ),
              BlocProvider(
                create: (context) {
                  final constellation = context.read<ConstellationCubit>();
                  return ConstellationComposerCubit(
                    positions: const {},
                    eligible: const {},
                    peopleSnapshot: constellation.composerPeople,
                    createCubitFactory: (kind) => BeaconCreateCubit(kind: kind),
                    forwardCubitFactory: (beaconId) =>
                        ForwardCubit(beaconId: beaconId, embedded: true),
                  );
                },
              ),
            ],
            child: this,
          ),
        );
      },
    ),
  );

  @override
  State<ConstellationScreen> createState() => _ConstellationScreenState();
}

class _ConstellationScreenState extends State<ConstellationScreen> {
  bool _legendExpanded = false;

  void _toggleLegend() => setState(() => _legendExpanded = !_legendExpanded);

  @override
  void deactivate() {
    final cubit = context.read<ConstellationCubit>();
    cubit.onRouteLeave();
    super.deactivate();
  }

  @override
  Widget build(BuildContext context) {
    return BlocListener<HomeTabReselectCubit, HomeTabReselectState>(
      listenWhen: (prev, curr) =>
          prev.constellationReselectCount != curr.constellationReselectCount,
      listener: (context, _) {
        unawaited(context.read<ConstellationCubit>().load());
      },
      child: Scaffold(
        appBar: TenturaTopBar.of(
          context,
          alignment: TenturaTopBarAlignment.content,
          title: const SizedBox.shrink(),
          row: ConstellationAppBarRow(
            legendExpanded: _legendExpanded,
            onToggleLegend: _toggleLegend,
          ),
        ),
        body: TenturaFullBleed(
          child: ConstellationBody(
            legendExpanded: _legendExpanded,
            onToggleLegend: _toggleLegend,
          ),
        ),
      ),
    );
  }
}
