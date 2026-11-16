import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:injectable/injectable.dart';
import 'package:logging/logging.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';
import 'package:tentura_root/utils/infer_image_mime_from_bytes.dart';
import 'package:uuid/uuid.dart';

import 'package:tentura_server/consts/beacon_fact_card_consts.dart';
import 'package:tentura_server/consts/beacon_room_consts.dart';
import 'package:tentura_server/domain/entity/beacon_fact_card_outcome.dart';
import 'package:tentura_server/domain/entity/beacon_fact_history_entry_entity.dart';
import 'package:tentura_server/domain/entity/beacon_fact_room_access.dart';
import 'package:tentura_server/domain/entity/beacon_kind.dart';
import 'package:tentura_server/domain/entity/fact_copy_outcome.dart';
import 'package:tentura_server/domain/entity/fact_copy_source.dart';
import 'package:tentura_server/domain/entity/prepared_fact_copy.dart';
import 'package:tentura_server/domain/entity/task_entity.dart';
import 'package:tentura_server/domain/exception.dart';
import 'package:tentura_server/domain/policy/beacon_room_lifecycle_write_policy.dart';
import 'package:tentura_server/domain/port/beacon_access_guard.dart';
import 'package:tentura_server/domain/port/beacon_fact_card_repository_port.dart';
import 'package:tentura_server/domain/port/beacon_hierarchy_repository_port.dart';
import 'package:tentura_server/domain/port/beacon_room_repository_port.dart';
import 'package:tentura_server/domain/port/image_repository_port.dart';
import 'package:tentura_server/domain/port/task_repository_port.dart';
import 'package:tentura_server/domain/request_context.dart';
import 'package:tentura_server/domain/use_case/room_write_guard.dart';
import 'package:tentura_server/env.dart';
import 'package:tentura_server/utils/id.dart';
import 'package:tentura_server/utils/postgres_sql_state.dart';
import 'package:tentura_server/utils/read_uint8_stream_with_limit.dart';

import '_use_case_base.dart';

// Order 1 and pre-resolved: [BeaconCase] (order 2) takes it as a nullable
// dependency, which Injectable does not order by.
@Singleton(order: 1)
final class BeaconFactCardCase extends UseCaseBase {
  @FactoryMethod(preResolve: true)
  static Future<BeaconFactCardCase> createInstance(
    BeaconFactCardRepositoryPort facts,
    BeaconRoomRepositoryPort room,
    ImageRepositoryPort imageRepository,
    TaskRepositoryPort tasksRepository,
    BeaconHierarchyRepositoryPort hierarchyRepository,
    BeaconAccessGuard guard,
    Env env,
    Logger logger,
  ) async => BeaconFactCardCase(
    facts,
    room,
    imageRepository,
    tasksRepository,
    hierarchyRepository,
    guard,
    env: env,
    logger: logger,
  );

  BeaconFactCardCase(
    this._facts,
    this._room,
    this._imageRepository,
    this._tasksRepository,
    this._hierarchyRepository,
    // Kept for DI, same as the hierarchy port above.
    // ignore: avoid_unused_constructor_parameters
    BeaconAccessGuard guard, {
    required super.env,
    required super.logger,
  });

  final BeaconFactCardRepositoryPort _facts;

  // Reserved for future room-coupled fact reads; list now uses revision snaps.
  // ignore: unused_field
  final BeaconRoomRepositoryPort _room;

  final ImageRepositoryPort _imageRepository;

  final TaskRepositoryPort _tasksRepository;

  /// Classifies a write that lost a race with closing or archiving.
  final BeaconHierarchyRepositoryPort _hierarchyRepository;

  /// Fused `loadRoomAccess` preflight (plan §5.1): room use, then a
  /// read-only room (lifecycle or expired Post), then R5: a draft accepts
  /// no fact writes but copy-in and remove. Returns the access row.
  Future<BeaconFactRoomAccess> _ensureWritableRoomAccess({
    required String beaconId,
    required String userId,
  }) async {
    final access = await _ensureRoomMember(beaconId: beaconId, userId: userId);
    _rejectReadOnly(access);
    if (access.isDraft) {
      throw const BeaconCreateException(
        description: 'Facts can be changed only after publishing',
      );
    }
    return access;
  }

  Future<BeaconFactRoomAccess> _ensureRoomMember({
    required String beaconId,
    required String userId,
  }) async {
    final access = await _facts.loadRoomAccess(
      beaconId: beaconId,
      userId: userId,
    );
    // An unknown id is a client mistake: the typed not-found answer.
    if (!access.exists) throw IdNotFoundException(id: beaconId);
    if (!access.canUseRoom) {
      throw const UnauthorizedException(
        description: 'Room access required',
      );
    }
    return access;
  }

