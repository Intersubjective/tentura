import 'dart:async';
import 'dart:ui' show Offset;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:force_directed_graphview/force_directed_graphview.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/features/graph/domain/entity/node_details.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/test_ids.dart';

import '../../domain/entity/constellation_anchor.dart';
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

/// Wraps [GraphPersonContextPanel] with constellation pin/unpin without editing it.
class ConstellationPersonContextDecorator extends StatelessWidget {
  const ConstellationPersonContextDecorator({
    required this.personId,
    required this.child,
    super.key,
  });

  final String personId;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final tt = context.tt;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        child,
        SizedBox(height: tt.rowGap),
        ConstellationAnchorTargetButton(
          target: ConstellationAnchorTarget.person(personId),
        ),
      ],
    );
  }
}

/// Map-only Pin here / Cancel overlay during [ConstellationPlacementPhase.provisionalNew].
class ConstellationProvisionalPlacementBar extends StatelessWidget {
  const ConstellationProvisionalPlacementBar({
    required this.controller,
    super.key,
  });

  final GraphController<NodeDetails, dynamic> controller;

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ConstellationCubit, ConstellationState>(
      buildWhen: (previous, current) =>
          previous.placementPhase != current.placementPhase ||
          previous.activePlacementTarget != current.activePlacementTarget,
      builder: (context, state) {
        if (state.placementPhase != ConstellationPlacementPhase.provisionalNew ||
            state.activePlacementTarget == null) {
          return const SizedBox.shrink();
        }
        final cubit = context.read<ConstellationCubit>();
        final l10n = L10n.of(context)!;
        final tt = context.tt;
        final target = state.activePlacementTarget!;

        return SafeArea(
          top: false,
          child: Padding(
            padding: EdgeInsets.all(tt.screenHPadding),
            child: Material(
              elevation: 4,
              borderRadius: BorderRadius.circular(tt.cardRadius),
              color: Theme.of(context).colorScheme.surfaceContainerHigh,
              child: Padding(
                padding: tt.cardPadding,
                child: Row(
                  children: [
                    Expanded(
                      child: FilledButton(
                        key: TestIds.key(TestIds.constellationPinHere),
                        onPressed: () {
                          final centre = _sceneCentreForTarget(
                            controller: controller,
                            target: target,
                          );
                          if (centre == null) {
                            return;
                          }
                          unawaited(
                            cubit.confirmProvisionalPin(
                              target: target,
                              sceneCentre: centre,
                            ),
                          );
                        },
                        child: Text(l10n.constellationPinHere),
                      ),
                    ),
                    SizedBox(width: tt.rowGap),
                    Expanded(
                      child: OutlinedButton(
                        key: TestIds.key(TestIds.constellationCancelPlacement),
                        onPressed: cubit.cancelPlacement,
                        child: Text(l10n.constellationCancelPlacement),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Offset? _sceneCentreForTarget({
    required GraphController<NodeDetails, dynamic> controller,
    required ConstellationAnchorTarget target,
  }) {
    for (final node in controller.nodes) {
      if (node.id != target.graphNodeId) {
        continue;
      }
      if (node is! NodeDetails) {
        return null;
      }
      return controller.getPosition(node);
    }
    return null;
  }
}
