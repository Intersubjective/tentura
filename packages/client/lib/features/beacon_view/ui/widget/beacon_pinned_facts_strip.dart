import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/beacon_fact_card.dart';
import 'package:tentura/domain/entity/beacon_fact_card_consts.dart';
import 'package:tentura/domain/entity/room_message_attachment.dart';
import 'package:tentura/features/beacon_room/ui/widget/room_pinned_fact_visibility_mark.dart';
import 'package:tentura/features/beacon_room/ui/widget/room_attachment_widgets.dart';
import 'package:tentura/features/beacon_room/ui/widget/room_file_attachment_open.dart';
import 'package:tentura/features/beacon_view/ui/util/beacon_fact_actions.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/widget/url_link_annotations.dart';
import 'package:tentura/features/beacon_room/ui/widget/room_message_trailing_meta_layout.dart';

const double _kFactStripCardWidth = 160;

/// Collapsible horizontal strip of composite pinned-fact cards on beacon detail.
class BeaconPinnedFactsStrip extends StatefulWidget {
  const BeaconPinnedFactsStrip({
    required this.facts,
    required this.beaconId,
    super.key,
  });

  final List<BeaconFactCard> facts;
  final String beaconId;

  @override
  State<BeaconPinnedFactsStrip> createState() => _BeaconPinnedFactsStripState();
}

class _BeaconPinnedFactsStripState extends State<BeaconPinnedFactsStrip> {
  var _expanded = false;
  final _stripScrollController = ScrollController();

  @override
  void dispose() {
    _stripScrollController.dispose();
    super.dispose();
  }