  static void _rejectReadOnly(BeaconFactRoomAccess access) {
    if (BeaconRoomLifecycleWritePolicy.blocksOrdinaryUserWrites(
          BeaconStatus.fromSmallint(access.beaconStatus),
        ) ||
        access.isExpiredPost) {
      throw kRoomReadOnlyException;
    }
  }

  static bool _isPost(BeaconFactRoomAccess access) =>
      access.kind == BeaconKind.post.value;

  /// Plan §5.3: the destination of a copy: a Request or Post the actor can
  /// use, which for a draft means its author. A missing or deleted
  /// destination, someone else's draft and a non-member all get the same [UnauthorizedException],
  /// so beacon ids cannot be probed; a read-only room is reported only after
  /// membership passed.
  Future<void> _ensureCopyDestination({
    required String beaconId,
    required String userId,
  }) async {
    final access = await _facts.loadRoomAccess(
      beaconId: beaconId,
      userId: userId,
    );
    if (!access.exists ||
        !access.canUseRoom ||
        BeaconStatus.fromSmallint(access.beaconStatus) ==
            BeaconStatus.deleted) {
      throw const UnauthorizedException(description: 'Room access required');
    }
    _rejectReadOnly(access);
  }

  /// Plan §5.4 `BeaconFactCardCopy`: copies one fact into a published
  /// Request. Order: destination check, copy rate limit, [prepareCopies],
  /// insert; the source is loaded only after the first two passed. Blobs of
  /// a copy that was not inserted are compensated; hash tasks are scheduled
  /// for the inserted copy's images after the insert committed.
  Future<({String factCardId, FactCopyOutcome outcome})> copy({
    required String sourceFactCardId,
    required String destinationBeaconId,
    required String actorUserId,
  }) async {
    await _ensureCopyDestination(
      beaconId: destinationBeaconId,
      userId: actorUserId,
    );
    final recentCopies = await _facts.countRecentCopyRevisions(
      actorUserId: actorUserId,
      window: env.factEditRateWindow,
    );
    if (recentCopies >= env.factCopyRateMax) {
      throw const BeaconFactCardRateLimitedException(
        description: 'Too many fact copies',
      );
    }
    final (:prepared, :alreadyThere) = await prepareCopies(
      sourceFactCardIds: [sourceFactCardId],
      actorUserId: actorUserId,
      destinationBeaconId: destinationBeaconId,
      skipUnavailable: false,
    );
    if (alreadyThere[sourceFactCardId] case final existingId?) {
      return (factCardId: existingId, outcome: FactCopyOutcome.alreadyThere);
    }
    final copy = prepared.single;
    final List<String> ids;
    try {
      ids = await insertPreparedCopies(
        destinationBeaconId: destinationBeaconId,
        actorUserId: actorUserId,
        prepared: prepared,
      );
    } catch (_) {
      await compensatePreparedCopies(prepared, actorUserId: actorUserId);
      rethrow;
    }
    await settleInsertedCopies(
      prepared: prepared,
      insertedIds: ids,
      actorUserId: actorUserId,
    );
    final id = ids.single;
    return (
      factCardId: id,
      outcome: id == copy.factCardId
          ? FactCopyOutcome.created
          : FactCopyOutcome.alreadyThere,
    );
  }

  /// Plan §5.2 insert: writes [prepared] into [destinationBeaconId] (joining
  /// the caller's transaction, if any) and returns, per copy, the new id or
  /// the id of the live copy that won the race. A write that lost a race
  /// with closing or archiving is translated as for other room writes.
  Future<List<String>> insertPreparedCopies({
    required String destinationBeaconId,
    required String actorUserId,
    required List<PreparedFactCopy> prepared,
  }) => _hierarchyRepository.translateRoomWriteError(
    () => _facts.insertPreparedCopies(
      destinationBeaconId: destinationBeaconId,
      actorUserId: actorUserId,
      prepared: prepared,
    ),
  );

  /// Removes the re-stored images and files of copies that were not (or
  /// will not be) inserted.
  Future<void> compensatePreparedCopies(
    Iterable<PreparedFactCopy> prepared, {
    required String actorUserId,
  }) async {
    for (final copy in prepared) {
      for (final imageId in copy.newImageIds) {
        await _imageRepository.compensateOrphanedUpload(
          imageId: imageId,
          authorId: actorUserId,
        );
      }
      await _removeFilesNonFatal(copy.newFileKeys);
    }
  }

  /// Removes copied file objects no fact references (any more). A leftover
  /// object only costs storage, so a failure is logged, not thrown.
  Future<void> _removeFilesNonFatal(Iterable<String> fileKeys) async {
    for (final path in fileKeys) {
      try {
        await _imageRepository.removeFile(path: path);
      } catch (e, st) {
        logger.warning('copied fact file $path not removed', e, st);
      }
    }
  }

