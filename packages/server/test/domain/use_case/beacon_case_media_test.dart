import 'dart:async';
import 'dart:typed_data';

import 'package:injectable/injectable.dart' show Environment;
import 'package:logging/logging.dart';
import 'package:mockito/mockito.dart';
import 'package:test/test.dart';

import 'package:tentura_root/domain/entity/beacon_cover_source.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';
import 'package:tentura_server/domain/entity/beacon_entity.dart';
import 'package:tentura_server/domain/entity/beacon_media_state.dart';
import 'package:tentura_server/domain/entity/image_entity.dart';
import 'package:tentura_server/domain/entity/task_entity.dart';
import 'package:tentura_server/domain/entity/user_entity.dart';
import 'package:tentura_server/domain/exception.dart';
import 'package:tentura_server/domain/exception_codes.dart';
import 'package:tentura_server/domain/port/beacon_repository_port.dart';
import 'package:tentura_server/domain/port/coordination_repository_port.dart';
import 'package:tentura_server/domain/port/help_offer_repository_port.dart';
import 'package:tentura_server/domain/port/image_object_gc_port.dart';
import 'package:tentura_server/domain/port/image_repository_port.dart';
import 'package:tentura_server/domain/port/task_repository_port.dart';
import 'package:tentura_server/domain/use_case/beacon_case.dart';
import 'package:tentura_server/env.dart';

import '../../support/fake_beacon_access_guard.dart';

class _MediaBeaconRepo extends Fake implements BeaconRepositoryPort {
  _MediaBeaconRepo(this.locked);

  BeaconEntity locked;
  BeaconMediaSnapshot snapshot = const BeaconMediaSnapshot(
    attachedImageIds: [],
    stagedImageIds: {},
  );

  final addImageCalls = <({String beaconId, String imageId, int position})>[];
  final insertStageCalls = <({String beaconId, String imageId})>[];
  final deleteStageCalls = <String>[];
  final replaceMediaCalls =
      <
        ({
          String beaconId,
          List<String> imageIds,
          String? coverImageId,
          String? coverThumbImageId,
          BeaconCoverSource coverSource,
        })
      >[];
  final setCoverCalls =
      <({String beaconId, String? coverImageId, BeaconCoverSource coverSource})>[];

  List<String> replaceMediaReturns = const [];

  @override
  Future<BeaconEntity> getBeaconById({
    required String beaconId,
    String? filterByUserId,
  }) async {
    if (filterByUserId != null && filterByUserId != locked.author.id) {
      throw StateError('No element');
    }
    return locked;
  }

  @override
  Future<T> runInBeaconStateTransaction<T>({
    required String beaconId,
    required String userId,
    required Future<T> Function(BeaconEntity locked) fn,
  }) => fn(locked);

  @override
  Future<BeaconMediaSnapshot> getMediaSnapshot(String beaconId) async =>
      snapshot;

  @override
  Future<void> addImage({
    required String beaconId,
    required String imageId,
    required int position,
  }) async {
    addImageCalls.add((beaconId: beaconId, imageId: imageId, position: position));
  }

  @override
  Future<void> insertStage({
    required String beaconId,
    required String imageId,
  }) async {
    insertStageCalls.add((beaconId: beaconId, imageId: imageId));
  }

  @override
  Future<void> deleteStage({required String imageId}) async {
    deleteStageCalls.add(imageId);
  }

  @override
  Future<List<String>> replaceMedia({
    required String beaconId,
    required List<String> imageIds,
    required String? coverImageId,
    required BeaconCoverSource coverSource,
    String? coverThumbImageId,
  }) async {
    replaceMediaCalls.add((
      beaconId: beaconId,
      imageIds: imageIds,
      coverImageId: coverImageId,
      coverThumbImageId: coverThumbImageId,
      coverSource: coverSource,
    ));
    return replaceMediaReturns;
  }

  @override
  Future<void> setCover({
    required String beaconId,
    required String? coverImageId,
    required BeaconCoverSource coverSource,
  }) async {
    setCoverCalls.add((
      beaconId: beaconId,
      coverImageId: coverImageId,
      coverSource: coverSource,
    ));
    locked = locked.copyWith(coverImageId: coverImageId);
  }
}

class _TrackingImageRepo extends Fake implements ImageRepositoryPort {
  String nextPutId = 'Inew';
  List<String> ownedIds = const [];
  final compensatedUploads = <({String authorId, String imageId})>[];
  final deletedOwnedRows = <({String authorId, String imageId})>[];

  @override
  Future<String> put({
    required String authorId,
    required Stream<Uint8List> bytes,
  }) async => nextPutId;

