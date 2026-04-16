import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:tentura/features/home/ui/bloc/new_stuff_cubit.dart';

/// Inbox tab icon with optional new-activity dot (see [NewStuffCubit]).
class InboxNavbarItem extends StatelessWidget {
  const InboxNavbarItem({super.key, this.selected = false});

  final bool selected;

  @override
  Widget build(BuildContext context) =>
      BlocBuilder<NewStuffCubit, NewStuffState>(
        buildWhen: (p, c) =>
            p.inboxLastSeenMs != c.inboxLastSeenMs ||
            p.maxInboxActivityMs != c.maxInboxActivityMs ||
            p.activeHomeTabIndex != c.activeHomeTabIndex,
        builder: (context, _) {
          final show = context.read<NewStuffCubit>().hasNewInboxDot;
          final scheme = Theme.of(context).colorScheme;
          return Badge(
            isLabelVisible: show,
            backgroundColor: scheme.primary,
            child: Icon(selected ? Icons.inbox : Icons.inbox_outlined),
          );
        },
      );
}