  /// After the insert committed: compensates the blobs of copies that lost
  /// to an existing copy and schedules hash tasks for the inserted ones.
  /// [insertedIds] is the result of [insertPreparedCopies].
  Future<void> settleInsertedCopies({
    required List<PreparedFactCopy> prepared,
    required List<String> insertedIds,
    required String actorUserId,
  }) async {
    for (final (i, copy) in prepared.indexed) {
      if (insertedIds[i] != copy.factCardId) {
        await compensatePreparedCopies([copy], actorUserId: actorUserId);
        continue;
      }
      for (final imageId in copy.newImageIds) {
        await _scheduleHashTaskNonFatal(imageId);
      }
    }
  }

  /// The image is already stored and referenced; a failed hash task only
  /// delays its blur hash.
  Future<void> _scheduleHashTaskNonFatal(String imageId) async {
    try {
      await _tasksRepository.schedule(
        TaskEntity(details: TaskCalculateImageHashDetails(imageId: imageId)),
      );
    } catch (e, st) {
      logger.warning('failed to schedule hash task for image $imageId', e, st);
    }
  }

  /// Plan §5.2 `prepareCopies`: authorises and snapshots each source fact
  /// and re-stores its images under [actorUserId] and its files as new
  /// objects (files have no size, quota or count limit). The caller has already
  /// checked the destination (and, for a single copy, the copy rate limit).
  ///
  /// An unavailable source (missing, removed, outside
  /// [requiredSourceBeaconId], already in [destinationBeaconId], or failing
  /// the fact access rule) throws [FactCopySourceUnavailableException], or
  /// is dropped when [skipUnavailable]. A fact with a live copy in
  /// [destinationBeaconId] is reported in `alreadyThere` without blob work.
  /// Hash tasks are left to the caller, after the copies are inserted.
  Future<({List<PreparedFactCopy> prepared, Map<String, String> alreadyThere})>
  prepareCopies({
    required List<String> sourceFactCardIds,
    required String actorUserId,
    required bool skipUnavailable,
    String? destinationBeaconId,
    String? requiredSourceBeaconId,
  }) async {
    final ids = sourceFactCardIds.toSet().toList();
    if (ids.length > kMaxFactCopySourcesPerCall) {
      throw const BeaconCreateException(description: 'Too many facts to copy');
    }
    final loaded = {
      for (final source in await _facts.loadCopySources(factCardIds: ids))
        source.factCardId: source,
    };
    final accessByBeacon = <String, BeaconFactRoomAccess>{};
    final available = <FactCopySource>[];
    for (final id in ids) {
      final source = loaded[id];
      if (source != null &&
          await _canCopyFrom(
            source,
            actorUserId: actorUserId,
            destinationBeaconId: destinationBeaconId,
            requiredSourceBeaconId: requiredSourceBeaconId,
            accessByBeacon: accessByBeacon,
          )) {
        available.add(source);
      } else if (!skipUnavailable) {
        throw const FactCopySourceUnavailableException();
      }
    }

    final alreadyThere = destinationBeaconId == null || available.isEmpty
        ? const <String, String>{}
        : await _facts.liveCopiesByOrigin(
            beaconId: destinationBeaconId,
            originFactCardIds: [for (final s in available) s.factCardId],
          );

    final prepared = <PreparedFactCopy>[];
    // Every blob this call created and still owns, for compensation.
    final created = <String>[];
    final createdFiles = <String>[];
    var imageCount = 0;
    var imagesStopped = false;
    try {
      for (final source in available) {
        if (alreadyThere.containsKey(source.factCardId)) continue;
        if (imagesStopped &&
            source.attachments.any((a) => _copyableImageId(a) != null)) {
          continue;
        }

        final factBlobs = <String>[];
        final factFiles = <String>[];
        final attachments = <Map<String, Object?>>[];
        var dropFact = false;
        for (final a in source.attachments) {
          if (a.fileKey case final fileKey?) {
            final String newKey;
            try {
              newKey = await _imageRepository.copyFile(
                path: fileKey,
                mime: switch (a.fields['mime']) {
                  final String mime => mime,
                  _ => 'application/octet-stream',
                },
              );
            } on FactCopyAttachmentUnavailableException {
              if (!skipUnavailable) rethrow;
              continue;
            }
            factFiles.add(newKey);
            createdFiles.add(newKey);
            attachments.add({
              ...a.fields,
              'id': generateId('A'),
              'fileKey': newKey,
            });
            continue;
          }
          final imageId = _copyableImageId(a);
          if (imageId == null) continue;
          if (imageCount == kMaxFactCopyImagesPerCall) {
            if (!skipUnavailable) {
              throw const BeaconCreateException(
                description: 'Too many images to copy',
              );
            }
            dropFact = true;
            break;
          }
          final bytes = await _imageRepository.get(id: imageId);
          final String newImageId;
          try {
            newImageId = await _imageRepository.put(
              authorId: actorUserId,
              bytes: Stream.value(bytes),
            );
          } on RateLimitedException {
            if (!skipUnavailable) rethrow;
            dropFact = true;
            break;
          }
          imageCount++;
          factBlobs.add(newImageId);
          created.add(newImageId);
          attachments.add({
            ...a.fields,
            'id': generateId('A'),
            'imageId': newImageId,
            'imageAuthorId': actorUserId,
          });
        }
        if (dropFact) {
          // R1 / X9: drop this fact and stop copying images in this call.
          imagesStopped = true;
          for (final imageId in factBlobs) {
            created.remove(imageId);
            await _imageRepository.compensateOrphanedUpload(
              imageId: imageId,
              authorId: actorUserId,
            );
          }
          factFiles.forEach(createdFiles.remove);
          await _removeFilesNonFatal(factFiles);
          continue;
        }
        prepared.add(
          PreparedFactCopy(
            originFactCardId: source.factCardId,
            originRevisionSeq: source.headRevisionSeq,
            originBeaconKind: source.beaconKind,
            factText: source.headText,
            attachmentsJson: jsonEncode(attachments),
            newImageIds: factBlobs,
            newFileKeys: factFiles,
          ),
        );
      }
    } catch (_) {
      for (final imageId in created) {
        await _imageRepository.compensateOrphanedUpload(
          imageId: imageId,
          authorId: actorUserId,
        );
      }
      await _removeFilesNonFatal(createdFiles);
      rethrow;
    }
    return (prepared: prepared, alreadyThere: alreadyThere);
  }

