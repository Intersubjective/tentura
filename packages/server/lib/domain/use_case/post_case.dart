import 'dart:typed_data';

import 'package:get_it/get_it.dart';
import 'package:injectable/injectable.dart';
import 'package:tentura_root/domain/entity/beacon_post_lifetime.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';

import 'package:tentura_server/domain/entity/beacon_kind.dart';
import 'package:tentura_server/domain/entity/post_publish_result.dart';
import 'package:tentura_server/domain/entity/post_summary.dart';
import 'package:tentura_server/domain/exception.dart';
import 'package:tentura_server/domain/port/beacon_repository_port.dart';
import 'package:tentura_server/domain/port/post_lock_port.dart';

import 'beacon_case.dart';
import 'beacon_room_case.dart';
import 'forward_case.dart';
import 'transactional_attention_case.dart';

/// Post-specific flows that compose the Request use cases.
// Order 3: depends on `BeaconRoomCase` (order 3).
@Singleton(order: 3)
class PostCase {
  @FactoryMethod(preResolve: true)
  static Future<PostCase> createInstance(
    ForwardCase forwardCase,
    BeaconRoomCase roomCase,
    BeaconRepositoryPort beaconRepository,
    PostLockPort postLock,
    TransactionalAttentionCase attention,
  ) async => PostCase(
    forwardCase: forwardCase,
    roomCase: roomCase,
    beaconRepository: beaconRepository,
    postLock: postLock,
    attention: attention,
  );

  PostCase({
    required ForwardCase forwardCase,
    required BeaconRoomCase roomCase,
    required BeaconRepositoryPort beaconRepository,
    required PostLockPort postLock,
    required TransactionalAttentionCase attention,
    BeaconCase? beaconCase,
  }) : _injectedBeaconCase = beaconCase,
       _forwardCase = forwardCase,
       _roomCase = roomCase,
       _beaconRepository = beaconRepository,
       _postLock = postLock,
       _attention = attention;

  /// Open Post conversations; the client chooses their ordering.
  Future<List<PostSummary>> myPosts(String viewerId) =>
      _beaconRepository.myPosts(viewerId);

  /// One row of [myPosts], for the Post screen.
  Future<PostSummary?> postSummary({
    required String viewerId,
    required String beaconId,
  }) => _beaconRepository.postSummary(viewerId: viewerId, beaconId: beaconId);

  final BeaconCase? _injectedBeaconCase;

  /// Resolved lazily: `BeaconCase` is pre-resolved by DI after this case.
  BeaconCase get _beaconCase => _injectedBeaconCase ?? GetIt.I<BeaconCase>();
  final ForwardCase _forwardCase;
  final BeaconRoomCase _roomCase;
  final BeaconRepositoryPort _beaconRepository;
  final PostLockPort _postLock;
  final TransactionalAttentionCase _attention;

