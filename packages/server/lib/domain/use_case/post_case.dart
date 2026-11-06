import 'dart:typed_data';

import 'package:get_it/get_it.dart';
import 'package:injectable/injectable.dart';
import 'package:tentura_root/domain/entity/beacon_post_lifetime.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';

import 'package:tentura_server/domain/entity/beacon_kind.dart';
import 'package:tentura_server/domain/entity/beacon_entity.dart';
import 'package:tentura_server/domain/entity/post_publish_result.dart';
import 'package:tentura_server/domain/entity/post_summary.dart';
import 'package:tentura_server/domain/exception.dart';
import 'package:tentura_server/domain/port/beacon_repository_port.dart';
import 'package:tentura_server/domain/port/post_lock_port.dart';

import 'beacon_case.dart';
import 'beacon_room_case.dart';
import 'forward_case.dart';
import 'post_close_operation.dart';
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

  /// Commits the draft's status before delivering to [recipientIds] and posting
  /// the root message in a transaction without the hierarchy lock. Upload I/O
  /// precedes both transactions. [lifetimeHours] (1…72, default 72) sets when
  /// the Post expires. An open Post without a root retries delivery alone;
  /// after success the author gets the existing ids.
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
    final post = await _postForPublication(
      authorId: authorId,
      beaconId: beaconId,
    );
    final existing = await _publishedResult(post);
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
    if (post.status == BeaconStatus.draft) {
      await _attention.runAction<void>(
        actorUserId: authorId,
        action: (_) async {
          await _postLock.lockForPostMutation(beaconId);
          final current = await _postForPublication(
            authorId: authorId,
            beaconId: beaconId,
          );
          if (current.status != BeaconStatus.draft) return;
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
          // A refused recipient fails the call before the status commits.
          if (recipientIds.isNotEmpty) {
            await _forwardCase.checkPostForward(
              senderId: authorId,
              beaconId: beaconId,
              recipientIds: recipientIds,
            );
          }
        },
      );
    }
    var createdMessage = false;
    final result = await _attention.runAction(
      actorUserId: authorId,
      action: (_) async {
        await _postLock.lockForPostDelivery(beaconId, senderId: authorId);
        final current = await _postForPublication(
          authorId: authorId,
          beaconId: beaconId,
        );
        final existing = await _publishedResult(current);
        if (existing != null) return existing;
        if (current.status != BeaconStatus.open) {
          throw const PostNotOpenException();
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
        final expiresAt = await _beaconRepository.postExpiresAt(beaconId);
        return PostPublishResult(
          beaconId: beaconId,
          rootMessageId: rootMessageId,
          expiresAt: expiresAt,
        );
      },
    );
    if (createdMessage) await _roomCase.scheduleAttachmentHash(attachment);
    return result;
  }

  Future<BeaconEntity> _postForPublication({
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
    if (beacon.status != BeaconStatus.draft &&
        beacon.status != BeaconStatus.open) {
      throw const BeaconCreateException(
        description: 'Post is not a draft',
      );
    }
    return beacon;
  }

  Future<PostPublishResult?> _publishedResult(BeaconEntity beacon) async {
    final root = beacon.postRootMessageId;
    if (beacon.status != BeaconStatus.open || root == null) return null;
    final expiresAt = await _beaconRepository.postExpiresAt(beacon.id);
    return PostPublishResult(
      beaconId: beacon.id,
      rootMessageId: root,
      expiresAt: expiresAt,
    );
  }

  /// The author ends the open Post early: [expiresAt] must be after now and
  /// before the current end.
  Future<void> shorten({
    required String userId,
    required String beaconId,
    required DateTime expiresAt,
  }) => _attention.runAction(
    actorUserId: userId,
    action: (_) async {
      await _postLock.lockForPostMutation(beaconId);
      final current = await _requireOpenOwnPost(
        userId: userId,
        beaconId: beaconId,
      );
      if (!expiresAt.isAfter(DateTime.now())) {
        throw const PostLifetimeInvalidException();
      }
      if (!expiresAt.isBefore(current)) {
        throw const PostLifetimeExtendException();
      }
      await _beaconRepository.setPostExpiresAt(
        postId: beaconId,
        expiresAt: expiresAt,
      );
    },
  );

  /// The author closes the open Post now.
  Future<void> close({required String userId, required String beaconId}) =>
      _attention.runAction(
        actorUserId: userId,
        action: (_) async {
          await _postLock.lockForPostMutation(beaconId);
          await _requireOpenOwnPost(userId: userId, beaconId: beaconId);
          await PostCloseOperation(
            _beaconRepository,
          ).closeByAuthor(postId: beaconId, actorId: userId);
        },
      );

  /// Returns the `expires_at` of [beaconId] after checking that it is an open,
  /// not yet expired Post written by [userId]; the caller holds the Post lock.
  Future<DateTime> _requireOpenOwnPost({
    required String userId,
    required String beaconId,
  }) async {
    final beacon = await _beaconRepository.getBeaconById(beaconId: beaconId);
    if (beacon.author.id != userId) {
      throw const UnauthorizedException(
        description: 'Only the author can change a Post lifetime',
      );
    }
    final expiresAt = await _beaconRepository.postExpiresAt(beaconId);
    if (beacon.kind != BeaconKind.post ||
        beacon.status != BeaconStatus.open ||
        expiresAt == null ||
        !expiresAt.isAfter(DateTime.now())) {
      throw const PostNotOpenException();
    }
    return expiresAt;
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
      final beacon = await _beaconRepository.getBeaconById(beaconId: beaconId);
      if (beacon.kind == BeaconKind.post &&
          beacon.status != BeaconStatus.open &&
          beacon.status != BeaconStatus.closed) {
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
