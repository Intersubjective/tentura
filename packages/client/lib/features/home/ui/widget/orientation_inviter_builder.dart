import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';

import 'package:tentura/domain/entity/profile.dart';

import '../../domain/port/home_inviter_port.dart';
import '../bloc/orientation_inviter_cubit.dart';

/// Looks up the viewer's inviter once and builds with it (#523); builds with
/// null while loading, on failure, and where no lookup is registered.
class OrientationInviterBuilder extends StatelessWidget {
  const OrientationInviterBuilder({required this.builder, super.key});

  final Widget Function(BuildContext context, Profile? inviter) builder;

  @override
  Widget build(BuildContext context) {
    if (!GetIt.I.isRegistered<HomeInviterPort>()) {
      return builder(context, null);
    }
    return BlocProvider(
      create: (_) => OrientationInviterCubit(GetIt.I<HomeInviterPort>()),
      child: BlocBuilder<OrientationInviterCubit, Profile?>(builder: builder),
    );
  }
}
