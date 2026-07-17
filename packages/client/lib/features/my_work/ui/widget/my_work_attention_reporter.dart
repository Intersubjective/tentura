import 'package:flutter/material.dart';

import 'package:tentura/features/home/ui/bloc/home_attention_cubit.dart';

import '../bloc/my_work_cubit.dart';

/// Reports the successfully loaded, non-archived My Work projection.
class MyWorkAttentionReporter extends StatelessWidget {
  const MyWorkAttentionReporter({
    required this.accountId,
    required this.child,
    super.key,
  });

  final String accountId;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return BlocListener<MyWorkCubit, MyWorkState>(
      listenWhen: (previous, current) =>
          previous.nonArchivedCards != current.nonArchivedCards ||
          previous.nonArchivedProjectionLoaded !=
              current.nonArchivedProjectionLoaded,
      listener: (context, state) {
        final loaded = state.nonArchivedProjectionLoaded;
        context.read<HomeAttentionCubit>().reportMyWorkSnapshot(
          accountId: accountId,
          beaconIds: loaded
              ? state.nonArchivedCards.map((card) => card.beaconId).toSet()
              : const {},
          loaded: loaded,
        );
      },
      child: child,
    );
  }
}
