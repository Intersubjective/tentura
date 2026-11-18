import 'dart:async';

import 'package:flutter/material.dart';
import 'package:auto_route/auto_route.dart';

import 'package:tentura/consts.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/features/context/ui/bloc/context_cubit.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/navigation/app_navigator.dart';

import '../../domain/exception.dart';
import '../bloc/forward_cubit.dart';
import '../widget/forward_recipient_picker.dart';

@RoutePage()
class ForwardBeaconScreen extends StatelessWidget implements AutoRouteWrapper {
  const ForwardBeaconScreen({
    @PathParam('id') this.beaconId = '',
    @QueryParam(kQueryForwardTags) this.tags,
    super.key,
  });

  final String beaconId;

  /// Own tag ids from the tag lens, comma-separated.
  final String? tags;

  @override
  Widget wrappedRoute(BuildContext context) => BlocProvider(
    create: (_) => ForwardCubit(
      beaconId: beaconId,
      context: context.read<ContextCubit>().state.selected,
      checkForwardPermission: true,
      initialTagIds: {
        for (final id in (tags ?? '').split(','))
          if (id.isNotEmpty) id,
      },
    ),
    child: this,
  );

  @override
  Widget build(BuildContext context) {
    return ForwardBeaconPage(beaconId: beaconId);
  }
}

/// Forward beacon recipient picker (compact operational layout).
class ForwardBeaconPage extends StatelessWidget {
  const ForwardBeaconPage({required this.beaconId, super.key});

  final String beaconId;

  @override
  Widget build(BuildContext context) {
    final tt = context.tt;
    return Scaffold(
      backgroundColor: tt.bg,
      body: SafeArea(
        child: TenturaContentColumn(
          child:
              BlocSelector<
                ForwardCubit,
                ForwardState,
                ForwardPermissionDenied?
              >(
                selector: (state) => switch (state.candidatesLoad) {
                  ForwardCandidatesError(
                    error: final ForwardPermissionDenied denied,
                  ) =>
                    denied,
                  _ => null,
                },
                builder: (context, denied) => denied == null
                    ? ForwardRecipientPicker(beaconId: beaconId)
                    : _ForwardDeniedPane(denied),
              ),
        ),
      ),
    );
  }
}

class _ForwardDeniedPane extends StatelessWidget {
  const _ForwardDeniedPane(this.denied);

  final ForwardPermissionDenied denied;

  @override
  Widget build(BuildContext context) {
    final l10n = lookupL10n(Localizations.localeOf(context));
    final isRequest = denied.beacon.isRequest;
    return Column(
      children: [
        TenturaTopBar.of(
          context,
          title: Text(
            isRequest ? l10n.forwardBeaconTitle : l10n.forwardPostTitle,
          ),
          leading: CloseButton(
            onPressed: () {
              final router = context.router;
              if (router.canPop()) {
                unawaited(router.maybePop());
              } else {
                unawaited(
                  GetIt.I<AppNavigator>().navigateToBeacon(
                    denied.beacon.id,
                    entry: kBeaconEntryForward,
                  ),
                );
              }
            },
          ),
        ),
        Expanded(
          child: TenturaEmptyState(
            icon: Icons.lock_outline,
            title: isRequest
                ? l10n.forwardRequestNotAllowed
                : l10n.forwardPostNotAllowed,
          ),
        ),
      ],
    );
  }
}
