import 'package:flutter/material.dart';

import 'package:tentura/features/home/ui/bloc/new_stuff_cubit.dart';
import 'package:tentura/features/my_work/domain/derive_my_work_cards.dart';

import '../bloc/my_work_cubit.dart';

/// Reports My Work card activity to [NewStuffCubit] at the screen boundary.
class MyWorkNewStuffReporter extends StatelessWidget {
  const MyWorkNewStuffReporter({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return BlocListener<MyWorkCubit, MyWorkState>(
      listenWhen: (p, c) =>
          c.isSuccess &&
          (p.nonArchivedCards != c.nonArchivedCards ||
              p.archivedCards != c.archivedCards),
      listener: (context, state) {
        context.read<NewStuffCubit>().reportMyWorkActivity(
          maxMyWorkDeskActivityEpochMs(
            nonArchivedCards: state.nonArchivedCards,
            archivedCards: state.archivedCards,
          ),
        );
      },
      child: child,
    );
  }
}
