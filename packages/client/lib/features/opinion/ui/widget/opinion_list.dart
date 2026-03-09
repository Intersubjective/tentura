import 'dart:async';
import 'package:flutter/material.dart';

import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/utils/ui_utils.dart';

import '../bloc/opinion_cubit.dart';
import 'opinion_tile.dart';

class OpinionList extends StatelessWidget {
  const OpinionList({super.key});

  @override
  Widget build(BuildContext context) => BlocBuilder<OpinionCubit, OpinionState>(
    buildWhen: (_, c) => c.isSuccess,
    builder: (_, state) => state.opinions.isEmpty
        ? SliverFillRemaining(
            hasScrollBody: false,
            child: Center(
              child: Text(
                L10n.of(context)!.noOpinions,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ),
          )
        : SliverList.separated(
            key: ValueKey(state.opinions),
            itemCount: state.opinions.length,
            itemBuilder: (_, i) {
              final opinion = state.opinions[i];
              if (i == state.opinions.length - 1 && !state.hasReachedMax) {
                unawaited(context.read<OpinionCubit>().fetch());
              }
              return OpinionTile(
                key: ValueKey(opinion),
                isMine: state.checkIfIsMine(opinion),
                opinion: opinion,
              );
            },
            separatorBuilder: separatorBuilder,
          ),
  );
}
