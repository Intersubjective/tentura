import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:tentura/features/home/ui/bloc/home_attention_cubit.dart';

/// My Work tab icon with a live-obligation count badge.
class MyWorkNavbarItem extends StatelessWidget {
  const MyWorkNavbarItem({super.key, this.selected = false});

  final bool selected;

  @override
  Widget build(BuildContext context) =>
      BlocSelector<HomeAttentionCubit, HomeAttentionState, int>(
        selector: (state) =>
            state.showMyWorkObligationBadge ? state.myWorkObligationCount : 0,
        builder: (context, count) {
          final scheme = Theme.of(context).colorScheme;
          final icon = Icon(selected ? Icons.work : Icons.work_outline);
          if (count <= 0) return icon;
          return Badge(
            label: Text('$count'),
            isLabelVisible: true,
            backgroundColor: selected ? scheme.onPrimary : scheme.primary,
            textColor: selected ? scheme.primary : scheme.onPrimary,
            child: icon,
          );
        },
      );
}
