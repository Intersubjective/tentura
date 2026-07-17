import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:tentura/features/home/ui/bloc/home_attention_cubit.dart';

/// My Work tab icon with an attention-derived activity dot.
class MyWorkNavbarItem extends StatelessWidget {
  const MyWorkNavbarItem({super.key, this.selected = false});

  final bool selected;

  @override
  Widget build(BuildContext context) =>
      BlocSelector<HomeAttentionCubit, HomeAttentionState, bool>(
        selector: (state) => state.hasMyWorkDot,
        builder: (context, show) {
          final scheme = Theme.of(context).colorScheme;
          return Badge(
            isLabelVisible: show,
            backgroundColor: scheme.primary,
            child: Icon(selected ? Icons.work : Icons.work_outline),
          );
        },
      );
}