  /// Plan §5.4 Origin row. Throws [FactCopySourceUnavailableException] when
  /// the fact is not a readable fact of [beaconId]; answers `null` when it
  /// has no origin, or the origin is not available to [userId].
  Future<Map<String, Object?>?> origin({
    required String beaconId,
    required String factCardId,
    required String userId,
  }) async {
    final access = await _facts.loadRoomAccess(
      beaconId: beaconId,
      userId: userId,
    );
    final ref = access.exists && access.canReadContent
        ? await _facts.loadOriginRef(factCardId: factCardId, beaconId: beaconId)
        : null;
    if (ref == null ||
        !access.canReadFact(status: ref.status, visibility: ref.visibility)) {
      throw const FactCopySourceUnavailableException();
    }
    final originId = ref.originFactCardId;
    final originSeq = ref.originRevisionSeq;
    if (originId == null || originSeq == null) return null;

    final source = (await _facts.loadCopySources(
      factCardIds: [originId],
    )).firstOrNull;
    final accessByBeacon = <String, BeaconFactRoomAccess>{};
    if (source == null ||
        !await _canCopyFrom(
          source,
          actorUserId: userId,
          destinationBeaconId: null,
          requiredSourceBeaconId: null,
          accessByBeacon: accessByBeacon,
        )) {
      return null;
    }
    final canSeeCopiedRevision = accessByBeacon[source.beaconId]!.canUseRoom;
    return {
      'available': true,
      'beaconId': source.beaconId,
      'factCardId': source.factCardId,
      'beaconKind': source.beaconKind,
      'changedSinceCopy': source.headRevisionSeq != originSeq,
      'canSeeCopiedRevision': canSeeCopiedRevision,
      'copiedRevisionSeq': canSeeCopiedRevision ? originSeq : null,
    };
  }

  /// Plan §5.4 CopyDestinations: the published, writable Requests and
  /// Posts [userId] can copy the fact into, most recently active first. Throws
  /// [FactCopySourceUnavailableException] unless the source is available.
  Future<List<Map<String, Object?>>> copyDestinations({
    required String sourceFactCardId,
    required String userId,
  }) async {
    final source = (await _facts.loadCopySources(
      factCardIds: [sourceFactCardId],
    )).firstOrNull;
    if (source == null ||
        !await _canCopyFrom(
          source,
          actorUserId: userId,
          destinationBeaconId: null,
          requiredSourceBeaconId: null,
          accessByBeacon: {},
        )) {
      throw const FactCopySourceUnavailableException();
    }
    final rows = await _facts.listCopyDestinations(
      userId: userId,
      excludeBeaconId: source.beaconId,
      writableStatuses: [
        for (final status in BeaconStatus.values)
          if (status != BeaconStatus.deleted &&
              !BeaconRoomLifecycleWritePolicy.blocksOrdinaryUserWrites(status))
            status.smallintValue,
      ],
      limit: kMaxFactCopyDestinations,
    );
    return [
      for (final r in rows)
        {
          'id': r.id,
          'kind': r.kind,
          'title': r.title,
          'isDraft': r.isDraft,
          'expiresAt': r.expiresAt?.toIso8601String(),
        },
    ];
  }

