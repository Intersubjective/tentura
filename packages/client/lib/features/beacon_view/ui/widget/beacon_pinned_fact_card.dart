import 'dart:async';

import 'package:flutter/material.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/beacon_fact_card.dart';
import 'package:tentura/domain/entity/beacon_fact_card_consts.dart';
import 'package:tentura/domain/entity/room_message_attachment.dart';
import 'package:tentura/features/beacon_threads/ui/widget/room_attachment_widgets.dart';
import 'package:tentura/features/beacon_threads/ui/widget/room_file_attachment_open.dart';
import 'package:tentura/features/beacon_threads/ui/widget/room_pinned_fact_visibility_mark.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/widget/tentura_selection_area.dart';
import 'package:tentura/ui/widget/url_link_annotations.dart';
import 'package:tentura/features/beacon_threads/ui/widget/room_message_trailing_meta_layout.dart';

/// Full-width pinned-fact card for the facts sheet (intrinsic height).
class BeaconPinnedFactCard extends StatelessWidget {
  const BeaconPinnedFactCard({
    required this.fact,
    required this.l10n,
    this.isNew = false,
    this.onManage,
    super.key,
  });

  final BeaconFactCard fact;
  final L10n l10n;
  final bool isNew;
  final VoidCallback? onManage;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final tt = context.tt;
    final images = _imageAttachments(fact);
    final files = _fileAttachments(fact);
    final hasText = fact.factText.trim().isNotEmpty;
    final corrected = fact.status == BeaconFactCardStatusBits.corrected;
    final desktopSelection = tenturaDesktopSelectionEnabledFor(
      Theme.of(context),
    );

    final touchTapEnabled =
        onManage != null &&
        !desktopSelection &&
        (hasText || images.isEmpty && files.isEmpty);

    return Material(
      color: scheme.surfaceContainerHighest.withValues(alpha: 0.4),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(TenturaRadii.cardDense),
        side: BorderSide(color: scheme.outlineVariant),
      ),
      clipBehavior: Clip.hardEdge,
      child: InkWell(
        onLongPress: onManage,
        onTap: touchTapEnabled ? onManage : null,
        onSecondaryTap: desktopSelection ? onManage : null,
        child: Padding(
          padding: tt.cardPadding,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(
                    child: RoomPinnedFactVisibilityMark(
                      visibility: fact.visibility,
                      compact: true,
                    ),
                  ),
                  if (isNew)
                    TenturaStatusText(
                      l10n.beaconPinnedFactNewBadge,
                      tone: TenturaTone.info,
                    ),
                ],
              ),
              SizedBox(height: tt.rowGap / 2),
              if (images.isNotEmpty)
                _FactCardImageZone(images: images),
              if (images.isNotEmpty &&
                  (hasText || files.isNotEmpty || corrected))
                SizedBox(height: tt.rowGap),
              if (hasText)
                TenturaSelectionArea(
                  child: Text.rich(
                    buildRoomMessageAnnotatedBodySpan(
                      data: fact.factText,
                      textStyle: TenturaText.bodyMedium(scheme.onSurface),
                      annotations: buildUrlAnnotations(linkColor: tt.info),
                    ),
                    maxLines: 6,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              if (hasText && (files.isNotEmpty || corrected))
                SizedBox(height: tt.rowGap),
              for (var i = 0; i < files.length; i++) ...[
                if (i > 0) SizedBox(height: tt.rowGap / 2),
                _FactCardFileRow(attachment: files[i], l10n: l10n),
              ],
              if (files.isNotEmpty && corrected) SizedBox(height: tt.rowGap),
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
    );
  }
}

List<RoomMessageAttachment> _imageAttachments(BeaconFactCard fact) =>
    fact.attachments.where((a) => a.isImage && a.imageId.isNotEmpty).toList();

List<RoomMessageAttachment> _fileAttachments(BeaconFactCard fact) =>
    fact.attachments.where((a) => a.isFile).toList();

class _FactCardImageZone extends StatefulWidget {
  const _FactCardImageZone({required this.images});

  final List<RoomMessageAttachment> images;

  @override
  State<_FactCardImageZone> createState() => _FactCardImageZoneState();
}

class _FactCardImageZoneState extends State<_FactCardImageZone> {
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
    _pageController.animateToPage(
      index,
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeInOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final tt = context.tt;
    final items = widget.images;
    final imageH = roomMessageInlineImageAlbumHeight(context);
    final materialL10n = MaterialLocalizations.of(context);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(TenturaRadii.cardDense),
          child: SizedBox(
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
                        child: _FactCardImageNavButton(
                          icon: Icons.chevron_left,
                          tooltip: materialL10n.previousPageTooltip,
                          enabled: _currentPage > 0,
                          onPressed: () => _goTo(_currentPage - 1),
                          scheme: scheme,
                          tt: tt,
                        ),
                      ),
                      Positioned(
                        right: 0,
                        top: 0,
                        bottom: 0,
                        child: _FactCardImageNavButton(
                          icon: Icons.chevron_right,
                          tooltip: materialL10n.nextPageTooltip,
                          enabled: _currentPage < items.length - 1,
                          onPressed: () => _goTo(_currentPage + 1),
                          scheme: scheme,
                          tt: tt,
                        ),
                      ),
                    ],
                  ),
          ),
        ),
        if (items.length > 1) ...[
          SizedBox(height: tt.rowGap / 2),
          Text(
            '${_currentPage + 1}/${items.length}',
            style: theme.textTheme.labelSmall,
          ),
        ],
      ],
    );
  }
}

class _FactCardImageNavButton extends StatelessWidget {
  const _FactCardImageNavButton({
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
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.88),
        elevation: 0,
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        child: IconButton(
          tooltip: tooltip,
          icon: Icon(icon, size: tt.iconSize),
          color: enabled ? scheme.onSurfaceVariant : scheme.outlineVariant,
          onPressed: enabled ? onPressed : null,
          visualDensity: VisualDensity.compact,
          constraints: BoxConstraints(
            minWidth: tt.buttonHeight,
            minHeight: tt.buttonHeight,
          ),
        ),
      ),
    );
  }
}

class _FactCardFileRow extends StatelessWidget {
  const _FactCardFileRow({
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
            size: context.tt.iconSize,
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
