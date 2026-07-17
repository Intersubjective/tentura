import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:tentura/features/home/ui/bloc/home_attention_cubit.dart';

/// Inbox tab icon with an attention-derived activity dot.
class InboxNavbarItem extends StatelessWidget {
  const InboxNavbarItem({super.key, this.selected = false});

  final bool selected;

  @override
  Widget build(BuildContext context) =>
      BlocSelector<HomeAttentionCubit, HomeAttentionState, bool>(
        selector: (state) => state.hasInboxDot,
        builder: (context, show) {
          final scheme = Theme.of(context).colorScheme;
          return Badge(
            isLabelVisible: show,
            backgroundColor: scheme.primary,
            child: Icon(selected ? Icons.inbox : Icons.inbox_outlined),
          );
        },
      );
}
