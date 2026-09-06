import 'package:injectable/injectable.dart';
import 'package:tentura_root/domain/entity/beacon_child_command_outcome.dart';
import 'package:tentura_root/domain/entity/beacon_creation_context.dart';
import 'package:tentura_root/domain/entity/beacon_hierarchy_capabilities.dart';
import 'package:tentura_root/domain/entity/beacon_hierarchy_child_group.dart';
import 'package:tentura_root/domain/entity/beacon_hierarchy_page.dart';
import 'package:tentura_root/domain/entity/beacon_parent_reference.dart';
import 'package:tentura_root/domain/entity/beacon_promotion_source.dart';
import 'package:uuid/uuid.dart';

import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/image_entity.dart';
import 'package:tentura/domain/entity/realtime/realtime_entity_change.dart';
import 'package:tentura/domain/port/beacon_child_command_store_port.dart';
import 'package:tentura/domain/port/beacon_write_port.dart';
import 'package:tentura/domain/use_case/beacon_create_case.dart';
import 'package:tentura/domain/use_case/realtime_sync_case.dart';
import 'package:tentura/features/beacon/domain/beacon_hierarchy_exception.dart';
import 'package:tentura/features/beacon/domain/port/beacon_hierarchy_repository_port.dart';

/// Result of opening the child-request composer (plan §3.4.10).
class BeaconChildComposerSession {
  const BeaconChildComposerSession({
    this.clientCommandId,
    this.descriptionSeed,
    this.promotionSource,
    this.restoredDraftBeaconId,
  });

  /// Null when reopening an existing server draft (uses canonical id instead).
  final String? clientCommandId;

  /// One-time description seed from a promotion source; title stays empty.
  final String? descriptionSeed;

  /// Composer-only authorized preview; never part of the child payload.
  final BeaconPromotionSource? promotionSource;

  /// Canonical draft id when restoring an existing child draft.
  final String? restoredDraftBeaconId;
}

/// Child save command carrying hierarchy identity and optional exact-retry
/// snapshot for ambiguous create responses (plan §3.4.4).
class BeaconChildSaveCommand {
  const BeaconChildSaveCommand({
    required this.creationContext,
    required this.clientCommandId,
    required this.saveCommand,
    this.exactRetrySnapshot,
  });

  final BeaconCreationContext creationContext;
  final String clientCommandId;
  final BeaconSaveCommand saveCommand;

  /// Last create payload sent before an ambiguous failure; retried verbatim
  /// before applying edited fields to a recovered canonical id.
  final BeaconSaveCommand? exactRetrySnapshot;

  BeaconChildSaveCommand copyWith({
    BeaconCreationContext? creationContext,
    String? clientCommandId,
    BeaconSaveCommand? saveCommand,
    BeaconSaveCommand? exactRetrySnapshot,
    bool clearExactRetrySnapshot = false,
  }) => BeaconChildSaveCommand(
    creationContext: creationContext ?? this.creationContext,
    clientCommandId: clientCommandId ?? this.clientCommandId,
    saveCommand: saveCommand ?? this.saveCommand,
    exactRetrySnapshot: clearExactRetrySnapshot
        ? null
        : (exactRetrySnapshot ?? this.exactRetrySnapshot),
  );
}

/// Thrown when [BeaconChildCommandOutcome.alreadyPromoted] is returned — the
/// source already has a winning child and this draft must not be treated as
/// successfully published (plan §3.4.7).
final class BeaconChildPromotionConflict implements Exception {
  const BeaconChildPromotionConflict({
    required this.clientCommandId,
    this.draftBeaconId,
    this.existingChildBeaconId,
  });

  final String clientCommandId;
  final String? draftBeaconId;
  final String? existingChildBeaconId;

  @override
  String toString() =>
      'BeaconChildPromotionConflict(existing=$existingChildBeaconId)';
}

/// Coordinates child draft-first creation, idempotent command identity, media
/// reconciliation, and publication (plan §3.4). Standalone creation stays in
/// [BeaconCreateCase].
@singleton
class BeaconHierarchyCase {
  BeaconHierarchyCase(
    this._hierarchy,
    this._createCase,
    this._beacons,
    this._commandStore,
    this._realtimeSyncCase,
  );

  final BeaconHierarchyRepositoryPort _hierarchy;
  final BeaconCreateCase _createCase;
  final BeaconWritePort _beacons;
  final BeaconChildCommandStorePort _commandStore;
  final RealtimeSyncCase _realtimeSyncCase;

  Stream<RealtimeEntityChange> hierarchyChangesFor(String beaconId) =>
      _realtimeSyncCase.changesForAggregate(
        kinds: const {RealtimeEntityKind.beaconHierarchy},
        aggregateId: beaconId,
      );

  Stream<void> get catchUps => _realtimeSyncCase.catchUps.map((_) {});

  static const _uuid = Uuid();

  Future<BeaconHierarchyCapabilities> fetchCapabilities({
    required String beaconId,
  }) =>
      _hierarchy.fetchCapabilities(beaconId: beaconId);