  /// Plan §5.2 step 3 and the §4.4 fact access rule.
  Future<bool> _canCopyFrom(
    FactCopySource source, {
    required String actorUserId,
    required String? destinationBeaconId,
    required String? requiredSourceBeaconId,
    required Map<String, BeaconFactRoomAccess> accessByBeacon,
  }) async {
    // Checked before the access load: a removed source costs no query.
    if (source.status == BeaconFactCardStatusBits.removed) return false;
    if (requiredSourceBeaconId != null &&
        source.beaconId != requiredSourceBeaconId) {
      return false;
    }
    if (source.beaconId == destinationBeaconId) return false;
    final access = accessByBeacon[source.beaconId] ??= await _facts
        .loadRoomAccess(beaconId: source.beaconId, userId: actorUserId);
    return access.canReadFact(
          status: source.status,
          visibility: source.visibility,
        ) ||
        await _facts.isUnblockedPinnerOfPublicFact(
          factCardId: source.factCardId,
          userId: actorUserId,
        );
  }

  /// R2: the image id of an image entry with a valid id whose row still
  /// exists; null for any other entry.
  static String? _copyableImageId(FactCopySourceAttachment a) =>
      switch (a.fields) {
        {
          'kind': BeaconRoomMessageAttachmentKind.image,
          'imageId': final String imageId,
        }
            when a.imageExists &&
                Uuid.isValidUUID(
                  fromString: imageId,
                  validationMode: ValidationMode.nonStrict,
                ) =>
          imageId,
        _ => null,
      };

  Future<Map<String, Object?>> pin({
    required String beaconId,
    required String factText,
    required int visibility,
    required String userId,
    String? sourceMessageId,
  }) async {
    try {
      final trimmed = factText.trim();
      if (trimmed.isEmpty) {
        throw const BeaconCreateException(description: 'Fact text is empty');
      }
      final access = await _ensureWritableRoomAccess(
        beaconId: beaconId,
        userId: userId,
      );
      final entity = await _hierarchyRepository.translateRoomWriteError(
        () => _facts.pinFact(
          beaconId: beaconId,
          factText: trimmed,
          // D5: a Post has one visibility, discussion-only.
          visibility: _isPost(access)
              ? BeaconFactCardVisibilityBits.room
              : visibility,
          pinnedBy: userId,
          sourceMessageId: sourceMessageId,
        ),
      );
      return {'id': entity.id, 'beaconId': entity.beaconId};
    } on Object catch (e, st) {
      _logPinFailure(
        error: e,
        stackTrace: st,
        beaconId: beaconId,
        sourceMessageId: sourceMessageId,
        visibility: visibility,
        userId: userId,
      );
      rethrow;
    }
  }

  /// One structured line per failed pin, so the next failure shows up in the
  /// server logs (#759). Carries no fact text and no raw user id: the user is
  /// a keyed hash, enough to tell repeat tries of one person apart. An
  /// unexpected error (a database one can quote the row: fact text, pinner)
  /// is named only by its type and SQLSTATE; its text and the error object
  /// stay out of the log.
  void _logPinFailure({
    required Object error,
    required StackTrace stackTrace,
    required String beaconId,
    required String? sourceMessageId,
    required int visibility,
    required String userId,
  }) {
    final detail = error is ExceptionBase
        ? 'message=${jsonEncode(_oneLine(error.description))}'
        : 'sqlstate=${postgresSqlState(error) ?? '-'}';
    final line =
        'fact_pin_failed error_type=${error.runtimeType} '
        'beacon_id=$beaconId '
        'source_message_id=${sourceMessageId ?? '-'} '
        'visibility=$visibility '
        'user_hash=${_userLogHash(userId)} '
        'request_id=${RequestContext.current?.requestId ?? '-'} '
        '$detail';
    if (error is ExceptionBase) {
      logger.warning(line);
    } else {
      logger.severe(line, null, stackTrace);
    }
  }

  /// HMAC-SHA256 of [userId] under the server secret that already keys user
  /// pseudonyms (invite-genealogy node keys), so the log cannot be reversed
  /// from the user table; `-` when no secret is configured.
  String _userLogHash(String userId) {
    final secret = env.genealogyNodeKeySecret.isNotEmpty
        ? env.genealogyNodeKeySecret
        : env.unsubscribeSigningSecret;
    if (secret.isEmpty) return '-';
    return Hmac(sha256, utf8.encode(secret))
        .convert(utf8.encode('fact_pin_failed:$userId'))
        .toString()
        .substring(0, 12);
  }

