import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/beacon_fact_card.dart';
import 'package:tentura/domain/entity/beacon_fact_card_consts.dart';
import 'package:tentura/domain/entity/room_message_attachment.dart';
import 'package:tentura/features/beacon_room/ui/widget/room_attachment_widgets.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/utils/ui_utils.dart';

const double _kCarouselHorizontalPadding = 2;

/// Horizontal swipe carousel for pinned fact text on compact operational surfaces.
class BeaconPinnedFactCarousel extends StatefulWidget {
  const BeaconPinnedFactCarousel({
    required this.facts,
    required this.factTextStyle,
    this.onManageOverflow,
    this.onOpenFileAttachment,
    this.maxCarouselPageHeight = 280,
    super.key,
  }) : assert(maxCarouselPageHeight > 0, 'maxCarouselPageHeight must be positive');

  final List<BeaconFactCard> facts;

  final TextStyle factTextStyle;

  /// Room: opens fact actions for the **currently visible** fact. Public overview: omit.
  final Future<void> Function(BeaconFactCard fact)? onManageOverflow;

  /// Room: download/share (same attachment ids as room messages). Overview: usually omit.
  final Future<void> Function(RoomMessageAttachment attachment)?
      onOpenFileAttachment;

  /// Long facts scroll inside a viewport no taller than this.
  final double maxCarouselPageHeight;

  @override
  State<BeaconPinnedFactCarousel> createState() =>
      _BeaconPinnedFactCarouselState();
}

class _BeaconPinnedFactCarouselState extends State<BeaconPinnedFactCarousel> {
  late final PageController _pageController;