  Future<BeaconHierarchyPage> fetchChildren({
    required String parentBeaconId,
    required BeaconHierarchyChildGroup group,
    int first = 20,
    String? after,
  }) =>
      _hierarchy.fetchChildren(
        parentBeaconId: parentBeaconId,
        group: group,
        first: first,
        after: after,
      );

  Future<BeaconParentReference> fetchParentReference({
    required String beaconId,
  }) =>
      _hierarchy.fetchParentReference(beaconId: beaconId);

  Future<BeaconChildComposerSession> openComposer({
    required BeaconCreationContext creationContext,
    String? restoredDraftBeaconId,
  }) async {
    if (restoredDraftBeaconId != null && restoredDraftBeaconId.isNotEmpty) {
      return BeaconChildComposerSession(
        restoredDraftBeaconId: restoredDraftBeaconId,
      );
    }

    final clientCommandId = await _resolveClientCommandId(creationContext);
    if (creationContext is BeaconCreationContextPromotedChild) {
      final source = await _hierarchy.fetchPromotionSource(
        parentBeaconId: creationContext.parentBeaconId,
        sourceMessageId: creationContext.sourceMessageId,
      );
      return BeaconChildComposerSession(
        clientCommandId: clientCommandId,
        descriptionSeed: source.textPreview,
        promotionSource: source,
      );
    }

    return BeaconChildComposerSession(clientCommandId: clientCommandId);
  }

  Future<String> _resolveClientCommandId(
    BeaconCreationContext creationContext,
  ) async {
    final stored = await _commandStore.read(creationContext);
    if (stored != null && stored.isNotEmpty) {
      return stored;
    }
    final created = _uuid.v4();
    await _commandStore.write(creationContext, created);
    return created;
  }

  Future<void> clearCommandIdentity(BeaconCreationContext creationContext) =>
      _commandStore.clear(creationContext);

  Future<BeaconSaveResult> ensureChildDraft(BeaconChildSaveCommand command) =>
      _saveChild(command);

  Future<BeaconSaveResult> saveChildDraft(BeaconChildSaveCommand command) =>
      _saveChild(command);

  Future<void> publishChildDraft({
    required String beaconId,
    required BeaconChildSaveCommand command,
    required List<ImageEntity> images,
    required String? coverKey,
    required ImageEntity? coverThumb,
  }) async {
    try {
      await _beacons.publishDraft(beaconId);
      await _commandStore.clear(command.creationContext);
    } on BeaconSourceAlreadyPromotedException catch (e) {
      // The real-world trigger for alreadyPromoted (plan §3.4.6): a
      // concurrent publisher won the same source between this draft's
      // creation and its publish attempt. Surface the same typed conflict
      // _runCreateChild uses, not a generic publish failure, so the UI
      // never implies this draft published and can offer the winning
      // child instead.
      throw BeaconChildPromotionConflict(
        clientCommandId: command.clientCommandId,
        draftBeaconId: beaconId,
        existingChildBeaconId: e.existingChildBeaconId,
      );
    } catch (e) {
      throw BeaconSaveFailure(
        cause: e,
        phase: BeaconSavePhase.publish,
        beaconId: beaconId,
        images: images,
        coverKey: coverKey,
        coverThumb: coverThumb,
        clientCommandId: command.clientCommandId,
      );
    }
  }

  Future<BeaconSaveResult> _saveChild(BeaconChildSaveCommand command) async {
    final canonicalId = command.saveCommand.fields.id;
    if (canonicalId.isNotEmpty) {
      return _saveExistingChildDraft(command);
    }

    final retry = command.exactRetrySnapshot;
    if (retry != null && !_sameCreatePayload(retry, command.saveCommand)) {
      final recovered = await _createChildDraft(
        command.copyWith(saveCommand: retry, clearExactRetrySnapshot: true),
      );
      final withId = command.saveCommand.copyWith(
        fields: command.saveCommand.fields.copyWith(id: recovered.beacon.id),
      );
      return _saveExistingChildDraft(
        command.copyWith(saveCommand: withId, clearExactRetrySnapshot: true),
      );
    }

    return _createChildDraft(command);
  }

  Future<BeaconSaveResult> _saveExistingChildDraft(
    BeaconChildSaveCommand command,
  ) async {
    try {
      return await _createCase.saveDraft(command.saveCommand);
    } on BeaconSaveFailure catch (failure) {
      throw BeaconSaveFailure(
        cause: failure.cause,
        phase: failure.phase,
        beaconId: failure.beaconId ?? command.saveCommand.fields.id,
        images: failure.images,
        coverKey: failure.coverKey,
        coverThumb: failure.coverThumb,
        clientCommandId: command.clientCommandId,
      );
    }
  }

  Future<BeaconSaveResult> _createChildDraft(BeaconChildSaveCommand command) {
    final fields = command.saveCommand.fields;
    final parentBeaconId = switch (command.creationContext) {
      BeaconCreationContextChild(:final parentBeaconId) => parentBeaconId,
      BeaconCreationContextPromotedChild(:final parentBeaconId) =>
        parentBeaconId,
      BeaconCreationContextStandalone() => throw ArgumentError(
        'Child save requires child creation context',
      ),
    };
    final sourceMessageId = switch (command.creationContext) {
      BeaconCreationContextPromotedChild(:final sourceMessageId) =>
        sourceMessageId,
      _ => null,
    };

    return _runCreateChild(
      command: command,
      parentBeaconId: parentBeaconId,
      sourceMessageId: sourceMessageId,
      fields: fields,
    );
  }

