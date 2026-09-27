import 'package:injectable/injectable.dart';

import 'package:tentura/data/gql/tentura_v2_upload.dart';
import 'package:tentura/data/service/remote_api_service.dart';
import 'package:tentura/domain/entity/beacon_fact_card.dart';
import 'package:tentura/domain/entity/beacon_fact_card_consts.dart';
import 'package:tentura/domain/entity/beacon_fact_history_entry.dart';
import 'package:tentura/domain/entity/room_message_attachment.dart';
import 'package:tentura/domain/entity/room_pending_upload.dart';

import '../gql/_g/beacon_fact_card_attachment_upload.req.gql.dart';
import '../gql/_g/beacon_fact_card_correct.req.gql.dart';
import '../gql/_g/beacon_fact_card_list.data.gql.dart';
import '../gql/_g/beacon_fact_card_list.req.gql.dart';
import '../gql/_g/beacon_fact_card_pin.req.gql.dart';
import '../gql/_g/beacon_fact_card_remove.req.gql.dart';
import '../gql/_g/beacon_fact_card_restore.req.gql.dart';
import '../gql/_g/beacon_fact_card_revisions.data.gql.dart';
import '../gql/_g/beacon_fact_card_revisions.req.gql.dart';
import '../gql/_g/beacon_fact_card_set_visibility.req.gql.dart';

@lazySingleton
class BeaconFactCardRepository {
  BeaconFactCardRepository(this._remoteApiService);

  final RemoteApiService _remoteApiService;

  static const _label = 'BeaconFactCard';

  BeaconFactCard _mapRow(GBeaconFactCardListData_BeaconFactCardList row) =>
      BeaconFactCard(
        id: row.id,
        beaconId: row.beaconId,
        factText: row.factText,
        visibility: row.visibility,
        pinnedBy: row.pinnedBy,
        createdAt: DateTime.parse(row.createdAt),
        status: row.status,
        sourceMessageId: row.sourceMessageId,
        updatedAt: row.updatedAt != null
            ? DateTime.parse(row.updatedAt!)
            : null,
        pinnedByTitle: row.pinnedByTitle,
        revisionSeq: row.revisionSeq,
        lastEditedBy: row.lastEditedBy,
        lastEditedByTitle: row.lastEditedByTitle ?? '',
        lastEditedAt: row.lastEditedAt != null
            ? DateTime.parse(row.lastEditedAt!)
            : null,
        otherEditorCount: row.otherEditorCount,
        historyTruncated: row.historyTruncated,
        attachments: parseRoomMessageAttachmentsJson(row.attachmentsJson),
      );

  Future<List<BeaconFactCard>> list({required String beaconId}) async {
    final r = await _remoteApiService
        .request(GBeaconFactCardListReq((b) => b.vars.beaconId = beaconId))
        .firstWhere((e) => e.dataSource == DataSource.Link);
    final raw =
        r.dataOrThrow(label: _label).BeaconFactCardList?.toList() ?? const [];
    return raw.map(_mapRow).toList(growable: false);
  }

  Future<void> pin({
    required String beaconId,
    required String factText,
    required int visibility,
    String? sourceMessageId,
  }) async {
    await _remoteApiService
        .request(
          GBeaconFactCardPinReq(
            (b) => b.vars
              ..beaconId = beaconId
              ..factText = factText
              ..visibility = visibility
              ..sourceMessageId = sourceMessageId,
          ),
        )
        .firstWhere((e) => e.dataSource == DataSource.Link)
        .then((r) => r.dataOrThrow(label: _label).BeaconFactCardPin);
  }

  /// Returns the new head revision seq.
  Future<int> correct({
    required String beaconId,
    required String factCardId,
    required String newText,
    required int baseRevisionSeq,
    String? attachmentsJson,
  }) => _remoteApiService
      .request(
        GBeaconFactCardCorrectReq(
          (b) => b.vars
            ..beaconId = beaconId
            ..factCardId = factCardId
            ..newText = newText
            ..baseRevisionSeq = baseRevisionSeq
            ..attachmentsJson = attachmentsJson,
        ),
      )
      .firstWhere((e) => e.dataSource == DataSource.Link)
      .then((r) => r.dataOrThrow(label: _label).BeaconFactCardCorrect);

  /// Stages one image; returns a single attachment JSON object string.
  Future<String> uploadAttachment({
    required String beaconId,
    required RoomPendingUpload upload,
  }) async {
    final file = TenturaV2Upload(
      filename: upload.fileName,
      mimeType: upload.mimeType,
      bytes: upload.bytes,
    );
    return _remoteApiService
        .request(
          GBeaconFactCardAttachmentUploadReq(
            (b) => b.vars
              ..beaconId = beaconId
              ..file = file,
          ),
        )
        .firstWhere((e) => e.dataSource == DataSource.Link)
        .then(
          (r) =>
              r.dataOrThrow(label: _label).BeaconFactCardAttachmentUpload,
        );
  }

