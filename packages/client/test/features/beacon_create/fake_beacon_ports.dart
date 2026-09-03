import 'dart:async';
import 'dart:typed_data';

import 'package:tentura_root/domain/entity/beacon_cover_source.dart';

import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/image_entity.dart';
import 'package:tentura/domain/entity/image_picked.dart';
import 'package:tentura/domain/port/beacon_image_port.dart';
import 'package:tentura/domain/port/beacon_write_port.dart';
import 'package:tentura/domain/use_case/beacon_create_case.dart';

/// 1×1 opaque PNG, so widgets under test decode a real image.
const kTinyPng = [
  0x89,
  0x50,
  0x4E,
  0x47,
  0x0D,
  0x0A,
  0x1A,
  0x0A,
  0x00,
  0x00,
  0x00,
  0x0D,
  0x49,
  0x48,
  0x44,
  0x52,
  0x00,
  0x00,
  0x00,
  0x01,
  0x00,
  0x00,
  0x00,
  0x01,
  0x08,
  0x02,
  0x00,
  0x00,
  0x00,
  0x90,
  0x77,
  0x53,
  0xDE,
  0x00,
  0x00,
  0x00,
  0x0C,
  0x49,
  0x44,
  0x41,
  0x54,
  0x08,
  0xD7,
  0x63,
  0xF8,
  0xCF,
  0xC0,
  0x00,
  0x00,
  0x03,
  0x01,
  0x01,
  0x00,
  0x18,
  0xDD,
  0x8D,
  0xB0,
  0x00,
  0x00,
  0x00,
  0x00,
  0x49,
  0x45,
  0x4E,
  0x44,
  0xAE,
  0x42,
  0x60,
  0x82,
];

/// Recorded `setMedia` command, so tests can assert exactly one reconciliation.
class SetMediaCall {
  const SetMediaCall({
    required this.beaconId,
    required this.imageIds,
    required this.coverImageId,
    required this.coverThumbImageId,
    required this.coverSource,
  });

  final String beaconId;
  final List<String> imageIds;
  final String? coverImageId;
  final String? coverThumbImageId;
  final BeaconCoverSource coverSource;
}

/// Defers [fetchBeaconById] until [release] completes (for async-load races).
class DelayedFakeBeaconWritePort extends FakeBeaconWritePort {
  DelayedFakeBeaconWritePort({
    required this.release,
    super.beacon,
  });

  final Completer<void> release;

  @override
  Future<Beacon> fetchBeaconById(String id) async {
    await release.future;
    return super.fetchBeaconById(id);
  }
}

class FakeBeaconWritePort implements BeaconWritePort {
  FakeBeaconWritePort({Beacon? beacon}) : beacon = beacon ?? Beacon.empty;

  /// Server view returned by [fetchBeaconById] and the write commands.
  Beacon beacon;

  /// Staged ids handed out to successful stage calls, in order.
  final stageIds = <String>[];

  /// Local keys presented to [stageImage], in order.
  final stagedKeys = <String>[];

  final setMediaCalls = <SetMediaCall>[];
  final createdFields = <Beacon>[];
  final updatedDraftFields = <Beacon>[];
  final updatedFields = <Beacon>[];
  final publishedIds = <String>[];
  final deletedIds = <String>[];

  Exception? createError;
  Exception? updateDraftError;
  Exception? updateError;

  /// When set, [create] waits until this completes (overlapping create tests).
  Completer<void>? createHold;

  /// Fails the nth (0-based) `stageImage` attempt.
  int? failStageAtCall;
  Exception? stageError;

  /// How many ids have been handed out; a failed attempt consumes none.
  int _issuedIds = 0;

  /// Fails the nth (0-based) `setMedia` call.
  int? failSetMediaAtCall;
  Exception? setMediaError;

  int _stageCalls = 0;

  @override
  Future<Beacon> fetchBeaconById(String id) async => beacon;

  @override
  Future<Beacon> create(Beacon fields, {bool draft = false}) async {
    final hold = createHold;
    if (hold != null) await hold.future;
    if (createError != null) throw createError!;
    createdFields.add(fields);
    return beacon = _applyFields(
      fields,
      id: beacon.id.isEmpty ? 'server-beacon' : beacon.id,
    );
  }

  @override
  Future<Beacon> updateDraft(Beacon fields) async {
    if (updateDraftError != null) throw updateDraftError!;
    updatedDraftFields.add(fields);
    return beacon = _applyFields(fields, id: fields.id);
  }

  @override
  Future<Beacon> update(Beacon fields) async {
    if (updateError != null) throw updateError!;
    updatedFields.add(fields);
    return beacon = _applyFields(fields, id: fields.id);
  }

  /// Field writes never touch media; only [setMedia] does.
  Beacon _applyFields(Beacon fields, {required String id}) => beacon.copyWith(
    id: id,
    title: fields.title,
    needs: fields.needs,
    primaryNeedSlug: fields.primaryNeedSlug,
    coverSource: fields.coverSource,
  );

  @override
  Future<void> publishDraft(String id) async => publishedIds.add(id);

  @override
  Future<void> delete(String id) async => deletedIds.add(id);

  @override
  Future<String> stageImage({
    required String beaconId,
    required ImageEntity image,
  }) async {
    final attempt = _stageCalls++;
    stagedKeys.add(image.key);
    if (failStageAtCall == attempt) {
      throw stageError ?? Exception('stage failed');
    }
    final issued = _issuedIds++;
    return issued < stageIds.length ? stageIds[issued] : 'staged-$issued';
  }

  @override
  Future<Beacon> setMedia({
    required String beaconId,
    required List<String> imageIds,
    required String? coverImageId,
    required String? coverThumbImageId,
    required BeaconCoverSource coverSource,
  }) async {
    final call = setMediaCalls.length;
    setMediaCalls.add(
      SetMediaCall(
        beaconId: beaconId,
        imageIds: imageIds,
        coverImageId: coverImageId,
        coverThumbImageId: coverThumbImageId,
        coverSource: coverSource,
      ),
    );
    if (failSetMediaAtCall == call) {
      throw setMediaError ?? Exception('setMedia failed');
    }
    final thumb = coverThumbImageId == null
        ? null
        : ImageEntity(id: coverThumbImageId, authorId: 'author-1');
    return beacon = beacon.copyWith(
      id: beaconId,
      images: [
        for (final id in imageIds) ImageEntity(id: id, authorId: 'author-1'),
      ],
      coverImageId: coverImageId,
      coverThumb: thumb,
      coverSource: coverSource,
    );
  }
}

class FakeBeaconImagePort implements BeaconImagePort {
  FakeBeaconImagePort({this.picked = const [], this.bytes});

  List<ImagePicked> picked;
  Uint8List? bytes;
  Exception? fetchError;
  final fetchedUrls = <String>[];

  @override
  Future<List<ImagePicked>> pickMultipleImages() async => picked;

  @override
  Future<Uint8List> fetchImageBytes(String url) async {
    fetchedUrls.add(url);
    if (fetchError != null) throw fetchError!;
    return bytes ?? Uint8List.fromList(kTinyPng);
  }
}

class FakeImageCropUi implements ImageCropUiPort {
  FakeImageCropUi({this.result});

  ImagePicked? result;
  int calls = 0;

  @override
  Future<ImagePicked?> cropSquare(Uint8List bytes) async {
    calls++;
    return result;
  }
}

BeaconCreateCase fakeBeaconCreateCase({
  FakeBeaconWritePort? write,
  FakeBeaconImagePort? images,
}) => BeaconCreateCase(
  write ?? FakeBeaconWritePort(),
  images ?? FakeBeaconImagePort(),
);
