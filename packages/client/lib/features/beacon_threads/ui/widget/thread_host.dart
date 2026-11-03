import 'package:flutter/material.dart';
import 'package:tentura/design_system/tentura_design_system.dart';

import '../bloc/thread_host_cubit.dart';
import '../bloc/thread_host_state.dart';

class ThreadHost extends StatelessWidget {
  const ThreadHost({
    required this.child,
    super.key,
  });

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ThreadHostCubit, ThreadHostState>(
      builder: (context, hostState) {
        if (hostState.switching) {
          return const Center(child: TenturaCircularProgress(adaptive: true));
        }
        final roomCubit = context.read<ThreadHostCubit>().roomCubit;
        if (roomCubit == null) {
          return const SizedBox.shrink();
        }
        return BlocProvider.value(
          value: roomCubit,
          child: child,
        );
      },
    );
  }
}