  var _currentPage = 0;

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
  }

  @override
  void didUpdateWidget(BeaconPinnedFactCarousel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.facts.length != oldWidget.facts.length &&
        widget.facts.isNotEmpty) {
      final maxIdx = widget.facts.length - 1;
      if (_currentPage > maxIdx) {
        _currentPage = maxIdx;
        if (_pageController.hasClients) {
          _pageController.jumpToPage(maxIdx);
        }
      }
    }
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _goTo(int index) {
    if (index < 0 || index >= widget.facts.length) return;
    unawaited(
      _pageController.animateToPage(
        index,
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeInOut,
      ),
    );
  }

  Future<void> _onOverflowPressed() async {
    final cb = widget.onManageOverflow;
    if (cb == null || widget.facts.isEmpty) return;
    await cb(widget.facts[_currentPage]);
  }

  static List<RoomMessageAttachment> _imageAtt(BeaconFactCard f) => f.attachments
      .where((a) => a.isImage && a.imageId.isNotEmpty)
      .toList();

  static List<RoomMessageAttachment> _fileAtt(BeaconFactCard f) =>
      f.attachments.where((a) => a.isFile).toList();

  /// Approximate file chip wrap height (aligned with [ActionChip] density).
  static double _fileAttachmentsHeightEstimate(int n, double contentW) {
    if (n <= 0) return 0;
    const chipMinW = 180.0;
    const rowH = 48.0;
    final perRow = math.max(1, (contentW / chipMinW).floor());
    final rows = (n + perRow - 1) ~/ perRow;
    if (rows <= 1) {
      return rowH;
    }
    return rows * rowH + (rows - 1) * kSpacingSmall;
  }

  static double _attachmentsHeightEstimate(BeaconFactCard f, double contentW) {
    final imgs = _imageAtt(f);
    final files = _fileAtt(f);
    var h = 0.0;

    if (imgs.isNotEmpty) {
      h += kRoomMessageInlineImageAlbumHeight;
      if (imgs.length > 1) {
        h += kSpacingSmall + 40;
      }
    }

    if (files.isNotEmpty) {
      if (imgs.isNotEmpty) {
        h += kSpacingSmall;
      }
      h += _fileAttachmentsHeightEstimate(files.length, contentW);
    }
    return h;
  }

  static double _rawFactBlockHeight(
    BuildContext context,
    BeaconFactCard f,
    double contentWidth,
    TextStyle factTextStyle,
    TextStyle badgeTextStyle,
    String correctedBadgeLabel,
  ) {
    final scaler = MediaQuery.textScalerOf(context);
    final hasText = f.factText.trim().isNotEmpty;
    var h = 0.0;
    if (hasText) {
      final textPainter = TextPainter(
        text: TextSpan(text: f.factText, style: factTextStyle),
        textDirection: Directionality.of(context),
        textScaler: scaler,
      )..layout(maxWidth: math.max(0, contentWidth));
      h += textPainter.height;
    }
    if (f.status == BeaconFactCardStatusBits.corrected) {
      if (hasText) {
        h += kSpacingSmall / 2;
      }
      final badgePainter = TextPainter(
        text: TextSpan(
          text: correctedBadgeLabel,
          style: badgeTextStyle,
        ),
        textDirection: Directionality.of(context),
        textScaler: scaler,
      )..layout(maxWidth: math.max(0, contentWidth));
      h += badgePainter.height;
    }

    final att = _attachmentsHeightEstimate(f, contentWidth);
    final gapBeforeAtt = att > 0 &&
            (hasText || f.status == BeaconFactCardStatusBits.corrected)
        ? kSpacingSmall
        : 0.0;
    return h + gapBeforeAtt + att;
  }

  Widget _factColumn(
    BeaconFactCard f,
    ColorScheme scheme,
    L10n l10n,
  ) {
    final corrected = f.status == BeaconFactCardStatusBits.corrected;
    final hasText = f.factText.trim().isNotEmpty;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (hasText)
          SelectableText(
            f.factText,
            style: widget.factTextStyle,
          ),
        if (corrected) ...[
          SizedBox(height: hasText ? kSpacingSmall / 2 : 0),
          Text(
            l10n.beaconRoomFactCardCorrectedBadge,
            style: TenturaText.status(scheme.tertiary),
          ),
        ],
        if (f.attachments.isNotEmpty)
          Padding(
            padding: EdgeInsets.only(
              top: (hasText || corrected) ? kSpacingSmall : 0,
            ),
            child: RoomPinnedStyleAttachments(
              attachments: f.attachments,
              l10n: l10n,
              onOpenFileAttachment: widget.onOpenFileAttachment,
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final l10n = L10n.of(context)!;
    final items = widget.facts;

    if (items.isEmpty) {
      return const SizedBox.shrink();
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final maxOuterW = constraints.maxWidth;
        final contentW = math
            .max(0, maxOuterW - 2 * _kCarouselHorizontalPadding)
            .toDouble();
        final badgeStyle = TenturaText.status(scheme.tertiary);
        final correctedLabel = l10n.beaconRoomFactCardCorrectedBadge;
        final current = items[_currentPage];
        final rawCurrent = _rawFactBlockHeight(
          context,
          current,
          contentW,
          widget.factTextStyle,
          badgeStyle,
          correctedLabel,
        );
        final viewportH = math.min(rawCurrent, widget.maxCarouselPageHeight);

        return Semantics(
          label: l10n.beaconPinnedFactCarouselSemanticLabel,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (widget.onManageOverflow != null)
                Align(
                  alignment: AlignmentDirectional.centerEnd,
                  child: IconButton(
                    tooltip: l10n.beaconRoomFactOverflowTooltip,
                    icon: const Icon(Icons.more_vert),
                    onPressed: () => unawaited(_onOverflowPressed()),
                  ),
                ),
              AnimatedSize(
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeInOut,
                alignment: Alignment.topCenter,
                child: SizedBox(
                  width: double.infinity,
                  height: viewportH,
                  child: PageView.builder(
                    controller: _pageController,
                    itemCount: items.length,
                    onPageChanged: (i) => setState(() => _currentPage = i),
                    itemBuilder: (ctx, index) {
                      final f = items[index];
                      final raw = _rawFactBlockHeight(
                        context,
                        f,
                        contentW,
                        widget.factTextStyle,
                        badgeStyle,
                        correctedLabel,
                      );
                      final needsScroll = raw > viewportH + 0.5;
                      final inner = Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: _kCarouselHorizontalPadding,
                        ),
                        child: _factColumn(f, scheme, l10n),
                      );
                      if (needsScroll) {
                        return SingleChildScrollView(
                          child: inner,
                        );
                      }
                      return Align(
                        alignment: Alignment.topCenter,
                        child: inner,
                      );
                    },
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(top: kSpacingSmall),
                child: Row(
                  children: [
                    if (items.length > 1) ...[
                      IconButton(
                        tooltip: l10n.beaconPinnedFactCarouselPreviousTooltip,
                        icon: const Icon(Icons.chevron_left),
                        visualDensity: VisualDensity.compact,
                        onPressed: _currentPage > 0
                            ? () => _goTo(_currentPage - 1)
                            : null,
                      ),
                    ] else
                      const SizedBox(width: 4),
                    Expanded(
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            '${_currentPage + 1}/${items.length}',
                            style: theme.textTheme.labelSmall,
                          ),
                          const SizedBox(width: kSpacingSmall),
                          ...List.generate(
                            items.length,
                            (index) {
                              final dot = AnimatedContainer(
                                duration: const Duration(milliseconds: 200),
                                width: _currentPage == index ? 10 : 7,
                                height: _currentPage == index ? 10 : 7,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: _currentPage == index
                                      ? scheme.primary
                                      : scheme.outlineVariant,
                                ),
                              );
                              if (items.length <= 1) {
                                return Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 4,
                                    vertical: 8,
                                  ),
                                  child: dot,
                                );
                              }
                              return Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 4,
                                  vertical: 8,
                                ),
                                child: Semantics(
                                  label: l10n
                                      .beaconPinnedFactCarouselDotSemanticLabel(
                                    index + 1,
                                  ),
                                  button: true,
                                  child: GestureDetector(
                                    onTap: () => _goTo(index),
                                    child: dot,
                                  ),
                                ),
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                    if (items.length > 1) ...[
                      IconButton(
                        tooltip: l10n.beaconPinnedFactCarouselNextTooltip,
                        icon: const Icon(Icons.chevron_right),
                        visualDensity: VisualDensity.compact,
                        onPressed: _currentPage < items.length - 1
                            ? () => _goTo(_currentPage + 1)
                            : null,
                      ),
                    ] else
                      const SizedBox(width: 4),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
