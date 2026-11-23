import 'dart:async';

import 'package:flutter/material.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';

import 'package:tentura/app/router/root_router.dart';
import 'package:tentura/app/platform/landing_redirect.dart';
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
  Widget build(BuildContext context) =>
      BlocConsumer<AcceptInviteCubit, AcceptInviteState>(
        listener: (context, state) {
          if (state.needsConfirmation) {
            if (!_confirmStarted) {
              _confirmStarted = true;
              unawaited(_runConfirmation(context, state));
            }
            return;
          }
          final signupCode = state.pendingSignupCode;
          if (signupCode != null && signupCode.isNotEmpty) {
            unawaited(_handleSignupNavigation(context, signupCode));
          }
        },
        builder: (context, state) => Scaffold(
          body: SafeArea(
            child: Center(
              child: state.isLoading || state.needsConfirmation
                  ? const TenturaCircularProgress(adaptive: true)
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
    final signupCode = state.pendingSignupCode;
    final accepted =
        await InvitationAcceptDialog.show(
          context,
          profile: inviter,
          beacon: state.pendingBeacon,
          signup: signupCode != null,
        ) ??
        false;
    if (!context.mounted) {
      return;
    }
    if (!accepted) {
      cubit.cancelAccept();
    } else if (signupCode != null) {
      await _handleSignupNavigation(context, signupCode);
    } else {
      await cubit.confirmAccept();
    }
  }

  Future<void> _handleSignupNavigation(
    BuildContext context,
    String code,
  ) async {
    if (goToLanding(invitePath: '/invite/$code')) {
      context.read<AcceptInviteCubit>().clearPendingSignupNavigation();
      return;
    }
    if (!context.mounted) {
      return;
    }
    await context.router.replaceAll([
      AuthRegisterRoute(id: code),
    ]);
    if (!context.mounted) {
      return;
    }
    context.read<AcceptInviteCubit>().clearPendingSignupNavigation();
  }
}