  /// Publishes a draft Post, forwards it to [recipientIds] and posts the root
  /// message, all in one transaction after upload I/O. [lifetimeHours]
  /// (1…72, default 72) sets when the Post expires. A retry by the author
  /// after success returns the existing ids.
  Future<PostPublishResult> publish({
    required String authorId,
    required String beaconId,
    required String body,
    required List<String> mentionUserIds,
    required List<int> mentionOffsets,
    required List<int> mentionLengths,
    required List<String> recipientIds,
    required Map<String, String> notes,
    required BeaconForwardPolicyValue forwardPolicy,
    Stream<Uint8List>? attachmentBytes,
    String? attachmentFilename,
    String? attachmentMimeType,
    int? lifetimeHours,
  }) async {
    final existing = await _publishedPostOrValidateDraft(
      authorId: authorId,
      beaconId: beaconId,
    );
    if (existing != null) return existing;
    if (lifetimeHours != null &&
        (lifetimeHours < BeaconPostLifetime.minHours ||
            lifetimeHours > BeaconPostLifetime.maxHours)) {
      throw const PostLifetimeInvalidException();
    }
    if (body.trim().isEmpty && attachmentBytes == null) {
      throw const BeaconCreateException(
        description: 'A Post needs text or an attachment',
      );
    }
    final attachment = attachmentBytes == null
        ? null
        : await _roomCase.prepareMessageAttachment(
            userId: authorId,
            bytes: attachmentBytes,
            uploadFilename: attachmentFilename,
            uploadMimeType: attachmentMimeType,
          );
    var createdMessage = false;
    final result = await _attention.runAction(
      actorUserId: authorId,
      action: (_) async {
        await _postLock.lockForPostMutation(beaconId);
        final existing = await _publishedPostOrValidateDraft(
          authorId: authorId,
          beaconId: beaconId,
        );
        if (existing != null) return existing;
        await _beaconRepository.setForwardPolicy(
          beaconId: beaconId,
          policy: forwardPolicy,
        );
        await _beaconCase.publishDraft(userId: authorId, beaconId: beaconId);
        // `publishDraft` stamps the 72 h default; a shorter choice restamps.
        if (lifetimeHours != null &&
            lifetimeHours != BeaconPostLifetime.maxHours) {
          await _beaconRepository.setPostLifetime(
            beaconId: beaconId,
            lifetime: Duration(hours: lifetimeHours),
          );
        }
        // Without recipients the Post stays visible only to its author —
        // `beacon_can_read_content` already admits the author unconditionally.
        if (recipientIds.isNotEmpty) {
          await _forwardCase.forward(
            senderId: authorId,
            beaconId: beaconId,
            recipientIds: recipientIds,
            perRecipientNotes: notes,
          );
        }
        final message = await _roomCase.createMessage(
          beaconId: beaconId,
          userId: authorId,
          body: body,
          explicitMentionUserIds: mentionUserIds,
          explicitMentionOffsets: mentionOffsets,
          explicitMentionLengths: mentionLengths,
          uploadedAttachment: attachment,
          deferAttachmentHash: true,
          suppressMentionNotifyFor: recipientIds.toSet(),
        );
        final rootMessageId = message['id']! as String;
        await _beaconRepository.setPostRootMessage(
          beaconId: beaconId,
          messageId: rootMessageId,
        );
        createdMessage = true;
        return PostPublishResult(
          beaconId: beaconId,
          rootMessageId: rootMessageId,
        );
      },
    );
    if (createdMessage) await _roomCase.scheduleAttachmentHash(attachment);
    return result;
  }

  Future<PostPublishResult?> _publishedPostOrValidateDraft({
    required String authorId,
    required String beaconId,
  }) async {
    final beacon = await _beaconRepository.getBeaconById(beaconId: beaconId);
    if (beacon.author.id != authorId) {
      throw const UnauthorizedException(
        description: 'Only the author can publish a Post',
      );
    }
    if (beacon.kind != BeaconKind.post) {
      throw const BeaconCreateException(description: 'Not a Post');
    }
    final existingRoot = beacon.postRootMessageId;
    if (beacon.status == BeaconStatus.open && existingRoot != null) {
      return PostPublishResult(
        beaconId: beaconId,
        rootMessageId: existingRoot,
      );
    }
    if (beacon.status != BeaconStatus.draft) {
      throw const BeaconCreateException(
        description: 'Post is not a draft',
      );
    }
    return null;
  }

  /// An addressee steps out of a Post (or of a Request converted from one).
  Future<void> leave({required String userId, required String beaconId}) =>
      _addresseeAction(
        userId: userId,
        beaconId: beaconId,
        action: _beaconRepository.leavePostAsAddressee,
      );

  /// An addressee who left comes back.
  Future<void> returnTo({required String userId, required String beaconId}) =>
      _addresseeAction(
        userId: userId,
        beaconId: beaconId,
        action: _beaconRepository.returnToPostAsAddressee,
      );

  Future<void> _addresseeAction({
    required String userId,
    required String beaconId,
    required Future<void> Function({
      required String beaconId,
      required String userId,
    })
    action,
  }) => _attention.runAction(
    actorUserId: userId,
    action: (_) async {
      await _postLock.lockForPostMutation(beaconId);
      // A Post closed by budding is read-only: nobody leaves or returns
      // (plan C5). A Request converted from a Post is not a Post.
      final beacon = await _beaconRepository.getBeaconById(beaconId: beaconId);
      if (beacon.kind == BeaconKind.post &&
          beacon.status != BeaconStatus.open) {
        throw const PostNotOpenException();
      }
      if (!await _beaconRepository.isPostAddressee(
        beaconId: beaconId,
        userId: userId,
      )) {
        throw const UnauthorizedException(
          description: 'Only an addressee can leave or return to a Post',
        );
      }
      await action(beaconId: beaconId, userId: userId);
    },
  );
}
