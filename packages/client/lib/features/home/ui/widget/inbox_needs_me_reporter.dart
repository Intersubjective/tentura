import 'package:flutter/material.dart';

import 'package:tentura/features/home/ui/bloc/new_stuff_cubit.dart';
import 'package:tentura/features/inbox/ui/bloc/inbox_cubit.dart';

/// Reports Inbox Needs me count to [NewStuffCubit] for cross-tab empty-state CTAs.
class InboxNeedsMeReporter extends StatelessWidget {
  const InboxNeedsMeReporter({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return BlocListener<InboxCubit, InboxState>(
      listenWhen: (p, c) =>
          c.isSuccess &&
          (p.items != c.items || p.status != c.status || !p.isSuccess),
      listener: (context, state) {
        context.read<NewStuffCubit>().reportInboxNeedsMe(
          count: state.needsMe.length,
          loadComplete: state.isSuccess,
        );
      },
      child: child,
    );
  }
}
