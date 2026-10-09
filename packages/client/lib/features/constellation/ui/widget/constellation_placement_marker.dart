import 'package:flutter/material.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/ui/l10n/l10n.dart';

enum ConstellationPlacementMarkerStatus { notSaved, saving }

/// Cue on a node whose placement write is slow or did not reach the server.
///
/// A not-saved marker offers Retry and Discard through one toolbar that a
/// plain tap or a secondary tap pins open and a mouse hover reveals, so touch
/// and desktop users both reach it and no action hangs on a long press.
class ConstellationPlacementMarker extends StatefulWidget {
  const ConstellationPlacementMarker({
    required this.status,
    required this.onRetry,
    required this.onDiscard,
    super.key,
  });

  final ConstellationPlacementMarkerStatus status;
  final VoidCallback onRetry;
  final VoidCallback onDiscard;

  @override
  State<ConstellationPlacementMarker> createState() =>
      _ConstellationPlacementMarkerState();
}

class _ConstellationPlacementMarkerState
    extends State<ConstellationPlacementMarker> {
  bool _hovered = false;
  bool _pinned = false;

  void _pin() => setState(() => _pinned = true);

  void _togglePinned() => setState(() => _pinned = !_pinned);

  void _choose(VoidCallback action) {
    setState(() {
      _hovered = false;
      _pinned = false;
    });
    action();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    if (widget.status == ConstellationPlacementMarkerStatus.saving) {
      final label = l10n.constellationPlacementSaving;
      return Semantics(
        container: true,
        liveRegion: true,
        label: label,
        child: ExcludeSemantics(
          child: _PlacementBadge(
            icon: Icons.sync,
            label: label,
            tone: TenturaTone.neutral,
            busy: true,
          ),
        ),
      );
    }
    final label = l10n.constellationPlacementNotSaved;
    final showActions = _hovered || _pinned;
    return Semantics(
      container: true,
      button: true,
      label: label,
      onTap: _togglePinned,
      child: TapRegion(
        onTapOutside: _pinned ? (_) => setState(() => _pinned = false) : null,
        child: MouseRegion(
          onEnter: (_) => setState(() => _hovered = true),
          onExit: (_) => setState(() => _hovered = false),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (showActions)
                _PlacementActions(
                  onRetry: () => _choose(widget.onRetry),
                  onDiscard: () => _choose(widget.onDiscard),
                ),
              ExcludeSemantics(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: _togglePinned,
                  onSecondaryTap: _pin,
                  child: _PlacementBadge(
                    icon: Icons.cloud_off_outlined,
                    label: label,
                    tone: TenturaTone.warn,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PlacementBadge extends StatelessWidget {
  const _PlacementBadge({
    required this.icon,
    required this.label,
    required this.tone,
    this.busy = false,
  });

  final IconData icon;
  final String label;
  final TenturaTone tone;

  /// Shows progress in place of [icon] while the server is still answering.
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final tt = context.tt;
    final scheme = Theme.of(context).colorScheme;
    final color = switch (tone) {
      TenturaTone.warn => tt.warn,
      _ => tt.textMuted,
    };
    return _PlacementPlate(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: tt.graphLabelMaxWidthRequest),
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: tt.iconTextGap,
            vertical: tt.tightGap,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (busy)
                SizedBox.square(
                  dimension: tt.iconSize * 0.85,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: color,
                  ),
                )
              else
                Icon(icon, size: tt.iconSize * 0.85, color: color),
              SizedBox(width: tt.tightGap),
              Flexible(
                child: Text(
                  label,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TenturaText.labelSmall(scheme.onSurface),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PlacementActions extends StatelessWidget {
  const _PlacementActions({required this.onRetry, required this.onDiscard});

  final VoidCallback onRetry;
  final VoidCallback onDiscard;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    return Padding(
      padding: EdgeInsets.only(bottom: context.tt.tightGap),
      child: _PlacementPlate(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            TenturaTextAction(
              label: l10n.constellationPlacementRetry,
              onPressed: onRetry,
              minInteractive: true,
            ),
            TenturaTextAction(
              label: l10n.constellationPlacementDiscard,
              onPressed: onDiscard,
              tone: TenturaTone.danger,
              minInteractive: true,
            ),
          ],
        ),
      ),
    );
  }
}

class _PlacementPlate extends StatelessWidget {
  const _PlacementPlate({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(context.tt.buttonRadius),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: child,
    );
  }
}