  @override
  Future<List<String>> listOwnedIds({required String authorId}) async =>
      ownedIds;

  @override
  Future<void> compensateOrphanedUpload({
    required String imageId,
    required String authorId,
  }) async {
    compensatedUploads.add((authorId: authorId, imageId: imageId));
  }

  @override
  Future<int> deleteOwnedRow({
    required String imageId,
    required String authorId,
  }) async {
    deletedOwnedRows.add((authorId: authorId, imageId: imageId));
    return 1;
  }
}

class _TrackingImageObjectGc extends Fake implements ImageObjectGcPort {
  final enqueued = <({String authorId, String imageId})>[];

  @override
  Future<void> enqueue({
    required String imageId,
    required String authorId,
  }) async {
    enqueued.add((authorId: authorId, imageId: imageId));
  }
}

class _FakeTaskRepo extends Fake implements TaskRepositoryPort {
  Object? failure;

  @override
  Future<String> schedule(TaskEntity task) async {
    if (failure != null) throw failure!;
    return 'T1';
  }
}

class _FakeCoordinationRepo extends Fake
    implements CoordinationRepositoryPort {}

class _FakeHelpOfferRepo extends Fake implements HelpOfferRepositoryPort {}

void main() {
  late _MediaBeaconRepo beaconRepo;
  late _TrackingImageRepo imageRepo;
  late _TrackingImageObjectGc imageObjectGc;
  late _FakeTaskRepo taskRepo;
  late BeaconCase case_;
  final now = DateTime.utc(2026, 6, 25);

  BeaconEntity beacon({List<ImageEntity> images = const []}) => BeaconEntity(
    id: 'B1',
    title: 'Title',
    author: const UserEntity(id: 'Uauth'),
    createdAt: now,
    updatedAt: now,
    status: BeaconStatus.open,
    images: images,
  );

  setUp(() {
    beaconRepo = _MediaBeaconRepo(beacon());
    imageRepo = _TrackingImageRepo();
    imageObjectGc = _TrackingImageObjectGc();
    taskRepo = _FakeTaskRepo();
    case_ = BeaconCase(
      beaconRepo,
      imageRepo,
      imageObjectGc,
      taskRepo,
      _FakeCoordinationRepo(),
      _FakeHelpOfferRepo(),
      FakeBeaconAccessGuard(),
      env: Env(environment: Environment.test),
      logger: Logger('BeaconCaseMediaTest'),
    );
  });

  group('BeaconCase.addImage (legacy)', () {
    test('rejects an unauthorized caller before uploading', () async {
      await expectLater(
        case_.addImage(
          beaconId: 'B1',
          userId: 'Uother',
          imageBytes: const Stream.empty(),
        ),
        throwsA(isA<StateError>()),
      );
      expect(imageRepo.compensatedUploads, isEmpty);
    });

    test('rejects at the cap and compensates the upload', () async {
      beaconRepo.snapshot = const BeaconMediaSnapshot(
        attachedImageIds: [
          'I1', 'I2', 'I3', 'I4', 'I5', 'I6', 'I7', 'I8', 'I9', 'I10',
        ],
        stagedImageIds: {},
      );

      await expectLater(
        case_.addImage(
          beaconId: 'B1',
          userId: 'Uauth',
          imageBytes: const Stream.empty(),
        ),
        throwsA(isA<BeaconCreateException>()),
      );

      expect(imageRepo.compensatedUploads, [
        (authorId: 'Uauth', imageId: 'Inew'),
      ]);
      expect(beaconRepo.addImageCalls, isEmpty);
    });

    test('attaches and sets the cover when none is selected', () async {
      final result = await case_.addImage(
        beaconId: 'B1',
        userId: 'Uauth',
        imageBytes: const Stream.empty(),
      );

      expect(result.imageId, 'Inew');
      expect(beaconRepo.addImageCalls, [
        (beaconId: 'B1', imageId: 'Inew', position: 0),
      ]);
      expect(beaconRepo.setCoverCalls, [
        (
          beaconId: 'B1',
          coverImageId: 'Inew',
          coverSource: BeaconCoverSource.photo,
        ),
      ]);
    });

    test('does not overwrite an existing cover', () async {
      beaconRepo.locked = beaconRepo.locked.copyWith(coverImageId: 'Iold');

      await case_.addImage(
        beaconId: 'B1',
        userId: 'Uauth',
        imageBytes: const Stream.empty(),
      );

      expect(beaconRepo.setCoverCalls, isEmpty);
    });

    test(
      'succeeds even when post-commit hash scheduling fails (non-fatal)',
      () async {
        taskRepo.failure = StateError('task queue unavailable');

        final result = await case_.addImage(
          beaconId: 'B1',
          userId: 'Uauth',
          imageBytes: const Stream.empty(),
        );

        expect(result.imageId, 'Inew');
      },
    );
  });

  group('BeaconCase.beaconStageImage', () {
    test('rejects an unauthorized caller before uploading', () async {
      await expectLater(
        case_.beaconStageImage(
          beaconId: 'B1',
          userId: 'Uother',
          imageBytes: const Stream.empty(),
        ),
        throwsA(isA<StateError>()),
      );
      expect(imageRepo.compensatedUploads, isEmpty);
    });

    test('rejects at the cap and compensates the upload', () async {
      beaconRepo.snapshot = const BeaconMediaSnapshot(
        attachedImageIds: [],
        stagedImageIds: {
          'I1', 'I2', 'I3', 'I4', 'I5', 'I6', 'I7', 'I8', 'I9', 'I10',
        },
      );
      imageRepo.ownedIds = ['Inew'];

      await expectLater(
        case_.beaconStageImage(
          beaconId: 'B1',
          userId: 'Uauth',
          imageBytes: const Stream.empty(),
        ),
        throwsA(isA<BeaconCreateException>()),
      );

      expect(imageRepo.compensatedUploads, [
        (authorId: 'Uauth', imageId: 'Inew'),
      ]);
      expect(beaconRepo.insertStageCalls, isEmpty);
    });

    test(
      'rejects when the uploaded image is not owned under the lock and compensates',
      () async {
        imageRepo.ownedIds = const [];

        await expectLater(
          case_.beaconStageImage(
            beaconId: 'B1',
            userId: 'Uauth',
            imageBytes: const Stream.empty(),
          ),
          throwsA(isA<IdNotFoundException>()),
        );

        expect(imageRepo.compensatedUploads, [
          (authorId: 'Uauth', imageId: 'Inew'),
        ]);
        expect(beaconRepo.insertStageCalls, isEmpty);
      },
    );

    test('stages an invisible image without touching attachments', () async {
      imageRepo.ownedIds = ['Inew'];

      final result = await case_.beaconStageImage(
        beaconId: 'B1',
        userId: 'Uauth',
        imageBytes: const Stream.empty(),
      );

      expect(result.imageId, 'Inew');
      expect(result.beaconId, 'B1');
      expect(beaconRepo.insertStageCalls, [
        (beaconId: 'B1', imageId: 'Inew'),
      ]);
      expect(beaconRepo.addImageCalls, isEmpty);
    });

    test(
      'succeeds even when post-commit hash scheduling fails (non-fatal)',
      () async {
        imageRepo.ownedIds = ['Inew'];
        taskRepo.failure = StateError('task queue unavailable');

        final result = await case_.beaconStageImage(
          beaconId: 'B1',
          userId: 'Uauth',
          imageBytes: const Stream.empty(),
        );

        expect(result.imageId, 'Inew');
      },
    );
  });

  group('BeaconCase.beaconSetMedia', () {
    test('rejects an unauthorized caller', () async {
      await expectLater(
        case_.beaconSetMedia(
          beaconId: 'B1',
          userId: 'Uother',
          imageIds: const [],
          coverSource: 0,
        ),
        throwsA(isA<EvaluationException>()),
      );
    });

    test('rejects duplicate ids with the exact media-invalid code', () async {
      beaconRepo.snapshot = const BeaconMediaSnapshot(
        attachedImageIds: ['I1'],
        stagedImageIds: {},
      );

      await expectLater(
        case_.beaconSetMedia(
          beaconId: 'B1',
          userId: 'Uauth',
          imageIds: const ['I1', 'I1'],
          coverImageId: 'I1',
          coverSource: 0,
        ),
        throwsA(
          isA<BeaconMediaInvalidException>().having(
            (e) => e.code.codeNumber,
            'codeNumber',
            const BeaconExceptionCodes(
              BeaconExceptionCode.beaconMediaInvalid,
            ).codeNumber,
          ),
        ),
      );
    });

    test('rejects a list over the per-beacon cap', () async {
      final ids = List.generate(11, (i) => 'I$i');
      beaconRepo.snapshot = BeaconMediaSnapshot(
        attachedImageIds: ids,
        stagedImageIds: const {},
      );

      await expectLater(
        case_.beaconSetMedia(
          beaconId: 'B1',
          userId: 'Uauth',
          imageIds: ids,
          coverImageId: ids.first,
          coverSource: 0,
        ),
        throwsA(isA<BeaconMediaInvalidException>()),
      );
    });

    test('rejects an unknown cover-source wire value', () async {
      beaconRepo.snapshot = const BeaconMediaSnapshot(
        attachedImageIds: ['I1'],
        stagedImageIds: {},
      );

      await expectLater(
        case_.beaconSetMedia(
          beaconId: 'B1',
          userId: 'Uauth',
          imageIds: const ['I1'],
          coverImageId: 'I1',
          coverSource: 99,
        ),
        throwsA(isA<BeaconMediaInvalidException>()),
      );
    });

    test('rejects a media id outside the attached-or-staged set', () async {
      beaconRepo.snapshot = const BeaconMediaSnapshot(
        attachedImageIds: ['I1'],
        stagedImageIds: {},
      );

      await expectLater(
        case_.beaconSetMedia(
          beaconId: 'B1',
          userId: 'Uauth',
          imageIds: const ['I1', 'Iunknown'],
          coverImageId: 'I1',
          coverSource: 0,
        ),
        throwsA(
          isA<BeaconImageNotAttachedException>().having(
            (e) => e.code.codeNumber,
            'codeNumber',
            const BeaconExceptionCodes(
              BeaconExceptionCode.beaconImageNotAttached,
            ).codeNumber,
          ),
        ),
      );
    });

    test('rejects a cover outside the desired media set', () async {
      beaconRepo.snapshot = const BeaconMediaSnapshot(
        attachedImageIds: ['I1', 'I2'],
        stagedImageIds: {},
      );

      await expectLater(
        case_.beaconSetMedia(
          beaconId: 'B1',
          userId: 'Uauth',
          imageIds: const ['I1'],
          coverImageId: 'I2',
          coverSource: 0,
        ),
        throwsA(
          isA<BeaconCoverNotAttachedException>().having(
            (e) => e.code.codeNumber,
            'codeNumber',
            const BeaconExceptionCodes(
              BeaconExceptionCode.beaconCoverNotAttached,
            ).codeNumber,
          ),
        ),
      );
    });

    test('rejects a non-null cover when the desired list is empty', () async {
      beaconRepo.snapshot = const BeaconMediaSnapshot(
        attachedImageIds: ['I1'],
        stagedImageIds: {},
      );

      await expectLater(
        case_.beaconSetMedia(
          beaconId: 'B1',
          userId: 'Uauth',
          imageIds: const [],
          coverImageId: 'I1',
          coverSource: 0,
        ),
        throwsA(isA<BeaconMediaInvalidException>()),
      );
    });

    test('rejects a null cover when the desired list is non-empty', () async {
      beaconRepo.snapshot = const BeaconMediaSnapshot(
        attachedImageIds: ['I1'],
        stagedImageIds: {},
      );

      await expectLater(
        case_.beaconSetMedia(
          beaconId: 'B1',
          userId: 'Uauth',
          imageIds: const ['I1'],
          coverSource: 0,
        ),
        throwsA(isA<BeaconMediaInvalidException>()),
      );
    });

    test(
      'reconciles atomically: promotes staged ids, preserves the desired order, and GCs every removed row',
      () async {
        beaconRepo.snapshot = const BeaconMediaSnapshot(
          attachedImageIds: ['I1', 'I2'],
          stagedImageIds: {'I3'},
        );
        beaconRepo.replaceMediaReturns = ['I2'];

        final result = await case_.beaconSetMedia(
          beaconId: 'B1',
          userId: 'Uauth',
          imageIds: const ['I3', 'I1'],
          coverImageId: 'I3',
          coverSource: 1,
        );

        expect(result.id, 'B1');
        expect(beaconRepo.replaceMediaCalls, hasLength(1));
        final call = beaconRepo.replaceMediaCalls.single;
        expect(call.beaconId, 'B1');
        expect(call.imageIds, ['I3', 'I1']);
        expect(call.coverImageId, 'I3');
        expect(call.coverSource, BeaconCoverSource.symbol);
        expect(imageObjectGc.enqueued, [
          (authorId: 'Uauth', imageId: 'I2'),
        ]);
        expect(imageRepo.deletedOwnedRows, [
          (authorId: 'Uauth', imageId: 'I2'),
        ]);
      },
    );

    test(
      'idempotent retry: reconciling to the already-attached set removes nothing',
      () async {
        beaconRepo.snapshot = const BeaconMediaSnapshot(
          attachedImageIds: ['I1', 'I2'],
          stagedImageIds: {},
        );
        beaconRepo.replaceMediaReturns = const [];

        await case_.beaconSetMedia(
          beaconId: 'B1',
          userId: 'Uauth',
          imageIds: const ['I1', 'I2'],
          coverImageId: 'I1',
          coverSource: 0,
        );

        expect(imageObjectGc.enqueued, isEmpty);
        expect(imageRepo.deletedOwnedRows, isEmpty);
      },
    );
  });
}