  static String _oneLine(String text) {
    final flat = text.replaceAll(RegExp(r'\s+'), ' ').trim();
    return flat.length <= 300 ? flat : '${flat.substring(0, 300)}…';
  }

  /// Edits fact text and/or attachments against [baseRevisionSeq]; returns
  /// the resulting head seq. When [attachmentsJson] is null the previous head
  /// attachment snapshot is kept; when non-null it replaces the snapshot.
  ///
  /// Plan X11: an entry whose `id` is on any revision of this fact is stored
  /// as the server saved it, taking only its position from the client's
  /// order; any other entry must be an image the actor uploaded.
  Future<int> correct({
    required String factCardId,
    required String beaconId,
    required String actorUserId,
    required String newText,
    required int baseRevisionSeq,
    String? attachmentsJson,
  }) async {
    final clientAttachments = attachmentsJson == null
        ? null
        : _parseClientAttachments(attachmentsJson);
    var effectiveText = newText.trim();
    if (effectiveText.isEmpty && clientAttachments == null) {
      throw const BeaconCreateException(description: 'Fact text is empty');
    }

    await _ensureWritableRoomAccess(beaconId: beaconId, userId: actorUserId);

    final attachments = clientAttachments == null
        ? null
        : await _serverAttachments(
            clientAttachments,
            factCardId: factCardId,
            beaconId: beaconId,
            actorUserId: actorUserId,
          );
    if (effectiveText.isEmpty && attachments != null) {
      final names = [
        for (final item in attachments)
          if (item['fileName'] case final String name
              when name.trim().isNotEmpty)
            name.trim(),
      ];
      effectiveText = names.isEmpty
          ? 'Attachment'
          : names.length <= 3
          ? names.join(', ')
          : '${names.take(3).join(', ')}…';
    }

    return _seqOrThrow(
      await _hierarchyRepository.translateRoomWriteError(
        () => _facts.editText(
          factCardId: factCardId,
          beaconId: beaconId,
          actorUserId: actorUserId,
          newText: effectiveText,
          baseRevisionSeq: baseRevisionSeq,
          rateWindow: env.factEditRateWindow,
          rateMax: env.factEditRateMax,
          quietWindow: kFactEditQuietWindow,
          attachmentsJson: attachments == null ? null : jsonEncode(attachments),
        ),
      ),
      factCardId: factCardId,
    );
  }

  /// Parses an edit's attachment list: a JSON list of at most
  /// [kMaxRoomMessageAttachments] objects, each with its own string `id`.
  static List<({String id, Map<String, Object?> fields})>
  _parseClientAttachments(String attachmentsJson) {
    const invalid = BeaconCreateException(description: 'Invalid attachments');
    final Object? decoded;
    try {
      decoded = jsonDecode(attachmentsJson);
    } on FormatException {
      throw invalid;
    }
    if (decoded is! List || decoded.length > kMaxRoomMessageAttachments) {
      throw invalid;
    }
    final ids = <String>{};
    return [
      for (final item in decoded)
        if (item case {'id': final String id} when id.isNotEmpty && ids.add(id))
          (id: id, fields: Map<String, Object?>.from(item))
        else
          throw invalid,
    ];
  }

  /// Rebuilds the client's attachment list from server data, in the
  /// client's order (see [correct]).
  Future<List<Map<String, Object?>>> _serverAttachments(
    List<({String id, Map<String, Object?> fields})> clientAttachments, {
    required String factCardId,
    required String beaconId,
    required String actorUserId,
  }) async {
    if (clientAttachments.isEmpty) return const [];
    final lookup = await _facts.findEditAttachments(
      factCardId: factCardId,
      beaconId: beaconId,
      actorUserId: actorUserId,
      attachmentIds: [for (final a in clientAttachments) a.id],
      imageIds: [
        for (final a in clientAttachments)
          if (a.fields['imageId'] case final String imageId
              when Uuid.isValidUUID(
                fromString: imageId,
                validationMode: ValidationMode.nonStrict,
              ))
            imageId,
      ],
    );
    return [
      for (final (position, a) in clientAttachments.indexed)
        if (lookup.known[a.id] case final known?)
          {...known, 'position': position}
        else if (a.fields case {
          'kind': BeaconRoomMessageAttachmentKind.image,
          'imageId': final String imageId,
        } when lookup.ownedImages.containsKey(imageId))
          {
            'id': a.id,
            'kind': BeaconRoomMessageAttachmentKind.image,
            'position': position,
            'mime': switch (a.fields['mime']) {
              final String mime => mime,
              _ => 'application/octet-stream',
            },
            'sizeBytes': switch (a.fields['sizeBytes']) {
              final int size => size,
              _ => 0,
            },
            'fileName': switch (a.fields['fileName']) {
              final String name => name,
              _ => '',
            },
            'imageId': imageId,
            'imageAuthorId': actorUserId,
            'blurHash': lookup.ownedImages[imageId]?.blurHash ?? '',
            'width': lookup.ownedImages[imageId]?.width ?? 0,
            'height': lookup.ownedImages[imageId]?.height ?? 0,
          }
        else
          throw const BeaconCreateException(
            description: 'Unknown attachment',
          ),
    ];
  }

