import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/test_ids.dart';

import 'package:tentura_root/domain/constellation/constellation_anchor.dart';
import '../bloc/constellation_cubit.dart';

/// Pin / Unpin actions for constellation targets (person panel, preview, text).
class ConstellationAnchorTargetButton extends StatelessWidget {
  const ConstellationAnchorTargetButton({
    required this.target,
    this.filled = false,
    super.key,
  });

  final ConstellationAnchorTarget target;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ConstellationCubit, ConstellationState>(
      buildWhen: (previous, current) =>
          previous.placementPhase != current.placementPhase ||
          previous.placementActionsEnabled != current.placementActionsEnabled ||
          previous.graphRevision != current.graphRevision ||
          previous.field != current.field ||
          previous.composition != current.composition,
      builder: (context, state) {
        final cubit = context.read<ConstellationCubit>();
        final l10n = L10n.of(context)!;
        final anchored = cubit.isAnchored(target);
        final enabled =
            cubit.placementActionsEnabled && cubit.canPinTarget(target);
        final onPressed = enabled
            ? () {
                if (anchored) {
                  unawaited(cubit.unpinAnchor(target: target));
                } else {
                  unawaited(cubit.pinFromText(target: target));
                }
              }
            : null;
        final label = anchored ? l10n.constellationUnpinTarget : l10n.constellationPinTarget;
        final testId =
            anchored ? TestIds.constellationUnpinTarget : TestIds.constellationPinTarget;

        if (filled) {
          return Semantics(
            identifier: testId,
            button: true,
            child: FilledButton.icon(
              key: TestIds.key(testId),
              onPressed: onPressed,
              icon: Icon(anchored ? Icons.push_pin_outlined : Icons.push_pin),
              label: Text(label),
            ),
          );
        }
        return Semantics(
          identifier: testId,
          button: true,
          child: OutlinedButton.icon(
            key: TestIds.key(testId),
            onPressed: onPressed,
            icon: Icon(anchored ? Icons.push_pin_outlined : Icons.push_pin),
            label: Text(label),
          ),
        );
      },
    );
  }
}
