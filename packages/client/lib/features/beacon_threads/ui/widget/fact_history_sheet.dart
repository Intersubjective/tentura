import 'dart:async';

import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/beacon_activity_event_consts.dart';
import 'package:tentura/domain/entity/beacon_fact_card_consts.dart';
import 'package:tentura/domain/entity/beacon_fact_history_entry.dart';
import 'package:tentura/features/beacon_threads/data/repository/beacon_fact_card_repository.dart';
import 'package:tentura/features/beacon_threads/domain/util/word_diff.dart';
import 'package:tentura/features/beacon_threads/ui/bloc/fact_history_cubit.dart';
import 'package:tentura/features/beacon_threads/ui/bloc/fact_history_state.dart';
import 'package:tentura/features/beacon_threads/ui/widget/fact_origin_line.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/utils/relative_time.dart';
import 'package:tentura/ui/utils/ui_utils.dart';

/// Opens the fact history sheet (issue #181 plan §3/D2/D5): a modal listing
/// [BeaconFactTimelineEntry] rows newest first, word-diffed against the
/// next older revision, with restore + Undo when [canMutate].
///
/// [highlightSeq] marks that revision (the copied version, plan §6.1). A
/// copy ([originBeaconKind] set) ends with a footer that opens its source.
Future<void> showFactHistorySheet(
  BuildContext context, {
  required String beaconId,
  required String factCardId,
  required int baseRevisionSeq,
  required bool canMutate,
  int? originBeaconKind,
  int? highlightSeq,
  BeaconFactCardRepository? repository,
}) {
  return showTenturaAdaptiveSheet<void>(
    context: context,
    showSnackBars: true,
    useRootNavigator: true,
    limitCompactHeight: true,
    builder: (_) => FactHistorySheet(
      beaconId: beaconId,
      factCardId: factCardId,
      baseRevisionSeq: baseRevisionSeq,
      canMutate: canMutate,
      originBeaconKind: originBeaconKind,
      highlightSeq: highlightSeq,
      repository: repository,
    ),
  );
}

class FactHistorySheet extends StatefulWidget {
  const FactHistorySheet({
    required this.beaconId,
    required this.factCardId,
    required this.baseRevisionSeq,
    required this.canMutate,
    this.originBeaconKind,
    this.highlightSeq,
    this.repository,
    super.key,
  });

  final String beaconId;
  final String factCardId;
  final int baseRevisionSeq;
  final bool canMutate;
  final int? originBeaconKind;
  final int? highlightSeq;
  final BeaconFactCardRepository? repository;

  @override
  State<FactHistorySheet> createState() => _FactHistorySheetState();
}

class _FactHistorySheetState extends State<FactHistorySheet> {
  late final FactHistoryCubit _cubit;

  /// In-sheet Undo host (avoids full-height Scaffold + app SnackBar behind
  /// the modal barrier — see former ScaffoldMessenger comment).
  _HistoryUndoBanner? _undoBanner;

  @override
  void initState() {
    super.initState();
    _cubit = FactHistoryCubit(
      beaconId: widget.beaconId,
      factCardId: widget.factCardId,
      baseRevisionSeq: widget.baseRevisionSeq,
      highlightSeq: widget.highlightSeq,
      repository: widget.repository,
    );
    unawaited(_cubit.load());
  }

  @override
  void dispose() {
    unawaited(_cubit.close());
    super.dispose();
  }

