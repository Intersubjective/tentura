import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';

import 'package:tentura/domain/entity/likable.dart';
import 'package:tentura/ui/widget/tentura_icons.dart';

import '../bloc/like_cubit.dart';

class LikeControl extends StatelessWidget {
  const LikeControl({
    required this.entity,
    super.key,
  });

  final Likable entity;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final likeCubit = GetIt.I<LikeCubit>();
    return RepaintBoundary(
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(32),
          color: theme.colorScheme.surface,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(TenturaIcons.arrowUp),
              onPressed: () => likeCubit.incrementLike(entity),
            ),
            BlocSelector<LikeCubit, LikeState, int>(
              key: ValueKey(entity),
              bloc: likeCubit,
              selector: (state) => state.likes[entity.id] ?? entity.votes,
              builder: (context, state) => Text(
                state.toString(),
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.primary,
                ),
              ),
            ),
            IconButton(
              icon: const Icon(TenturaIcons.arrowDown),
              onPressed: () => likeCubit.decrementLike(entity),
            ),
          ],
        ),
      ),
    );
  }
}
