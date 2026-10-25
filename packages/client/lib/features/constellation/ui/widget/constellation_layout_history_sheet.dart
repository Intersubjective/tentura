import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/ui/l10n/l10n.dart';

import '../../domain/entity/constellation_layout_snapshot.dart';
import '../bloc/constellation_cubit.dart';

Future<void> showConstellationLayoutHistorySheet(
  BuildContext context, {
  required ConstellationCubit cubit,
}) async {
  await showTenturaAdaptiveSheet<void>(
    context: context,
    builder: (_) => ConstellationLayoutHistorySheet(cubit: cubit),
  );
  cubit.cancelLayoutPreview();
}

class ConstellationLayoutHistorySheet extends StatefulWidget {
  const ConstellationLayoutHistorySheet({required this.cubit, super.key});
  final ConstellationCubit cubit;

  @override
  State<ConstellationLayoutHistorySheet> createState() => _HistoryState();
}

class _HistoryState extends State<ConstellationLayoutHistorySheet> {
  late final _snapshots = widget.cubit.listLayoutSnapshots();
  ConstellationLayoutSnapshot? _selected;
  bool _restoring = false;
  Object? _error;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final tt = context.tt;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.all(tt.screenHPadding),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              l10n.constellationLayoutHistory,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            Flexible(
              child: FutureBuilder<List<ConstellationLayoutSnapshot>>(
                future: _snapshots,
                builder: (context, result) {
                  if (result.hasError) {
                    return Text(l10n.constellationResetPositionsFailed);
                  }
                  final snapshots = result.data;
                  if (snapshots == null) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  final ordered = [...snapshots]
                    ..sort((a, b) {
                      final kind = a.kind.compareTo(b.kind);
                      return kind != 0
                          ? kind
                          : b.createdAt.compareTo(a.createdAt);
                    });
                  return ListView(
                    shrinkWrap: true,
                    children: [
                      for (final snapshot in ordered)
                        ListTile(
                          selected: _selected?.id == snapshot.id,
                          enabled: !_restoring,
                          leading: ConstellationLayoutThumbnail(
                            snapshot: snapshot,
                          ),
                          title: Text(
                            snapshot.kind == 0
                                ? l10n.constellationFavouriteLayout
                                : MaterialLocalizations.of(
                                    context,
                                  ).formatMediumDate(
                                    snapshot.createdAt.toLocal(),
                                  ),
                          ),
                          onTap: () {
                            setState(() => _selected = snapshot);
                            widget.cubit.previewLayout(snapshot);
                          },
                        ),
                    ],
                  );
                },
              ),
            ),
            if (_error != null) Text(l10n.constellationResetPositionsFailed),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: _restoring
                      ? null
                      : () => Navigator.of(context).pop(),
                  child: Text(l10n.buttonCancel),
                ),
                FilledButton(
                  onPressed: _selected == null || _restoring
                      ? null
                      : () async {
                          setState(() {
                            _restoring = true;
                            _error = null;
                          });
                          try {
                            if (await widget.cubit.restoreLayout(_selected!) &&
                                context.mounted) {
                              Navigator.of(context).pop();
                              return;
                            }
                          } on Object catch (error) {
                            if (mounted) setState(() => _error = error);
                          }
                          if (mounted) setState(() => _restoring = false);
                        },
                  child: Text(l10n.constellationRestoreLayout),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// A saved layout's painted, revision-free coordinates.
class ConstellationLayoutThumbnail extends StatelessWidget {
  const ConstellationLayoutThumbnail({required this.snapshot, super.key});
  final ConstellationLayoutSnapshot snapshot;

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: context.tt.avatarSize,
    child: CustomPaint(
      painter: _SnapshotPainter(
        snapshot,
        Theme.of(context).colorScheme.primary,
      ),
    ),
  );
}

class _SnapshotPainter extends CustomPainter {
  const _SnapshotPainter(this.snapshot, this.color);
  final ConstellationLayoutSnapshot snapshot;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final points = [
      Offset.zero,
      for (final p in snapshot.anchors.values) Offset(p.xUnits, p.yUnits),
    ];
    var extent = 1.0;
    for (final p in points) {
      extent = math.max(extent, math.max(p.dx.abs(), p.dy.abs()));
    }
    final scale = size.shortestSide * 0.4 / extent;
    final paint = Paint()..color = color;
    for (final p in points) {
      canvas.drawCircle(
        size.center(Offset.zero) + p * scale,
        size.shortestSide * 0.04,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_SnapshotPainter oldDelegate) =>
      oldDelegate.snapshot != snapshot || oldDelegate.color != color;
}