  /// Restores revision [fromSeq] as the new head; returns its seq.
  Future<int> restore({
    required String beaconId,
    required String factCardId,
    required int fromSeq,
    required int baseRevisionSeq,
  }) => _remoteApiService
      .request(
        GBeaconFactCardRestoreReq(
          (b) => b.vars
            ..beaconId = beaconId
            ..factCardId = factCardId
            ..fromSeq = fromSeq
            ..baseRevisionSeq = baseRevisionSeq,
        ),
      )
      .firstWhere((e) => e.dataSource == DataSource.Link)
      .then((r) => r.dataOrThrow(label: _label).BeaconFactCardRestore);

  /// One page of the fact's history timeline; [before] is the opaque
  /// `nextCursor` of the previous page.
  Future<BeaconFactHistoryPage> revisions({
    required String beaconId,
    required String factCardId,
    String? before,
  }) async {
    final r = await _remoteApiService
        .request(
          GBeaconFactCardRevisionsReq(
            (b) => b.vars
              ..beaconId = beaconId
              ..factCardId = factCardId
              ..before = before,
          ),
        )
        .firstWhere((e) => e.dataSource == DataSource.Link);
    final page = r.dataOrThrow(label: _label).BeaconFactCardRevisions;
    return (
      entries: page.entries
          .map((e) => _mapHistoryRow(factCardId, e))
          .toList(growable: false),
      nextCursor: page.nextCursor,
    );
  }

  static const _historyEntryEvent = 'event';

  BeaconFactTimelineEntry _mapHistoryRow(
    String factCardId,
    GBeaconFactCardRevisionsData_BeaconFactCardRevisions_entries row,
  ) {
    final createdAt = DateTime.parse(row.createdAt).toUtc();
    if (row.entry == _historyEntryEvent) {
      return BeaconFactHistoryEvent(
        id: row.entryKey,
        type: row.kind,
        visibilityFrom: row.visibilityFrom,
        visibilityTo: row.visibilityTo,
        actorId: row.actorId,
        actorTitle: row.actorTitle,
        createdAt: createdAt,
      );
    }
    final seq = row.seq!;
    final factText = row.factText ?? '';
    return switch (row.kind) {
      BeaconFactCardRevisionKindBits.edited => BeaconFactHistoryEdited(
        id: row.entryKey,
        factCardId: factCardId,
        seq: seq,
        factText: factText,
        actorId: row.actorId,
        actorTitle: row.actorTitle,
        createdAt: createdAt,
      ),
      BeaconFactCardRevisionKindBits.restored => BeaconFactHistoryRestored(
        id: row.entryKey,
        factCardId: factCardId,
        seq: seq,
        factText: factText,
        restoredFromSeq: row.restoredFromSeq!,
        actorId: row.actorId,
        actorTitle: row.actorTitle,
        createdAt: createdAt,
      ),
      BeaconFactCardRevisionKindBits.imported => BeaconFactHistoryImported(
        id: row.entryKey,
        factCardId: factCardId,
        seq: seq,
        factText: factText,
        actorId: row.actorId,
        actorTitle: row.actorTitle,
        createdAt: createdAt,
      ),
      _ => BeaconFactHistoryCreated(
        id: row.entryKey,
        factCardId: factCardId,
        seq: seq,
        factText: factText,
        actorId: row.actorId,
        actorTitle: row.actorTitle,
        createdAt: createdAt,
      ),
    };
  }

  Future<void> remove({
    required String beaconId,
    required String factCardId,
  }) async {
    await _remoteApiService
        .request(
          GBeaconFactCardRemoveReq(
            (b) => b.vars
              ..beaconId = beaconId
              ..factCardId = factCardId,
          ),
        )
        .firstWhere((e) => e.dataSource == DataSource.Link)
        .then((r) => r.dataOrThrow(label: _label).BeaconFactCardRemove);
  }

  Future<void> setVisibility({
    required String beaconId,
    required String factCardId,
    required int visibility,
  }) async {
    await _remoteApiService
        .request(
          GBeaconFactCardSetVisibilityReq(
            (b) => b.vars
              ..beaconId = beaconId
              ..factCardId = factCardId
              ..visibility = visibility,
          ),
        )
        .firstWhere((e) => e.dataSource == DataSource.Link)
        .then((r) => r.dataOrThrow(label: _label).BeaconFactCardSetVisibility);
  }
}
