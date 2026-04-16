import 'package:flutter/material.dart';

import 'package:tentura/features/home/ui/bloc/new_stuff_cubit.dart';

/// My Work tab icon with optional new-activity dot (see [NewStuffCubit]).
class MyWorkNavbarItem extends StatelessWidget {
  const MyWorkNavbarItem({super.key, this.selected = false});

  final bool selected;

  @override
  Widget build(BuildContext context) =>
      BlocBuilder<NewStuffCubit, NewStuffState>(
        buildWhen: (p, c) =>
            p.myWorkLastSeenMs != c.myWorkLastSeenMs ||
            p.maxMyWorkActivityMs != c.maxMyWorkActivityMs ||
            p.activeHomeTabIndex != c.activeHomeTabIndex,
        builder: (context, _) {
          final show = context.read<NewStuffCubit>().hasNewMyWorkDot;
          final scheme = Theme.of(context).colorScheme;
          return Badge(
            isLabelVisible: show,
            backgroundColor: scheme.primary,
            child: Icon(selected ? Icons.work : Icons.work_outline),
          );
        },
      );
}