  /// Stages one image attachment for a later [correct] `attachmentsJson`.
  /// Returns a single JSON object (not an array).
  Future<String> uploadAttachment({
    required String beaconId,
    required String actorUserId,
    required Stream<Uint8List> attachmentBytes,
    String? attachmentFilename,
    String? attachmentMimeType,
  }) async {
    await _ensureWritableRoomAccess(beaconId: beaconId, userId: actorUserId);
    final bytes = await readUint8StreamWithLimit(
      attachmentBytes,
      kMaxRoomMessageAttachmentBytes,
    );
    if (bytes.isEmpty) {
      throw const BeaconCreateException(description: 'Empty attachment');
    }
    final trimmedName = attachmentFilename?.trim() ?? '';
    final displayName = trimmedName.isEmpty ? 'file' : trimmedName;
    var mime = attachmentMimeType ?? 'application/octet-stream';
    final sniffed = inferImageMimeFromLeadingBytes(bytes);
    if (sniffed != null) mime = sniffed;
    if (sniffed == null && !mime.toLowerCase().startsWith('image/')) {
      throw const BeaconCreateException(
        description: 'Only image attachments are supported on facts',
      );
    }
    final imageId = await _imageRepository.put(
      authorId: actorUserId,
      bytes: Stream.value(bytes),
    );
    await _tasksRepository.schedule(
      TaskEntity(
        details: TaskCalculateImageHashDetails(imageId: imageId),
      ),
    );
    return jsonEncode({
      'id': generateId('A'),
      'kind': BeaconRoomMessageAttachmentKind.image,
      'position': 0,
      'mime': mime,
      'sizeBytes': bytes.length,
      'fileName': displayName,
      'imageId': imageId,
      'imageAuthorId': actorUserId,
      'blurHash': '',
      'width': 0,
      'height': 0,
    });
  }

  /// Restores the text of revision [fromSeq] as a new head revision; returns
  /// the resulting head seq.
  Future<int> restore({
    required String factCardId,
    required String beaconId,
    required String actorUserId,
    required int fromSeq,
    required int baseRevisionSeq,
  }) async {
    await _ensureWritableRoomAccess(beaconId: beaconId, userId: actorUserId);
    return _seqOrThrow(
      await _hierarchyRepository.translateRoomWriteError(
        () => _facts.restoreRevision(
          factCardId: factCardId,
          beaconId: beaconId,
          actorUserId: actorUserId,
          fromSeq: fromSeq,
          baseRevisionSeq: baseRevisionSeq,
          rateWindow: env.factEditRateWindow,
          rateMax: env.factEditRateMax,
          quietWindow: kFactEditQuietWindow,
        ),
      ),
      factCardId: factCardId,
    );
  }

  /// Plan §14.5 outcome → result/exception map.
  int _seqOrThrow(FactEditOutcome outcome, {required String factCardId}) =>
      switch (outcome) {
        FactEditApplied(:final newSeq) => newSeq,
        FactEditNoOp(:final currentSeq) => currentSeq,
        FactEditNotFound() => throw IdNotFoundException(id: factCardId),
        FactEditRemoved() => throw const BeaconFactCardRemovedException(),
        FactEditRateLimited() =>
          throw const BeaconFactCardRateLimitedException(),
        FactEditConflict(:final currentSeq) =>
          throw BeaconFactCardEditConflictException(currentSeq: currentSeq),
        FactRestoreSourceMissing() => throw IdWrongException(
          id: factCardId,
          description: 'Fact card revision not found',
        ),
      };

  /// Unpins a fact. On a draft (plan R5, §5.4) only the author may remove
  /// it, and it is deleted outright, with no chat line and no event.
  Future<bool> remove({
    required String factCardId,
    required String beaconId,
    required String actorUserId,
  }) async {
    final access = await _ensureRoomMember(
      beaconId: beaconId,
      userId: actorUserId,
    );
    _rejectReadOnly(access);
    if (access.isDraft) {
      final (:deleted, :fileKeys) = await _facts.deleteFromDraft(
        factCardId: factCardId,
        beaconId: beaconId,
        actorUserId: actorUserId,
      );
      await _removeFilesNonFatal(fileKeys);
      return deleted;
    }
    return _hierarchyRepository.translateRoomWriteError(
      () => _facts.remove(
        factCardId: factCardId,
        beaconId: beaconId,
        actorUserId: actorUserId,
      ),
    );
  }

