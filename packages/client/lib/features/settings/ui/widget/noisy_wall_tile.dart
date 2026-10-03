import 'dart:async';

import 'package:flutter/material.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/ui/l10n/l10n.dart';

import '../bloc/noisy_wall_cubit.dart';

/// Settings switch for noisy-contact walls in the user's own frame. Hidden
/// until the current value is known, so it never shows a guessed state.
class NoisyWallTile extends StatelessWidget {
  const NoisyWallTile({super.key});

  @override
  Widget build(BuildContext context) => BlocProvider(
    create: (_) {
      final cubit = NoisyWallCubit();
      unawaited(cubit.fetch());
      return cubit;
    },
    child: const _NoisyWallTileBody(),
  );
}

class _NoisyWallTileBody extends StatelessWidget {
  const _NoisyWallTileBody();

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    return BlocSelector<NoisyWallCubit, NoisyWallState, bool?>(
      selector: (state) => state.enabled,
      builder: (context, enabled) {
        if (enabled == null) return const SizedBox.shrink();
        final cubit = context.read<NoisyWallCubit>();
        void toggle() => unawaited(cubit.set(enabled: !enabled));
        return TenturaMenuTile(
          icon: Icons.volume_off_outlined,
          title: l10n.settingsNoisyWall,
          subtitle: l10n.settingsNoisyWallHint,
          opensPage: false,
          onTap: toggle,
          trailing: Switch(
            value: enabled,
            onChanged: (_) => toggle(),
          ),
        );
      },
    );
  }
}