  void _scrollStripBy(double delta) {
    if (!_stripScrollController.hasClients) return;
    final position = _stripScrollController.position;
    final target = (_stripScrollController.offset + delta).clamp(
      0.0,
      position.maxScrollExtent,
    );
    unawaited(
      _stripScrollController.animateTo(
        target,
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeInOut,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    final tt = context.tt;
    final facts = widget.facts;

    if (facts.isEmpty) {
      return const SizedBox.shrink();
    }

    final stripHeight = _computeStripHeight(context, facts, l10n);

    return Padding(
      padding: EdgeInsets.fromLTRB(
        tt.screenHPadding,
        0,
        tt.screenHPadding,
        tt.rowGap,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Semantics(
            button: true,
            expanded: _expanded,
            label: l10n.beaconItemsFactsFoldTitle,
            child: InkWell(
              onTap: () => setState(() => _expanded = !_expanded),
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: tt.buttonHeight),
                child: Row(
                  children: [
                    Icon(
                      Icons.article_outlined,
                      size: tt.iconSize,
                      color: scheme.onSurfaceVariant,
                    ),
                    SizedBox(width: tt.rowGap),
                    Expanded(
                      child: Text(
                        l10n.beaconItemsFactsFoldTitle,
                        style: TenturaText.bodySmall(scheme.onSurface).copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Icon(
                      _expanded ? Icons.expand_less : Icons.expand_more,
                      size: tt.iconSize,
                      color: scheme.onSurfaceVariant,
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (_expanded) SizedBox(height: tt.rowGap / 2),
          AnimatedSize(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeInOut,
            alignment: Alignment.topCenter,
            child: _expanded
                ? Semantics(
                    label: l10n.beaconPinnedFactCarouselSemanticLabel,
                    child: SizedBox(
                      height: stripHeight,
                      child: facts.length > 1
                          ? _FactStripCarouselWithNav(
                              scrollController: _stripScrollController,
                              onScrollBy: _scrollStripBy,
                              step: _kFactStripCardWidth + tt.sectionGap,
                              previousTooltip:
                                  l10n.beaconPinnedFactCarouselPreviousTooltip,
                              nextTooltip:
                                  l10n.beaconPinnedFactCarouselNextTooltip,
                              child: _buildFactList(
                                facts: facts,
                                stripHeight: stripHeight,
                                l10n: l10n,
                                tt: tt,
                              ),
                            )
                          : _buildFactList(
                              facts: facts,
                              stripHeight: stripHeight,
                              l10n: l10n,
                              tt: tt,
                            ),
                    ),
                  )
                : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }

  Widget _buildFactList({
    required List<BeaconFactCard> facts,
    required double stripHeight,
    required L10n l10n,
    required TenturaTokens tt,
  }) {
    return ListView.separated(
      controller: _stripScrollController,
      scrollDirection: Axis.horizontal,
      physics: const ClampingScrollPhysics(),
      itemCount: facts.length,
      separatorBuilder: (_, _) => SizedBox(width: tt.sectionGap),
      itemBuilder: (context, index) {
        return _FactStripCompositeCard(
          fact: facts[index],
          beaconId: widget.beaconId,
          cardWidth: _kFactStripCardWidth,
          stripHeight: stripHeight,
          l10n: l10n,
        );
      },
    );
  }
}

/// Horizontal carousel with prev/next controls for pointer/desktop navigation.
class _FactStripCarouselWithNav extends StatefulWidget {
  const _FactStripCarouselWithNav({
    required this.scrollController,
    required this.onScrollBy,
    required this.step,
    required this.previousTooltip,
    required this.nextTooltip,
    required this.child,
  });

  final ScrollController scrollController;
  final void Function(double delta) onScrollBy;
  final double step;
  final String previousTooltip;
  final String nextTooltip;
  final Widget child;

  @override
  State<_FactStripCarouselWithNav> createState() =>
      _FactStripCarouselWithNavState();
}

class _FactStripCarouselWithNavState extends State<_FactStripCarouselWithNav> {
  var _canScrollBack = false;
  var _canScrollForward = false;

  @override
  void initState() {
    super.initState();
    widget.scrollController.addListener(_syncNavState);
    WidgetsBinding.instance.addPostFrameCallback((_) => _syncNavState());
  }

  @override
  void didUpdateWidget(covariant _FactStripCarouselWithNav oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.scrollController != widget.scrollController) {
      oldWidget.scrollController.removeListener(_syncNavState);
      widget.scrollController.addListener(_syncNavState);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _syncNavState());
  }

  @override
  void dispose() {
    widget.scrollController.removeListener(_syncNavState);
    super.dispose();
  }

  void _syncNavState() {
    if (!widget.scrollController.hasClients) return;
    final position = widget.scrollController.position;
    final back = position.pixels > position.minScrollExtent + 0.5;
    final forward = position.pixels < position.maxScrollExtent - 0.5;
    if (back == _canScrollBack && forward == _canScrollForward) return;
    setState(() {
      _canScrollBack = back;
      _canScrollForward = forward;
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final tt = context.tt;

    return Stack(
      alignment: Alignment.center,
      children: [
        widget.child,
        Positioned(
          left: 0,
          top: 0,
          bottom: 0,
          child: _FactStripNavButton(
            icon: Icons.chevron_left,
            tooltip: widget.previousTooltip,
            enabled: _canScrollBack,
            onPressed: () => widget.onScrollBy(-widget.step),
            scheme: scheme,
            tt: tt,
          ),
        ),
        Positioned(
          right: 0,
          top: 0,
          bottom: 0,
          child: _FactStripNavButton(
            icon: Icons.chevron_right,
            tooltip: widget.nextTooltip,
            enabled: _canScrollForward,
            onPressed: () => widget.onScrollBy(widget.step),
            scheme: scheme,
            tt: tt,
          ),
        ),
      ],
    );
  }
}

class _FactStripNavButton extends StatelessWidget {
  const _FactStripNavButton({
    required this.icon,
    required this.tooltip,
    required this.enabled,
    required this.onPressed,
    required this.scheme,
    required this.tt,
  });

  final IconData icon;
  final String tooltip;
  final bool enabled;
  final VoidCallback onPressed;
  final ColorScheme scheme;
  final TenturaTokens tt;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Material(
        color: scheme.surface.withValues(alpha: 0.92),
        elevation: 0,
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        child: IconButton(
          tooltip: tooltip,
          icon: Icon(icon, size: tt.iconSize),
          color: enabled ? scheme.onSurfaceVariant : scheme.outlineVariant,
          onPressed: enabled ? onPressed : null,
          constraints: BoxConstraints(
            minWidth: tt.buttonHeight,
            minHeight: tt.buttonHeight,
          ),
        ),
      ),
    );
  }
}

double _computeStripHeight(
  BuildContext context,
  List<BeaconFactCard> facts,
  L10n l10n,
) {
  final tt = context.tt;
  final scaler = MediaQuery.textScalerOf(context);
  final scheme = Theme.of(context).colorScheme;
  final textStyle = TenturaText.bodyMedium(scheme.onSurface);
  final badgeStyle = TenturaText.status(scheme.tertiary);
  final markStyle = TenturaText.status(scheme.onSurfaceVariant);
  final correctedLabel = l10n.beaconRoomFactCardCorrectedBadge;
  final markLabelPublic = l10n.beaconRoomFactCardVisibilityPublic;
  final markLabelPrivate = l10n.beaconRoomFactCardVisibilityChat;
  final cardPadV = tt.cardPadding.vertical;
  final gap = tt.rowGap;
  final innerWidth = _kFactStripCardWidth - tt.cardPadding.horizontal;
  const safetyBuffer = 8.0;

  var maxH = 0.0;
  for (final fact in facts) {
    var h = cardPadV;
    final markLabel = fact.visibility == BeaconFactCardVisibilityBits.public
        ? markLabelPublic
        : markLabelPrivate;
    final markPainter = TextPainter(
      text: TextSpan(text: markLabel, style: markStyle),
      textDirection: Directionality.of(context),
      textScaler: scaler,
      maxLines: 1,
    )..layout(maxWidth: innerWidth);
    h += markPainter.height + gap / 2;

    final images = _imageAttachments(fact);
    final files = _fileAttachments(fact);
    final hasText = fact.factText.trim().isNotEmpty;
    final corrected = fact.status == BeaconFactCardStatusBits.corrected;

    if (images.isNotEmpty) {
      h += innerWidth * 3 / 4;
      if (images.length > 1) {
        final indicatorPainter = TextPainter(
          text: TextSpan(
            text: '${images.length}/${images.length}',
            style: Theme.of(context).textTheme.labelSmall,
          ),
          textDirection: Directionality.of(context),
          textScaler: scaler,
          maxLines: 1,
        )..layout(maxWidth: innerWidth);
        h += gap / 2 + indicatorPainter.height + gap / 2;
      }
      if (hasText || files.isNotEmpty || corrected) {
        h += gap;
      }
    }

    if (hasText) {
      final painter = TextPainter(
        text: TextSpan(text: fact.factText, style: textStyle),
        textDirection: Directionality.of(context),
        textScaler: scaler,
        maxLines: 2,
      )..layout(maxWidth: innerWidth);
      h += painter.height;
      if (files.isNotEmpty || corrected) {
        h += gap;
      }
    }

    for (var i = 0; i < files.length; i++) {
      final filePainter = TextPainter(
        text: TextSpan(text: 'X', style: textStyle),
        textDirection: Directionality.of(context),
        textScaler: scaler,
        maxLines: 1,
      )..layout(maxWidth: innerWidth);
      h += filePainter.height + 4;
      if (i < files.length - 1) {
        h += gap / 2;
      }
    }
    if (files.isNotEmpty && corrected) {
      h += gap;
    }

    if (corrected) {
      final badgePainter = TextPainter(
        text: TextSpan(text: correctedLabel, style: badgeStyle),
        textDirection: Directionality.of(context),
        textScaler: scaler,
        maxLines: 1,
      )..layout(maxWidth: innerWidth);
      h += badgePainter.height;
    }

    maxH = math.max(maxH, h);
  }

  return math.max(maxH + safetyBuffer, innerWidth * 3 / 4 + cardPadV);
}

List<RoomMessageAttachment> _imageAttachments(BeaconFactCard fact) =>
    fact.attachments.where((a) => a.isImage && a.imageId.isNotEmpty).toList();

List<RoomMessageAttachment> _fileAttachments(BeaconFactCard fact) =>
    fact.attachments.where((a) => a.isFile).toList();

class _FactStripCompositeCard extends StatelessWidget {
  const _FactStripCompositeCard({
    required this.fact,
    required this.beaconId,
    required this.cardWidth,
    required this.stripHeight,
    required this.l10n,
  });

  final BeaconFactCard fact;
  final String beaconId;
  final double cardWidth;
  final double stripHeight;
  final L10n l10n;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final tt = context.tt;
    final images = _imageAttachments(fact);
    final files = _fileAttachments(fact);
    final hasText = fact.factText.trim().isNotEmpty;
    final corrected = fact.status == BeaconFactCardStatusBits.corrected;

    return SizedBox(
      width: cardWidth,
      height: stripHeight,
      child: Material(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.4),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(TenturaRadii.cardDense),
          side: BorderSide(color: scheme.outlineVariant),
        ),
        clipBehavior: Clip.hardEdge,
        child: InkWell(
          onLongPress: () => unawaited(
            showBeaconFactActions(
              context,
              beaconId: beaconId,
              fact: fact,
            ),
          ),
          onTap: hasText || images.isEmpty && files.isEmpty
              ? () => unawaited(
                    showBeaconFactActions(
                      context,
                      beaconId: beaconId,
                      fact: fact,
                    ),
                  )
              : null,
          child: Padding(
            padding: tt.cardPadding,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                RoomPinnedFactVisibilityMark(
                  visibility: fact.visibility,
                  compact: true,
                ),
                SizedBox(height: tt.rowGap / 2),
                if (images.isNotEmpty)
                  _FactStripImageZone(
                    images: images,
                    cardWidth: cardWidth - tt.cardPadding.horizontal,
                  ),
                if (images.isNotEmpty &&
                    (hasText || files.isNotEmpty || corrected))
                  SizedBox(height: tt.rowGap),
                Expanded(
                  child: ClipRect(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (hasText)
                          Text.rich(
                            buildRoomMessageAnnotatedBodySpan(
                              data: fact.factText,
                              textStyle:
                                  TenturaText.bodyMedium(scheme.onSurface),
                              annotations:
                                  buildUrlAnnotations(linkColor: tt.info),
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        if (hasText && (files.isNotEmpty || corrected))
                          SizedBox(height: tt.rowGap),
                        for (var i = 0; i < files.length; i++) ...[
                          if (i > 0) SizedBox(height: tt.rowGap / 2),
                          _FactStripFileRow(
                            attachment: files[i],
                            l10n: l10n,
                          ),
                        ],
                        if (files.isNotEmpty && corrected)
                          SizedBox(height: tt.rowGap),
                        if (corrected)
                          Text(
                            l10n.beaconRoomFactCardCorrectedBadge,
                            style: TenturaText.status(scheme.tertiary),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _FactStripImageZone extends StatefulWidget {
  const _FactStripImageZone({
    required this.images,
    required this.cardWidth,
  });

  final List<RoomMessageAttachment> images;
  final double cardWidth;

  @override
  State<_FactStripImageZone> createState() => _FactStripImageZoneState();
}

class _FactStripImageZoneState extends State<_FactStripImageZone> {
  late final PageController _pageController;
  var _currentPage = 0;

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _goTo(int index) {
    unawaited(
      _pageController.animateToPage(
        index,
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeInOut,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final tt = context.tt;
    final items = widget.images;
    final imageH = widget.cardWidth * 3 / 4;
    final materialL10n = MaterialLocalizations.of(context);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(TenturaRadii.cardDense),
          child: SizedBox(
            width: widget.cardWidth,
            height: imageH,
            child: items.length == 1
                ? GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => unawaited(
                      openRoomAttachmentImageAlbum(context, items, 0),
                    ),
                    child: roomAttachmentAlbumThumbnail(context, items.first),
                  )
                : Stack(
                    alignment: Alignment.center,
                    children: [
                      PageView.builder(
                        controller: _pageController,
                        itemCount: items.length,
                        onPageChanged: (i) => setState(() => _currentPage = i),
                        itemBuilder: (ctx, index) {
                          return GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: () => unawaited(
                              openRoomAttachmentImageAlbum(
                                context,
                                items,
                                index,
                              ),
                            ),
                            child: roomAttachmentAlbumThumbnail(
                              ctx,
                              items[index],
                            ),
                          );
                        },
                      ),
                      Positioned(
                        left: 0,
                        top: 0,
                        bottom: 0,
                        child: _FactStripImageNavButton(
                          icon: Icons.chevron_left,
                          tooltip: materialL10n.previousPageTooltip,
                          enabled: _currentPage > 0,
                          onPressed: () => _goTo(_currentPage - 1),
                          scheme: scheme,
                        ),
                      ),
                      Positioned(
                        right: 0,
                        top: 0,
                        bottom: 0,
                        child: _FactStripImageNavButton(
                          icon: Icons.chevron_right,
                          tooltip: materialL10n.nextPageTooltip,
                          enabled: _currentPage < items.length - 1,
                          onPressed: () => _goTo(_currentPage + 1),
                          scheme: scheme,
                        ),
                      ),
                    ],
                  ),
          ),
        ),
        if (items.length > 1) ...[
          SizedBox(height: tt.rowGap / 2),
          Row(
            children: [
              Text(
                '${_currentPage + 1}/${items.length}',
                style: theme.textTheme.labelSmall,
              ),
              SizedBox(width: tt.rowGap / 2),
              Expanded(
                child: Wrap(
                  spacing: tt.rowGap / 4,
                  runSpacing: tt.rowGap / 4,
                  alignment: WrapAlignment.center,
                  children: List.generate(
                    items.length,
                    (index) => GestureDetector(
                      onTap: () => _goTo(index),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        width: _currentPage == index ? 8 : 6,
                        height: _currentPage == index ? 8 : 6,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: _currentPage == index
                              ? scheme.primary
                              : scheme.outlineVariant,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

class _FactStripImageNavButton extends StatelessWidget {
  const _FactStripImageNavButton({
    required this.icon,
    required this.tooltip,
    required this.enabled,
    required this.onPressed,
    required this.scheme,
  });

  final IconData icon;
  final String tooltip;
  final bool enabled;
  final VoidCallback onPressed;
  final ColorScheme scheme;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Material(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.88),
        elevation: 0,
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        child: IconButton(
          tooltip: tooltip,
          icon: Icon(icon, size: 18),
          color: enabled ? scheme.onSurfaceVariant : scheme.outlineVariant,
          onPressed: enabled ? onPressed : null,
          visualDensity: VisualDensity.compact,
          constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
          padding: EdgeInsets.zero,
        ),
      ),
    );
  }
}

class _FactStripFileRow extends StatelessWidget {
  const _FactStripFileRow({
    required this.attachment,
    required this.l10n,
  });

  final RoomMessageAttachment attachment;
  final L10n l10n;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final name = attachment.fileName.trim().isNotEmpty
        ? attachment.fileName
        : l10n.beaconRoomAttachmentUntitled;
    final size = formatRoomAttachmentSize(attachment.sizeBytes);
    final label = size.isEmpty ? name : '$name · $size';

    return InkWell(
      onTap: () => unawaited(openRoomFileAttachment(context, l10n, attachment)),
      child: Row(
        children: [
          Icon(
            Icons.insert_drive_file_outlined,
            color: scheme.onSurfaceVariant,
            size: 20,
          ),
          SizedBox(width: context.tt.rowGap),
          Expanded(
            child: Text(
              label,
              style: TenturaText.bodyMedium(scheme.onSurfaceVariant),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}
