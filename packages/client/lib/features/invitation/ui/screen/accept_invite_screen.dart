import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';

import 'package:tentura/app/router/root_router.dart';
import 'package:tentura/consts.dart';
import 'package:tentura/features/auth/data/service/web_redirect.dart';
import 'package:tentura/ui/bloc/state_base.dart';

import '../bloc/accept_invite_cubit.dart';
import '../dialog/invitation_accept_dialog.dart';

@RoutePage()
class AcceptInviteScreen extends StatefulWidget implements AutoRouteWrapper {
  const AcceptInviteScreen({
    @PathParam('id') this.id = '',
    super.key,
  });

  final String id;

  @override
  Widget wrappedRoute(BuildContext context) => BlocProvider(
    create: (_) => GetIt.I<AcceptInviteCubit>(),
    child: this,
  );

  @override
  State<AcceptInviteScreen> createState() => _AcceptInviteScreenState();
}

class _AcceptInviteScreenState extends State<AcceptInviteScreen> {
  var _confirmStarted = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(context.read<AcceptInviteCubit>().start(widget.id));
    });
  }

  @override
  Widget build(BuildContext context) => BlocConsumer<AcceptInviteCubit, AcceptInviteState>(
    listener: (context, state) {
      if (state.needsConfirmation && !_confirmStarted) {
        _confirmStarted = true;
        unawaited(_runConfirmation(context, state));
        return;
      }
      if (state.status is StateIsNavigating) {
        unawaited(_handleNavigation(context, state));
      }
    },
    builder: (context, state) => Scaffold(
      body: SafeArea(
        child: Center(
          child: state.isLoading || state.needsConfirmation
              ? const CircularProgressIndicator.adaptive()
              : const SizedBox.shrink(),
        ),
      ),
    ),
  );

  Future<void> _runConfirmation(
    BuildContext context,
    AcceptInviteState state,
  ) async {
    final inviter = state.pendingInviter;
    if (inviter == null || !context.mounted) {
      return;
    }
    final cubit = context.read<AcceptInviteCubit>();
    final accepted =
        await InvitationAcceptDialog.show(context, profile: inviter) ?? false;
    if (!context.mounted) {
      return;
    }
    if (accepted) {
      await cubit.confirmAccept();
    } else {
      cubit.cancelAccept();
    }
  }

  Future<void> _handleNavigation(
    BuildContext context,
    AcceptInviteState state,
  ) async {
    final path = (state.status as StateIsNavigating).path;
    if (path.startsWith(kPathSignUp)) {
      if (goToLanding(invitePath: '/invite/${state.code}')) {
        return;
      }
      if (!context.mounted) {
        return;
      }
      await context.router.replaceAll([
        AuthRegisterRoute(id: state.code),
      ]);
    }
  }
}