  void _showUndoBanner({
    required String message,
    required String undoLabel,
    required VoidCallback onUndo,
  }) {
    setState(() {
      _undoBanner = _HistoryUndoBanner(
        message: message,
        undoLabel: undoLabel,
        onUndo: () {
          setState(() => _undoBanner = null);
          onUndo();
        },
        onDismiss: () => setState(() => _undoBanner = null),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final scrollBehavior = ScrollConfiguration.of(context);
    return BlocProvider.value(
      value: _cubit,
      child: SafeArea(
        child: BlocBuilder<FactHistoryCubit, FactHistoryState>(
          builder: (context, state) {
            final l10n = L10n.of(context)!;
            final tt = context.tt;
            final entries = state.entries;
            final baselines = _diffBaselines(entries);
            final headSeq = entries
                .whereType<BeaconFactHistoryEntry>()
                .firstOrNull
                ?.seq;
            return CustomScrollView(
              // Fit short histories under the adaptive sheet's height cap.
              shrinkWrap: true,
              scrollBehavior: scrollBehavior.copyWith(
                dragDevices: {
                  ...scrollBehavior.dragDevices,
                  PointerDeviceKind.mouse,
                },
              ),
              slivers: [
                SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.only(
                      left: tt.screenHPadding,
                      right: tt.screenHPadding / 2,
                      top: tt.rowGap,
                      bottom: tt.rowGap / 2,
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            l10n.beaconRoomFactHistorySheetTitle,
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                        ),
                        IconButton(
                          tooltip: l10n.buttonClose,
                          onPressed: () => Navigator.of(context).maybePop(),
                          icon: Icon(Icons.close, size: tt.iconSize),
                        ),
                      ],
                    ),
                  ),
                ),
                SliverPadding(
                  padding: EdgeInsets.only(bottom: tt.rowGap),
                  sliver: SliverList.builder(
                    itemCount: entries.length,
                    itemBuilder: (context, i) {
                      final entry = entries[i];
                      final row = _FactHistoryTimelineRow(
                        entry: entry,
                        olderRevision: baselines[i],
                        canMutate: widget.canMutate,
                        isHead:
                            entry is BeaconFactHistoryEntry &&
                            entry.seq == headSeq,
                        isFirst: i == 0,
                        isLast: i == entries.length - 1,
                        showDividerAbove: i > 0,
                        onShowUndo: _showUndoBanner,
                      );
                      if (entry is! BeaconFactHistoryEntry ||
                          entry.seq != widget.highlightSeq) {
                        return row;
                      }
                      // Mark the copied revision visually and for assistive technology.
                      return Semantics(
                        container: true,
                        selected: true,
                        child: ColoredBox(
                          color: Theme.of(
                            context,
                          ).colorScheme.secondaryContainer,
                          child: row,
                        ),
                      );
                    },
                  ),
                ),
                if (widget.originBeaconKind != null)
                  SliverToBoxAdapter(
                    child: _EarlierHistoryFooter(
                      beaconId: widget.beaconId,
                      factCardId: widget.factCardId,
                    ),
                  ),
                if (_undoBanner case final banner?)
                  SliverToBoxAdapter(child: banner),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _HistoryUndoBanner extends StatelessWidget {
  const _HistoryUndoBanner({
    required this.message,
    required this.undoLabel,
    required this.onUndo,
    required this.onDismiss,
  });

  final String message;
  final String undoLabel;
  final VoidCallback onUndo;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final tt = context.tt;
    return Material(
      color: scheme.inverseSurface,
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: tt.screenHPadding,
          vertical: tt.rowGap / 2,
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                message,
                style: TenturaText.bodySmall(scheme.onInverseSurface),
              ),
            ),
            TextButton(
              onPressed: onUndo,
              child: Text(
                undoLabel,
                style: TenturaText.status(scheme.inversePrimary),
              ),
            ),
            IconButton(
              tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
              onPressed: onDismiss,
              icon: Icon(
                Icons.close,
                size: tt.iconSize,
                color: scheme.onInverseSurface,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// For each index, the nearest strictly-older entry that is a text revision
/// (skipping interposed [BeaconFactHistoryEvent] rows), or `null` for the
/// earliest revision in the loaded page.
List<BeaconFactHistoryEntry?> _diffBaselines(
  List<BeaconFactTimelineEntry> entries,
) {
  final result = List<BeaconFactHistoryEntry?>.filled(entries.length, null);
  for (var i = 0; i < entries.length; i++) {
    for (var j = i + 1; j < entries.length; j++) {
      final candidate = entries[j];
      if (candidate is BeaconFactHistoryEntry) {
        result[i] = candidate;
        break;
      }
    }
  }
  return result;
}

class _FactHistoryTimelineRow extends StatelessWidget {
  const _FactHistoryTimelineRow({
    required this.entry,
    required this.olderRevision,
    required this.canMutate,
    required this.isHead,
    required this.isFirst,
    required this.isLast,
    required this.showDividerAbove,
    required this.onShowUndo,
  });

  final BeaconFactTimelineEntry entry;
  final BeaconFactHistoryEntry? olderRevision;
  final bool canMutate;
  final bool isHead;
  final bool isFirst;
  final bool isLast;
  final bool showDividerAbove;
  final void Function({
    required String message,
    required String undoLabel,
    required VoidCallback onUndo,
  })
  onShowUndo;

  static const double _railWidth = 16;
  static const double _nodeSize = 8;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final tt = context.tt;
    final scheme = Theme.of(context).colorScheme;
    final row = entry;
    final railColor = scheme.outlineVariant;
    final nodeColor = scheme.primary;
    // Dot sits on the first content line (author / event), not mid-row.
    final nodeCenterY = tt.rowGap + _nodeSize / 2;

    return Column(
      mainAxisSize: MainAxisSize.min,
      // Stretch so differently sized bodies share one left rail axis.
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (showDividerAbove)
          Padding(
            padding: EdgeInsets.only(left: tt.screenHPadding + _railWidth),
            child: const TenturaHairlineDivider(),
          ),
        Padding(
          padding: EdgeInsets.symmetric(horizontal: tt.screenHPadding),
          child: Stack(
            children: [
              Positioned(
                left: 0,
                top: 0,
                bottom: 0,
                width: _railWidth,
                child: CustomPaint(
                  painter: _TimelineRailPainter(
                    railColor: railColor,
                    nodeColor: nodeColor,
                    nodeSize: _nodeSize,
                    nodeCenterY: nodeCenterY,
                    drawAbove: !isFirst,
                    drawBelow: !isLast,
                  ),
                ),
              ),
              Padding(
                padding: EdgeInsets.only(
                  left: _railWidth + tt.rowGap,
                  top: tt.rowGap,
                  bottom: tt.rowGap,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (row is BeaconFactHistoryEvent) ...[
                      Text(
                        _eventLabel(l10n, row),
                        style: TenturaText.status(scheme.onSurfaceVariant),
                      ),
                      if (row.type ==
                          BeaconActivityEventTypeBits.factPinned) ...[
                        SizedBox(height: tt.tightGap),
                        Text(
                          l10n.beaconActivityFactPinned,
                          style: TenturaText.status(scheme.onSurfaceVariant),
                        ),
                      ],
                    ] else if (row is BeaconFactHistoryEntry) ...[
                      if (row is! BeaconFactHistoryImported)
                        Text(
                          _authorLabel(l10n, row),
                          style: TenturaText.status(
                            scheme.onSurfaceVariant,
                          ),
                        ),
                      SizedBox(height: tt.tightGap),
                      if (row is BeaconFactHistoryImported)
                        Text(
                          l10n.beaconRoomFactHistoryImportedBaseline,
                          style: TenturaText.status(
                            scheme.onSurfaceVariant,
                          ),
                        )
                      else if (row is BeaconFactHistoryCopied)
                        Text(
                          l10n.beaconRoomFactHistoryBroughtHere(
                            row.actorTitle,
                          ),
                          style: TenturaText.status(
                            scheme.onSurfaceVariant,
                          ),
                        )
                      else if (row is BeaconFactHistoryRestored)
                        Text(
                          l10n.beaconRoomFactHistoryRestoredFrom(
                            row.restoredFromSeq,
                          ),
                          style: TenturaText.status(
                            scheme.onSurfaceVariant,
                          ),
                        ),
                      SizedBox(height: tt.tightGap),
                      _CollapsibleDiffBody(
                        spans: _bodySpans(
                          scheme: scheme,
                          factText: row.factText,
                          olderText: olderRevision?.factText,
                        ),
                      ),
                      if (canMutate && !isHead) ...[
                        SizedBox(height: tt.tightGap),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: TextButton(
                            style: TextButton.styleFrom(
                              padding: EdgeInsets.zero,
                              minimumSize: Size.zero,
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                            onPressed: () =>
                                unawaited(_onRestore(context, row.seq)),
                            child: Text(
                              l10n.beaconRoomFactHistoryRestoreAction,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  String _authorLabel(L10n l10n, BeaconFactHistoryEntry row) {
    final relative = compactRelativeTimeAgo(
      when: row.createdAt,
      now: DateTime.now(),
      l10n: l10n,
    );
    return row.actorTitle.isEmpty ? relative : '${row.actorTitle} · $relative';
  }

  String _eventLabel(L10n l10n, BeaconFactHistoryEvent event) {
    switch (event.type) {
      case BeaconActivityEventTypeBits.factVisibilityChanged:
        final visibility =
            event.visibilityTo == BeaconFactCardVisibilityBits.public
            ? l10n.beaconRoomFactCardVisibilityPublic
            : l10n.beaconRoomFactCardVisibilityChat;
        return l10n.beaconRoomFactHistoryEventVisibilityChanged(
          event.actorTitle,
          visibility,
        );
      case BeaconActivityEventTypeBits.factRemoved:
        return l10n.beaconRoomFactHistoryEventRemoved(event.actorTitle);
      default:
        return event.actorTitle;
    }
  }

  Future<void> _onRestore(BuildContext context, int fromSeq) async {
    final cubit = context.read<FactHistoryCubit>();
    // Restore is only offered on revision rows, so a head revision exists.
    final previousHeadSeq = cubit.state.entries
        .whereType<BeaconFactHistoryEntry>()
        .first
        .seq;

    await cubit.restore(fromSeq);
    if (!context.mounted) return;

    final l10n = L10n.of(context)!;
    if (cubit.state.loadError != null) {
      showSnackBar(
        context,
        text: l10n.beaconRoomFactHistoryRestoreFailed,
        isError: true,
        error: cubit.state.loadError,
      );
      return;
    }

    onShowUndo(
      message: l10n.beaconRoomFactHistoryRestoredSnackbar,
      undoLabel: l10n.beaconRoomFactHistoryUndo,
      onUndo: () => unawaited(cubit.restore(previousHeadSeq)),
    );
  }
}

class _TimelineRailPainter extends CustomPainter {
  _TimelineRailPainter({
    required this.railColor,
    required this.nodeColor,
    required this.nodeSize,
    required this.nodeCenterY,
    required this.drawAbove,
    required this.drawBelow,
  });

  final Color railColor;
  final Color nodeColor;
  final double nodeSize;
  final double nodeCenterY;
  final bool drawAbove;
  final bool drawBelow;

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final nodeY = nodeCenterY.clamp(nodeSize / 2, size.height - nodeSize / 2);
    final railPaint = Paint()
      ..color = railColor
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;
    if (drawAbove) {
      canvas.drawLine(Offset(cx, 0), Offset(cx, nodeY), railPaint);
    }
    if (drawBelow) {
      canvas.drawLine(Offset(cx, nodeY), Offset(cx, size.height), railPaint);
    }
    canvas.drawCircle(
      Offset(cx, nodeY),
      nodeSize / 2,
      Paint()..color = nodeColor,
    );
  }

  @override
  bool shouldRepaint(covariant _TimelineRailPainter oldDelegate) =>
      railColor != oldDelegate.railColor ||
      nodeColor != oldDelegate.nodeColor ||
      nodeSize != oldDelegate.nodeSize ||
      nodeCenterY != oldDelegate.nodeCenterY ||
      drawAbove != oldDelegate.drawAbove ||
      drawBelow != oldDelegate.drawBelow;
}

List<InlineSpan> _bodySpans({
  required ColorScheme scheme,
  required String factText,
  required String? olderText,
}) {
  final baseStyle = TenturaText.body(scheme.onSurface);
  if (olderText == null) {
    return [TextSpan(text: factText, style: baseStyle)];
  }
  final addedStyle = baseStyle.copyWith(
    backgroundColor: scheme.surfaceContainerHighest,
  );
  final removedStyle = TenturaText.body(scheme.onSurfaceVariant).copyWith(
    decoration: TextDecoration.lineThrough,
  );
  return wordDiff(olderText, factText)
      .map((segment) {
        final style = switch (segment.kind) {
          DiffKind.same => baseStyle,
          DiffKind.added => addedStyle,
          DiffKind.removed => removedStyle,
        };
        return TextSpan(text: segment.text, style: style);
      })
      .toList(growable: false);
}

/// Collapses a diffed body past 6 lines behind a 'Show full' control.
///
/// Collapsed state renders a plain-text prefix (not the full [spans] tree
/// clipped by `maxLines`): `Text`/`Text.rich` keep their full string data
/// regardless of visual clipping, so a widget test asserting the tail text
/// is absent needs it actually missing from the tree, not merely clipped.
class _CollapsibleDiffBody extends StatefulWidget {
  const _CollapsibleDiffBody({required this.spans});

  final List<InlineSpan> spans;

  static const int _maxLines = 6;

  @override
  State<_CollapsibleDiffBody> createState() => _CollapsibleDiffBodyState();
}

class _CollapsibleDiffBodyState extends State<_CollapsibleDiffBody>
    with AutomaticKeepAliveClientMixin<_CollapsibleDiffBody> {
  bool _expanded = false;

  @override
  bool get wantKeepAlive => _expanded;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final l10n = L10n.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    final fullSpan = TextSpan(children: widget.spans);
    return LayoutBuilder(
      builder: (context, constraints) {
        final collapsedText = _expanded
            ? null
            : _collapsedPlainText(
                span: fullSpan,
                maxWidth: constraints.maxWidth,
                maxLines: _CollapsibleDiffBody._maxLines,
              );
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (collapsedText != null)
              Text(collapsedText, style: TenturaText.body(scheme.onSurface))
            else
              Text.rich(fullSpan),
            if (collapsedText != null)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  style: TextButton.styleFrom(
                    padding: EdgeInsets.zero,
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  onPressed: () {
                    setState(() => _expanded = true);
                    updateKeepAlive();
                  },
                  child: Text(
                    l10n.beaconRoomFactHistoryShowFull,
                    style: TenturaText.status(scheme.primary),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

/// Plain-text prefix of [span] that fits within [maxLines] at [maxWidth], or
/// `null` when it already fits (nothing to collapse).
String? _collapsedPlainText({
  required InlineSpan span,
  required double maxWidth,
  required int maxLines,
}) {
  if (maxWidth <= 0) return null;
  final painter = TextPainter(
    text: span,
    maxLines: maxLines,
    textDirection: TextDirection.ltr,
  )..layout(maxWidth: maxWidth);
  if (!painter.didExceedMaxLines) return null;

  final fullText = span.toPlainText();
  final cutOffset = painter
      .getPositionForOffset(Offset(maxWidth, painter.height - 1))
      .offset
      .clamp(0, fullText.length);
  if (cutOffset <= 0 || cutOffset >= fullText.length) return null;
  return fullText.substring(0, cutOffset);
}

/// Last row of a copy's history: its earlier history stays with the source.
class _EarlierHistoryFooter extends StatelessWidget {
  const _EarlierHistoryFooter({
    required this.beaconId,
    required this.factCardId,
  });

  final String beaconId;
  final String factCardId;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final tt = context.tt;
    return Padding(
      padding: EdgeInsets.only(
        left: tt.screenHPadding,
        right: tt.screenHPadding / 2,
        bottom: tt.rowGap,
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              l10n.beaconRoomFactHistoryEarlierElsewhere,
              style: TenturaText.status(
                Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          TextButton(
            onPressed: () => unawaited(
              openFactOrigin(
                context,
                beaconId: beaconId,
                factCardId: factCardId,
              ),
            ),
            child: Text(l10n.beaconRoomFactHistoryOpenOrigin),
          ),
        ],
      ),
    );
  }
}
