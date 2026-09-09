import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';

import 'package:tentura/design_system/tentura_design_system.dart';

import '../bloc/constellation_cubit.dart';

class ConstellationSnapshotBar extends StatelessWidget {
  const ConstellationSnapshotBar({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ConstellationCubit, ConstellationState>(
      buildWhen: (previous, current) =>
          previous.loadedAt != current.loadedAt ||
          previous.viewMode != current.viewMode,
      builder: (context, state) {
        final loadedAt = state.loadedAt;
        if (loadedAt == null) {
          return const SizedBox.shrink();
        }
        final tt = context.tt;
        final theme = Theme.of(context);
        final local = loadedAt.toLocal();
        final stamp = DateFormat.yMMMd().add_jm().format(local);
        return Material(
          color: theme.colorScheme.surfaceContainerHighest.withValues(
            alpha: 0.92,
          ),
          child: SafeArea(
            bottom: false,
            child: Padding(
              padding: EdgeInsets.symmetric(
                horizontal: tt.screenHPadding,
                vertical: tt.tightGap,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Loaded at $stamp',
                      key: const Key('constellation.snapshot.loaded_at'),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  SegmentedButton<ConstellationViewMode>(
                    key: const Key('constellation.snapshot.view_mode'),
                    segments: const [
                      ButtonSegment(
                        value: ConstellationViewMode.map,
                        label: Text('Map'),
                      ),
                      ButtonSegment(
                        value: ConstellationViewMode.text,
                        label: Text('Text'),
                      ),
                    ],
                    selected: {state.viewMode},
                    onSelectionChanged: (selection) {
                      context.read<ConstellationCubit>().setViewMode(
                        selection.first,
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
