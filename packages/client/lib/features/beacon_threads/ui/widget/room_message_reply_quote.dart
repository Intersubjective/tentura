import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import 'package:tentura/design_system/tentura_radii.dart';
import 'package:tentura/design_system/tentura_tokens.dart';
import 'package:tentura/features/beacon_threads/ui/util/room_reply_excerpt.dart';
import 'package:tentura/ui/l10n/l10n.dart';

/// Accent bar width for reply quote blocks (composer banner uses the same value).
const double kRoomReplyQuoteAccentWidth = 3.0;

/// Touch/stylus/mouse devices the quote jump tap listens on.
const Set<PointerDeviceKind> kRoomReplyQuoteTapDevices = {
  PointerDeviceKind.touch,
  PointerDeviceKind.stylus,
  PointerDeviceKind.mouse,
};

/// Accepts on [handleTapDown] so a single tap wins over the bubble's
/// [DoubleTapGestureRecognizer] (quick-react) and [TapGestureRecognizer]
/// (open linked item) without waiting for double-tap disambiguation.
class _EagerTapGestureRecognizer extends TapGestureRecognizer {
  _EagerTapGestureRecognizer({super.supportedDevices});

  @override
  void handleTapDown({required PointerDownEvent down}) {
    super.handleTapDown(down: down);
    resolve(GestureDisposition.accepted);
  }
}

/// Inner padding for the quote inset behind author + excerpt text.
EdgeInsets roomReplyQuoteInnerPadding(TenturaTokens tt) => EdgeInsets.symmetric(
  horizontal: tt.iconTextGap,
  vertical: tt.iconTextGap / 2,
);

/// Minimum content width for a reply quote, including accent bar, gap, and inset.
double measureRoomReplyQuoteMinContentWidth({
  required String authorName,
  required String excerpt,
  required double availableWidth,
  required TextStyle? nameStyle,
  required TextStyle? excerptStyle,
  required TextDirection textDirection,
  required TextScaler textScaler,
  required TenturaTokens tt,
  bool showAuthor = true,
}) {
  final innerPadding = roomReplyQuoteInnerPadding(tt);
  final chrome =
      kRoomReplyQuoteAccentWidth + tt.iconTextGap + innerPadding.horizontal;
  final textMaxWidth = (availableWidth - chrome).clamp(0.0, double.infinity);

  var textWidth = 0.0;
  if (showAuthor && authorName.isNotEmpty && nameStyle != null) {
    final namePainter = TextPainter(
      text: TextSpan(text: authorName, style: nameStyle),
      textDirection: textDirection,
      textScaler: textScaler,
      maxLines: 1,
    )..layout(maxWidth: textMaxWidth);
    textWidth = namePainter.size.width;
  }

  if (excerptStyle != null) {
    final excerptPainter = TextPainter(
      text: TextSpan(text: excerpt, style: excerptStyle),
      textDirection: textDirection,
      textScaler: textScaler,
      maxLines: 2,
    )..layout(maxWidth: textMaxWidth);
    if (excerptPainter.size.width > textWidth) {
      textWidth = excerptPainter.size.width;
    }
  }

  return textWidth + chrome;
}

/// Quoted parent message inside a reply bubble.
class RoomMessageReplyQuote extends StatelessWidget {
  const RoomMessageReplyQuote({
    required this.authorName,
    required this.excerpt,
    required this.unavailable,
    this.replyToMessageId,
    this.onJumpToReply,
    super.key,
  });

  final String authorName;
  final String excerpt;
  final bool unavailable;
  final String? replyToMessageId;
  final void Function(String messageId)? onJumpToReply;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final tt = context.tt;

    final nameStyle = theme.textTheme.labelSmall?.copyWith(
      fontWeight: FontWeight.w600,
    );
    final excerptStyle = theme.textTheme.bodySmall?.copyWith(
      color: unavailable ? scheme.onSurfaceVariant : null,
    );

    final inset = DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(tt.cardRadius),
      ),
      child: Padding(
        padding: roomReplyQuoteInnerPadding(tt),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!unavailable) ...[
              Text(
                authorName,
                style: nameStyle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              SizedBox(height: tt.iconTextGap / 2),
            ],
            Text(
              excerpt,
              style: excerptStyle,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );

    Widget quoteBody = inset;
    if (!unavailable) {
      final id = replyToMessageId?.trim() ?? '';
      final onJump = onJumpToReply;
      if (id.isNotEmpty && onJump != null) {
        quoteBody = Semantics(
          button: true,
          label: l10n.beaconRoomReplyQuoteA11yLabel(authorName),
          child: RawGestureDetector(
            behavior: HitTestBehavior.opaque,
            gestures: <Type, GestureRecognizerFactory>{
              _EagerTapGestureRecognizer:
                  GestureRecognizerFactoryWithHandlers<
                      _EagerTapGestureRecognizer>(
                    () => _EagerTapGestureRecognizer(
                      supportedDevices: kRoomReplyQuoteTapDevices,
                    ),
                    (recognizer) => recognizer.onTap = () => onJump(id),
                  ),
            },
            child: MouseRegion(
              cursor: SystemMouseCursors.click,
              child: ExcludeSemantics(child: inset),
            ),
          ),
        );
      }
    }

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              color: scheme.primary,
              borderRadius: BorderRadius.circular(TenturaRadii.accentBar),
            ),
            child: const SizedBox(width: kRoomReplyQuoteAccentWidth),
          ),
          SizedBox(width: tt.iconTextGap),
          Expanded(child: quoteBody),
        ],
      ),
    );
  }
}

/// Builds quote display fields from a reply [RoomMessage] snapshot.
({String authorName, String excerpt, bool unavailable}) roomReplyQuoteFields({
  required String? replyToAuthorTitle,
  required String? replyToBodyExcerpt,
  required bool replyToHasAttachments,
  required bool replyTargetUnavailable,
  required L10n l10n,
}) {
  final unavailable = replyTargetUnavailable;
  final authorName = (replyToAuthorTitle ?? '').trim();
  final excerpt = roomReplyExcerptFor(
    excerpt: replyToBodyExcerpt,
    hasAttachments: replyToHasAttachments,
    l10n: l10n,
  );
  return (
    authorName: authorName,
    excerpt: excerpt,
    unavailable: unavailable,
  );
}