  Future<BeaconSaveResult> _runCreateChild({
    required BeaconChildSaveCommand command,
    required String parentBeaconId,
    required String? sourceMessageId,
    required Beacon fields,
  }) async {
    try {
      final outcome = await _hierarchy.createChild(
        parentBeaconId: parentBeaconId,
        sourceMessageId: sourceMessageId,
        clientCommandId: command.clientCommandId,
        title: fields.title,
        description: fields.description,
        context: fields.context.isEmpty ? null : fields.context,
        coordinates: fields.coordinates,
        startAt: fields.startAt,
        endAt: fields.endAt,
        tags: fields.tags.isEmpty ? null : fields.tags.join(','),
        needs: fields.needs.isEmpty ? null : fields.needs.join(','),
        primaryNeedSlug: fields.primaryNeedSlug,
        addressLabel: fields.addressLabel,
        draft: true,
      );

      switch (outcome.outcome) {
        case BeaconChildCommandOutcome.created:
        case BeaconChildCommandOutcome.replayed:
          final beaconId = outcome.beaconId;
          if (beaconId == null || beaconId.isEmpty) {
            throw BeaconSaveFailure(
              cause: StateError('Child create succeeded without beacon id'),
              phase: BeaconSavePhase.fields,
              beaconId: null,
              images: command.saveCommand.images,
              coverKey: command.saveCommand.coverKey,
              coverThumb: command.saveCommand.coverThumb,
              clientCommandId: command.clientCommandId,
            );
          }
          await _commandStore.clear(command.creationContext);
          if (command.saveCommand.images.isEmpty &&
              command.saveCommand.coverThumb == null) {
            return BeaconSaveResult(
              beacon: command.saveCommand.fields.copyWith(id: beaconId),
              images: command.saveCommand.images,
              coverThumb: command.saveCommand.coverThumb,
            );
          }
          try {
            return await _createCase.reconcileMedia(
              beaconId: beaconId,
              images: command.saveCommand.images,
              coverKey: command.saveCommand.coverKey,
              coverThumb: command.saveCommand.coverThumb,
              coverSource: command.saveCommand.coverSource,
            );
          } on BeaconSaveFailure catch (failure) {
            throw BeaconSaveFailure(
              cause: failure.cause,
              phase: failure.phase,
              beaconId: failure.beaconId ?? beaconId,
              images: failure.images,
              coverKey: failure.coverKey,
              coverThumb: failure.coverThumb,
              clientCommandId: command.clientCommandId,
            );
          }
        case BeaconChildCommandOutcome.alreadyPromoted:
          // No draft was created for this actor in this branch (server
          // only reaches it pre-creation) — outcome.beaconId names the
          // OTHER, already-published child, never this actor's own draft.
          throw BeaconChildPromotionConflict(
            clientCommandId: command.clientCommandId,
            existingChildBeaconId: outcome.beaconId,
          );
      }
    } on BeaconChildPromotionConflict {
      rethrow;
    } on BeaconSourceAlreadyPromotedException catch (e) {
      throw BeaconChildPromotionConflict(
        clientCommandId: command.clientCommandId,
        existingChildBeaconId: e.existingChildBeaconId,
      );
    } on BeaconHierarchyException catch (e) {
      throw _hierarchyFailure(command, e);
    } catch (e) {
      if (e is BeaconSaveFailure) {
        throw BeaconSaveFailure(
          cause: e.cause,
          phase: e.phase,
          beaconId: e.beaconId,
          images: e.images,
          coverKey: e.coverKey,
          coverThumb: e.coverThumb,
          clientCommandId: command.clientCommandId,
        );
      }
      throw _hierarchyFailure(command, e);
    }
  }

  BeaconSaveFailure _hierarchyFailure(
    BeaconChildSaveCommand command,
    Object cause,
  ) => BeaconSaveFailure(
    cause: cause,
    phase: BeaconSavePhase.fields,
    beaconId: command.saveCommand.fields.id.isEmpty
        ? null
        : command.saveCommand.fields.id,
    images: command.saveCommand.images,
    coverKey: command.saveCommand.coverKey,
    coverThumb: command.saveCommand.coverThumb,
    clientCommandId: command.clientCommandId,
  );

  bool _sameCreatePayload(BeaconSaveCommand a, BeaconSaveCommand b) {
    final fa = a.fields;
    final fb = b.fields;
    return fa.title == fb.title &&
        fa.description == fb.description &&
        fa.context == fb.context &&
        fa.tags == fb.tags &&
        fa.needs == fb.needs &&
        fa.primaryNeedSlug == fb.primaryNeedSlug &&
        fa.coordinates == fb.coordinates &&
        fa.addressLabel == fb.addressLabel &&
        fa.startAt == fb.startAt &&
        fa.endAt == fb.endAt;
  }
}
