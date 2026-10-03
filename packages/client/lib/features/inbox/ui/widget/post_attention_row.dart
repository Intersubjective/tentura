import 'package:flutter/material.dart';

import 'package:tentura/consts.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/attention/attention_event_classification.dart';
import 'package:tentura/domain/attention/entity/attention_receipt.dart';
import 'package:tentura/domain/entity/image_entity.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/utils/relative_time.dart';

import '../../domain/entity/inbox_provenance.dart';

/// The `beacon.kind` of a Post; a Request is 0.
const kBeaconKindPost = 1;

/// What the latest directed event says about a Post (M1).
enum PostAttentionVariant { arrival, reply, mention, firstResponses }

/// The variant a grouped Post [receipt] is drawn as, off its latest event.
PostAttentionVariant postAttentionVariantOf(AttentionReceipt receipt) {
  final latest = _latestEvent(receipt);
  if (latest == null) return PostAttentionVariant.arrival;
  if (latest.kind == 'roomMention') return PostAttentionVariant.mention;
  return switch (attentionEventTypeOf(latest.presentationPayloadJson)) {
    'postFirstResponse' => PostAttentionVariant.firstResponses,
    'roomMessagePosted' => PostAttentionVariant.reply,
    _ => PostAttentionVariant.arrival,
  };
}

AttentionReceipt? _latestEvent(AttentionReceipt receipt) {
  AttentionReceipt? latest;
  for (final event in receipt.eventsPreview) {
    if (latest == null || event.createdAt.isAfter(latest.createdAt)) {
      latest = event;
    }
  }
  return latest;
}

/// A Post in the For You stream: lighter than a Request card — one
/// headline by the latest directed event, the root excerpt or the message, and
/// the forward note or the count of further messages (M1).
class PostAttentionRow extends StatelessWidget {
  const PostAttentionRow({
    required this.receipt,
    required this.onOpen,
    required this.onDismiss,
    super.key,
  });

  static const dismissKey = Key('post-attention-row-dismiss');

  final AttentionReceipt receipt;
  final VoidCallback onOpen;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final tt = context.tt;
    final variant = postAttentionVariantOf(receipt);
    final latest = _latestEvent(receipt);
    final authorId = receipt.beaconAuthorId ?? '';
    final author = Profile(
      id: authorId,
      displayName: receipt.beaconAuthorName ?? '',
      image: _imageOf(receipt.beaconAuthorImageId, authorId),
    );
    final authorName = author.shownName.trim();
    final provenance = InboxProvenance.parse(receipt.provenanceJson);
    final note = provenance.latestNoteForward;
    final noteText = (note?.notePreview ?? provenance.strongestNotePreview)
        .trim();
    final sender = provenance.senders
        .where((sender) => sender.notePreview.trim() == noteText)
        .firstOrNull;
    final senderName = (note?.displayName ?? sender?.displayName ?? '').trim();
    final senderId = note?.senderId ?? sender?.id;
    final fromOther =
        senderId != null && senderId != authorId && senderName.isNotEmpty;

    final headline = switch (variant) {
      PostAttentionVariant.arrival =>
        fromOther
            ? l10n.postRowSharedByFrom(authorName, senderName)
            : l10n.postRowSharedBy(authorName),
      PostAttentionVariant.reply => l10n.postRowReplied,
      PostAttentionVariant.mention => l10n.postRowMentioned,
      PostAttentionVariant.firstResponses => l10n.postRowFirstResponses,
    };

    final rootExcerpt = receipt.postRootExcerpt?.trim() ?? '';
    final rootImageId = receipt.postRootImageId ?? '';
    final isMessageVariant =
        variant == PostAttentionVariant.reply ||
        variant == PostAttentionVariant.mention;
    final eventBody = latest?.body.trim() ?? '';
    final body = isMessageVariant && eventBody.isNotEmpty
        ? eventBody
        : rootExcerpt;
    final showThumbnail =
        !isMessageVariant && rootImageId.isNotEmpty && authorId.isNotEmpty;

    final more = (receipt.eventTotal ?? receipt.eventsPreview.length) - 1;
    final footer = switch (variant) {
      PostAttentionVariant.arrival =>
        noteText.isEmpty
            ? null
            : (senderName.isEmpty ? noteText : '$senderName: «$noteText»'),
      PostAttentionVariant.reply || PostAttentionVariant.mention =>
        more > 0 ? l10n.postRowMoreMessages(more) : null,
      PostAttentionVariant.firstResponses => null,
    };

    final age = compactRelativeTimeAgo(
      when: latest?.createdAt ?? receipt.createdAt,
      now: DateTime.now(),
      l10n: l10n,
    );

    return Semantics(
      label: [headline, body, footer].nonNulls.join(', '),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onOpen,
          child: Padding(
            padding: tt.listRowPadding,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TenturaAvatar.medium(profile: author),
                SizedBox(width: tt.avatarTextGap),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        headline,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TenturaText.titleSmall(
                          tt.text,
                        ).copyWith(fontWeight: FontWeight.w500),
                      ),
                      if (body.isNotEmpty || showThumbnail) ...[
                        SizedBox(height: tt.tightGap),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (showThumbnail) ...[
                              _RootThumbnail(
                                url: _imageUrl(authorId, rootImageId),
                              ),
                              SizedBox(width: tt.iconTextGap),
                            ],
                            Expanded(
                              child: Text(
                                body,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: TenturaText.bodyMedium(tt.text),
                              ),
                            ),
                          ],
                        ),
                      ],
                      Row(
                        children: [
                          if (footer != null)
                            Expanded(
                              child: Text(
                                footer,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TenturaText.bodySmall(tt.textMuted),
                              ),
                            )
                          else
                            const Spacer(),
                          SizedBox(width: tt.iconTextGap),
                          Text(
                            age,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TenturaText.withTabular(
                              TenturaText.bodySmall(tt.textMuted),
                            ),
                            semanticsLabel: '',
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                SizedBox(width: tt.tightGap),
                SizedBox(
                  key: dismissKey,
                  width: kMinInteractiveDimension,
                  height: kMinInteractiveDimension,
                  child: IconButton(
                    onPressed: onDismiss,
                    tooltip: l10n.attentionEventDismiss,
                    iconSize: tt.iconSize,
                    padding: EdgeInsets.zero,
                    color: tt.textFaint,
                    icon: Icon(
                      Icons.close,
                      semanticLabel: l10n.attentionEventDismiss,
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

class _RootThumbnail extends StatelessWidget {
  const _RootThumbnail({required this.url});

  final String url;

  @override
  Widget build(BuildContext context) {
    final tt = context.tt;
    return ExcludeSemantics(
      child: ClipRRect(
        borderRadius: BorderRadius.circular(tt.cardRadius),
        child: SizedBox.square(
          dimension: tt.avatarSize,
          child: Image.network(
            url,
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) => const SizedBox.shrink(),
          ),
        ),
      ),
    );
  }
}

String _imageUrl(String authorId, String imageId) =>
    '$kImageServer/$kImagesPath/$authorId/$imageId.$kImageExt';

ImageEntity? _imageOf(String? imageId, String authorId) {
  if (imageId == null || imageId.isEmpty || imageId == 'null') return null;
  if (authorId.isEmpty) return null;
  return ImageEntity(id: imageId, authorId: authorId);
}
