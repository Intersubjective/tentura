import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';

import 'package:tentura/features/home/domain/port/post_join_beacon_handoff_port.dart';
import 'package:tentura/features/home/ui/bloc/post_join_navigation_cubit.dart';
import 'package:tentura/features/invitation/ui/message/accept_invite_messages.dart';
import 'package:tentura/ui/effect/ui_effect.dart';
import 'package:tentura/ui/effect/ui_effect_port.dart';

/// One-shot post-invite tab + snackbar after Home mounts (signup / web handoff).
class HomePostJoinListener extends StatefulWidget {
  const HomePostJoinListener({
    required this.tabsRouter,
    required this.child,
    super.key,
  });

  final TabsRouter tabsRouter;
  final Widget child;

  @override
  State<HomePostJoinListener> createState() => _HomePostJoinListenerState();
}

class _HomePostJoinListenerState extends State<HomePostJoinListener> {
  var _handled = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => unawaited(_handlePostJoin()),
    );
  }

  Future<void> _handlePostJoin() async {
    if (_handled || !mounted) return;
    _handled = true;

    final postJoin = GetIt.I<PostJoinNavigationCubit>();
    final handoff = GetIt.I<PostJoinBeaconHandoffPort>().readAndClear();
    if (handoff != null) {
      postJoin.set(handoff);
    }

    final dest = postJoin.takeDestination();
    if (dest == null || !dest.hasBeacon) return;

    widget.tabsRouter.setActiveIndex(1);

    if (!dest.showSnackbar) return;

    GetIt.I<UiEffectPort>().emit(
      ShowMessage(
        BeaconInviteAcceptedMessage(
          inviterName: dest.inviterName ?? '',
          beaconId: dest.beaconId!,
          beaconTitle: dest.beaconTitle ?? '',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