  Future<bool> setVisibility({
    required String factCardId,
    required String beaconId,
    required String actorUserId,
    required int visibility,
  }) async {
    final access = await _ensureWritableRoomAccess(
      beaconId: beaconId,
      userId: actorUserId,
    );
    // D5: no «Make public / private» on a Post.
    if (_isPost(access)) throw const BeaconNotRequestException();
    await _hierarchyRepository.translateRoomWriteError(
      () => _facts.setVisibility(
        factCardId: factCardId,
        beaconId: beaconId,
        actorUserId: actorUserId,
        visibility: visibility,
      ),
    );
    return true;
  }

  Future<List<Map<String, Object?>>> list({
    required String beaconId,
    required String userId,
  }) async {
    final access = await _facts.loadRoomAccess(
      beaconId: beaconId,
      userId: userId,
    );
    if (!access.canReadContent) {
      throw const UnauthorizedException(
        description: 'Viewer cannot read request content',
      );
    }
    final rows = await _facts.listForBeacon(
      beaconId: beaconId,
      viewerId: userId,
      includeRoomOnly: access.canUseRoom,
    );
    final attachmentsByFactId = await _facts.headAttachmentsJsonByFactIds([
      for (final e in rows) e.id,
    ]);
    return [
      for (final e in rows)
        <String, Object?>{
          'id': e.id,
          'beaconId': e.beaconId,
          'factText': e.factText,
          'visibility': e.visibility,
          'pinnedBy': e.pinnedBy,
          'pinnedByTitle': e.pinnedByTitle,
          'sourceMessageId': e.sourceMessageId,
          'status': e.status,
          'createdAt': e.createdAt.toIso8601String(),
          'updatedAt': e.updatedAt?.toIso8601String(),
          'attachmentsJson': attachmentsByFactId[e.id] ?? '[]',
          'revisionSeq': e.revisionSeq,
          'lastEditedBy': e.lastEditedBy,
          'lastEditedByTitle': e.lastEditedByTitle,
          'lastEditedAt': e.lastEditedAt?.toIso8601String(),
          'otherEditorCount': e.otherEditorCount,
          'historyTruncated': e.historyTruncated,
          'originBeaconKind': e.originBeaconKind,
          'savedByMe': e.savedByMe,
        },
    ];
  }

  /// Plan §8.4 / §8.11, D1: read-only fact timeline page. Gates on
  /// `canUseRoom` (members only), not `list()`'s `canReadContent`. [before]
  /// is the opaque `'<iso8601UTC>|<entry_key>'` cursor from a prior page's
  /// `nextCursor`.
  Future<({List<BeaconFactHistoryEntry> entries, String? nextCursor})> history({
    required String factCardId,
    required String beaconId,
    required String userId,
    String? before,
  }) async {
    final parsedBefore = _parseHistoryCursor(before, factCardId: factCardId);

    final access = await _facts.loadRoomAccess(
      beaconId: beaconId,
      userId: userId,
    );
    if (!access.exists || !access.canUseRoom) {
      throw const UnauthorizedException(
        description: 'Room access required',
      );
    }

    final rows = await _facts.history(
      factCardId: factCardId,
      beaconId: beaconId,
      before: parsedBefore,
    );
    final entries = rows.take(kFactHistoryPageSize).toList();
    return (
      entries: entries,
      nextCursor: rows.length > kFactHistoryPageSize
          ? _serializeHistoryCursor(entries.last)
          : null,
    );
  }

  /// Parses the opaque cursor into the port's keyset `before` argument;
  /// throws `IdWrongException` on any malformed input.
  ({DateTime createdAt, String entryKey})? _parseHistoryCursor(
    String? cursor, {
    required String factCardId,
  }) {
    if (cursor == null) return null;
    final sep = cursor.indexOf('|');
    final createdAt = sep < 0
        ? null
        : DateTime.tryParse(cursor.substring(0, sep));
    final entryKey = sep < 0 ? '' : cursor.substring(sep + 1);
    if (createdAt == null || entryKey.isEmpty) {
      throw IdWrongException(id: factCardId);
    }
    return (createdAt: createdAt, entryKey: entryKey);
  }

  String _serializeHistoryCursor(BeaconFactHistoryEntry entry) =>
      '${entry.createdAt.toUtc().toIso8601String()}|${_historyEntryKey(entry)}';

  /// Mirrors the repository's `entry_key` convention (§14.3): `'r' ||
  /// lpad(seq, 10)` for revisions, `'e' || id` for events.
  String _historyEntryKey(BeaconFactHistoryEntry entry) => switch (entry) {
    BeaconFactHistoryRevision(:final seq) =>
      'r${seq.toString().padLeft(10, '0')}',
    BeaconFactHistoryEvent(:final activityEventId) => 'e$activityEventId',
  };
}
