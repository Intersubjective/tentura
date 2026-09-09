import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:tentura/features/inbox/ui/bloc/inbox_cubit.dart';
import 'package:tentura/features/my_work/ui/bloc/my_work_cubit.dart';

import '../bloc/home_activation_cubit.dart';

/// Reports My Work and Inbox projections into [HomeActivationCubit].
class HomeActivationReporter extends StatelessWidget {
  const HomeActivationReporter({
    required this.accountId,
    required this.child,
    super.key,
  });

  final String accountId;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return MultiBlocListener(
      listeners: [
        BlocListener<MyWorkCubit, MyWorkState>(
          listenWhen: (previous, current) =>
              previous.nonArchivedCards != current.nonArchivedCards ||
              previous.archivedCountHint != current.archivedCountHint ||
              previous.draftCount != current.draftCount ||
              previous.nonArchivedProjectionLoaded !=
                  current.nonArchivedProjectionLoaded,
          listener: (context, state) {
            context.read<HomeActivationCubit>().reportMyWork(
              accountId: accountId,
              myWorkCardCount: state.nonArchivedCards.length,
              draftCount: state.draftCount,
              archivedCountHint: state.archivedCountHint,
              myWorkLoaded: state.nonArchivedProjectionLoaded,
            );
          },
        ),
        BlocListener<InboxCubit, InboxState>(
          listenWhen: (previous, current) =>
              previous.items != current.items ||
              previous.status != current.status ||
              previous.projectionLoaded != current.projectionLoaded ||
              previous.projectionFailed != current.projectionFailed,
          listener: (context, state) {
            context.read<HomeActivationCubit>().reportInbox(
              accountId: accountId,
              inboxItemCount: state.items.length,
              inboxLoaded: state.isSuccess && state.projectionLoaded,
              inboxFailed: state.projectionFailed,
            );
          },
        ),
      ],
      child: child,
    );
  }
}
