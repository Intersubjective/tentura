import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:tentura/features/home/ui/bloc/home_attention_cubit.dart';
import 'package:tentura/features/inbox/ui/bloc/inbox_cubit.dart';
import 'package:tentura/features/inbox/ui/bloc/inbox_operational_cubit.dart';

/// Reports the successful Inbox projection to its two home-shell consumers.
class InboxNeedsMeReporter extends StatelessWidget {
  const InboxNeedsMeReporter({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return BlocListener<InboxCubit, InboxState>(
      listenWhen: (p, c) =>
          p.items != c.items ||
          p.status != c.status ||
          p.projectionLoaded != c.projectionLoaded,
      listener: (context, state) {
        final loaded = state.isSuccess && state.projectionLoaded;
        context.read<InboxOperationalCubit>().report(
          needsMeCount: state.needsMe.length,
          loadComplete: loaded,
        );
        context.read<HomeAttentionCubit>().reportInboxSnapshot(
          accountId: state.currentUserId,
          beaconIds: loaded
              ? {
                  ...state.needsMe.map((item) => item.beaconId),
                  ...state.watching.map((item) => item.beaconId),
                }
              : const {},
          loaded: loaded,
        );
      },
      child: child,
    );
  }
}
