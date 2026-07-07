import 'package:flutter/material.dart';
import 'package:auto_route/auto_route.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/features/context/ui/bloc/context_cubit.dart';

import '../bloc/forward_cubit.dart';
import '../widget/forward_recipient_picker.dart';

@RoutePage()
class ForwardBeaconScreen extends StatelessWidget implements AutoRouteWrapper {
  const ForwardBeaconScreen({
    @PathParam('id') this.beaconId = '',
    super.key,
  });

  final String beaconId;

  @override
  Widget wrappedRoute(BuildContext context) => BlocProvider(
    create: (_) => ForwardCubit(
      beaconId: beaconId,
      context: context.read<ContextCubit>().state.selected,
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
          child: ForwardRecipientPicker(beaconId: beaconId),
        ),
      ),
    );
  }
}
