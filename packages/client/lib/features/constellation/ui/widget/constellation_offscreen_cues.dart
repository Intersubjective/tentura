import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/features/graph/domain/entity/node_details.dart';
import 'package:tentura/ui/l10n/l10n.dart';

import '../../domain/constellation_offscreen_cues.dart';
import '../bloc/constellation_cubit.dart';

typedef ConstellationOffscreenRevealCallback =
    void Function(NodeDetails node, ConstellationOffscreenSide side);

/// Directional arrows on the Field safe viewport when nodes lie fully off-screen.
class ConstellationOffscreenCues extends StatelessWidget {
  const ConstellationOffscreenCues({
    required this.cubit,
    required this.viewportInsets,
    required this.visible,
    required this.gestureHiddenListenable,
    required this.onReveal,
    super.key,
  });

  final ConstellationCubit cubit;
  final EdgeInsets viewportInsets;
  final bool visible;
  final ValueListenable<bool> gestureHiddenListenable;
  final ConstellationOffscreenRevealCallback onReveal;

  static const _minButtonSize = 48.0;

  @override
  Widget build(BuildContext context) {
    if (!visible) {
      return const SizedBox.shrink();
    }
    return ValueListenableBuilder<bool>(
      valueListenable: gestureHiddenListenable,
      builder: (context, hidden, _) {
        if (hidden) {
          return const SizedBox.shrink();
        }
        return ListenableBuilder(
          listenable: Listenable.merge([
            cubit.graphController,
            cubit.graphController.cameraRevision,
          ]),
          builder: (context, _) {
            final snapshot = cubit.fieldOffscreenCues(insets: viewportInsets);
            if (!snapshot.hasAny) {
              return const SizedBox.shrink();
            }
            final tt = context.tt;
            final size = math.max(tt.buttonHeight, _minButtonSize);
            final buttonConstraints = BoxConstraints.tightFor(
              width: size,
              height: size,
            );
            final inset = tt.tightGap;
            return LayoutBuilder(
              builder: (context, constraints) {
                final w = constraints.maxWidth;
                final h = constraints.maxHeight;
                return Stack(
                  clipBehavior: Clip.none,
                  children: [
                    if (snapshot.left > 0)
                      Positioned(
                        left: inset,
                        top: (h - size) / 2,
                        child: _OffscreenCueButton(
                          side: ConstellationOffscreenSide.left,
                          count: snapshot.left,
                          constraints: buttonConstraints,
                          onPressed: () => _reveal(
                            context,
                            ConstellationOffscreenSide.left,
                          ),
                        ),
                      ),
                    if (snapshot.right > 0)
                      Positioned(
                        right: inset,
                        top: (h - size) / 2,
                        child: _OffscreenCueButton(
                          side: ConstellationOffscreenSide.right,
                          count: snapshot.right,
                          constraints: buttonConstraints,
                          onPressed: () => _reveal(
                            context,
                            ConstellationOffscreenSide.right,
                          ),
                        ),
                      ),
                    if (snapshot.above > 0)
                      Positioned(
                        top: inset,
                        left: (w - size) / 2,
                        child: _OffscreenCueButton(
                          side: ConstellationOffscreenSide.above,
                          count: snapshot.above,
                          constraints: buttonConstraints,
                          onPressed: () => _reveal(
                            context,
                            ConstellationOffscreenSide.above,
                          ),
                        ),
                      ),
                    if (snapshot.below > 0)
                      Positioned(
                        bottom: inset,
                        left: (w - size) / 2,
                        child: _OffscreenCueButton(
                          side: ConstellationOffscreenSide.below,
                          count: snapshot.below,
                          constraints: buttonConstraints,
                          onPressed: () => _reveal(
                            context,
                            ConstellationOffscreenSide.below,
                          ),
                        ),
                      ),
                  ],
                );
              },
            );
          },
        );
      },
    );
  }

  void _reveal(BuildContext context, ConstellationOffscreenSide side) {
    final target = cubit.fieldOffscreenRevealTarget(
      side,
      insets: viewportInsets,
    );
    if (target == null) {
      return;
    }
    onReveal(target, side);
  }
}

class _OffscreenCueButton extends StatelessWidget {
  const _OffscreenCueButton({
    required this.side,
    required this.count,
    required this.constraints,
    required this.onPressed,
  });

  final ConstellationOffscreenSide side;
  final int count;
  final BoxConstraints constraints;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    final (icon, label, key) = switch (side) {
      ConstellationOffscreenSide.left => (
        Icons.keyboard_arrow_left,
        l10n.constellationOffscreenLeft(count),
        const Key('constellation.offscreen.left'),
      ),
      ConstellationOffscreenSide.right => (
        Icons.keyboard_arrow_right,
        l10n.constellationOffscreenRight(count),
        const Key('constellation.offscreen.right'),
      ),
      ConstellationOffscreenSide.above => (
        Icons.keyboard_arrow_up,
        l10n.constellationOffscreenAbove(count),
        const Key('constellation.offscreen.above'),
      ),
      ConstellationOffscreenSide.below => (
        Icons.keyboard_arrow_down,
        l10n.constellationOffscreenBelow(count),
        const Key('constellation.offscreen.below'),
      ),
    };
    return Semantics(
      button: true,
      label: label,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          IconButton.filledTonal(
            key: key,
            tooltip: label,
            onPressed: onPressed,
            constraints: constraints,
            icon: Icon(icon),
          ),
          Positioned(
            top: 2,
            right: 2,
            child: TenturaCountBadge(
              count: count,
              backgroundColor: scheme.primary,
            ),
          ),
        ],
      ),
    );
  }
}
