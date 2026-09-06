import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:tentura_root/domain/entity/beacon_child_command_outcome.dart';
import 'package:tentura_root/domain/entity/beacon_cover_source.dart';
import 'package:tentura_root/domain/entity/beacon_creation_context.dart';

import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/image_entity.dart';
import 'package:tentura/domain/use_case/beacon_create_case.dart';
import 'package:tentura/domain/use_case/beacon_hierarchy_case.dart';
import 'package:tentura/features/beacon/domain/beacon_hierarchy_exception.dart';
import 'package:tentura/features/beacon/domain/port/beacon_hierarchy_repository_port.dart';

import '../../features/beacon_create/fake_beacon_ports.dart';
import 'fake_beacon_hierarchy_ports.dart';

const _parentId = 'parent-1';
const _context = BeaconCreationContextChild(parentBeaconId: _parentId);

ImageEntity _local(String key) => ImageEntity(
  localKey: key,
  fileName: '$key.jpg',
  imageBytes: Uint8List.fromList([1, 2, 3]),
);

Beacon _fields({String id = '', String title = 'Child title', String description = 'Child body'}) =>
    Beacon.empty.copyWith(
      id: id,
      title: title,
      description: description,
      needs: {'transport'},
      primaryNeedSlug: 'transport',
      coverSource: BeaconCoverSource.photo,
    );

BeaconSaveCommand _save({
  String id = '',
  String title = 'Child title',
  String description = 'Child body',
  List<ImageEntity> images = const [],
  String? coverKey,
}) => BeaconSaveCommand(
  fields: _fields(id: id, title: title, description: description),
  images: images,
  coverKey: coverKey,
  draft: true,
);

BeaconChildSaveCommand _child({
  required String clientCommandId,
  required BeaconSaveCommand save,
  BeaconSaveCommand? exactRetrySnapshot,
}) => BeaconChildSaveCommand(
  creationContext: _context,
  clientCommandId: clientCommandId,
  saveCommand: save,
  exactRetrySnapshot: exactRetrySnapshot,
);

BeaconHierarchyCase _sut({
  FakeBeaconWritePort? write,
  FakeBeaconHierarchyRepositoryPort? hierarchy,
  InMemoryBeaconChildCommandStore? store,
}) {
  final w = write ?? FakeBeaconWritePort();
  return BeaconHierarchyCase(
    hierarchy ?? FakeBeaconHierarchyRepositoryPort(),
    BeaconCreateCase(w, FakeBeaconImagePort()),
    w,
    store ?? InMemoryBeaconChildCommandStore(),
  );
}

void main() {
  group('clientCommandId persistence', () {
    test('openComposer mints and stores a command id for new child attempts', () async {
      final store = InMemoryBeaconChildCommandStore();
      final sut = _sut(store: store);

      final session = await sut.openComposer(creationContext: _context);

      expect(session.clientCommandId, isNotEmpty);
      expect(await store.read(_context), session.clientCommandId);
    });

    test('restored draft uses canonical id without a fresh command id', () async {
      final sut = _sut();

      final session = await sut.openComposer(
        creationContext: _context,
        restoredDraftBeaconId: 'existing-draft',
      );

      expect(session.clientCommandId, isNull);
      expect(session.restoredDraftBeaconId, 'existing-draft');
    });
  });

  group('lost creation response', () {
    test('retry reuses the same clientCommandId and never mints a second key', () async {
      final store = InMemoryBeaconChildCommandStore();
      final hierarchy = FakeBeaconHierarchyRepositoryPort()
        ..createError = Exception('timeout');
      final sut = _sut(hierarchy: hierarchy, store: store);
      final session = await sut.openComposer(creationContext: _context);
      final cmd = _child(
        clientCommandId: session.clientCommandId!,
        save: _save(title: 'Draft'),
      );

      await expectLater(
        sut.ensureChildDraft(cmd),
        throwsA(isA<BeaconSaveFailure>()),
      );

      hierarchy.createError = null;
      final result = await sut.ensureChildDraft(cmd);

      expect(hierarchy.createAttempts, 2);
      expect(hierarchy.lastClientCommandId, session.clientCommandId);
      expect(await store.read(_context), isNull);
      expect(result.beacon.id, 'child-${session.clientCommandId}');
    });
  });

  group('changed form after unknown result', () {
    test('edited fields apply as update to recovered id, not a second create', () async {
      final hierarchy = FakeBeaconHierarchyRepositoryPort();
      final write = FakeBeaconWritePort();
      final sut = _sut(hierarchy: hierarchy, write: write);
      final session = await sut.openComposer(creationContext: _context);
      final original = _save(title: 'Original title', description: 'Original body');
      final edited = _save(title: 'Edited title', description: 'Edited body');
      final cmd = _child(
        clientCommandId: session.clientCommandId!,
        save: edited,
        exactRetrySnapshot: original,
      );

      final result = await sut.ensureChildDraft(cmd);

      expect(hierarchy.createCalls, hasLength(1));
      expect(hierarchy.createCalls.single['title'], 'Original title');
      expect(write.updatedDraftFields, hasLength(1));
      expect(write.updatedDraftFields.single.title, 'Edited title');
      expect(result.beacon.id, startsWith('child-'));
    });
  });

  group('stage/reconcile/publish failure recovery', () {
    test('stage failure preserves draft id and completed stages', () async {
      final write = FakeBeaconWritePort()
        ..stageIds.add('s1')
        ..failStageAtCall = 1;
      final hierarchy = FakeBeaconHierarchyRepositoryPort();
      final sut = _sut(write: write, hierarchy: hierarchy);
      final session = await sut.openComposer(creationContext: _context);
      final cmd = _child(
        clientCommandId: session.clientCommandId!,
        save: _save(
          images: [_local('k1'), _local('k2')],
          coverKey: 'k1',
        ),
      );

      BeaconSaveFailure? failure;
      try {
        await sut.ensureChildDraft(cmd);
      } on BeaconSaveFailure catch (e) {
        failure = e;
      }

      expect(failure, isNotNull);
      expect(failure!.phase, BeaconSavePhase.stage);
      expect(failure.beaconId, isNotEmpty);
      expect(failure.images.first.id, 's1');
      expect(failure.clientCommandId, session.clientCommandId);
    });

    test('reconcile failure preserves staged ids', () async {
      final write = FakeBeaconWritePort()
        ..stageIds.add('s1')
        ..failSetMediaAtCall = 0;
      final sut = _sut(write: write);
      final session = await sut.openComposer(creationContext: _context);
      final created = await sut.ensureChildDraft(
        _child(
          clientCommandId: session.clientCommandId!,
          save: _save(),
        ),
      );
      final cmd = _child(
        clientCommandId: session.clientCommandId!,
        save: _save(
          id: created.beacon.id,
          images: const [ImageEntity(id: 's1', authorId: 'author-1')],
          coverKey: 's1',
        ),
      );

      await expectLater(
        sut.saveChildDraft(cmd),
        throwsA(
          isA<BeaconSaveFailure>().having(
            (e) => e.phase,
            'phase',
            BeaconSavePhase.reconcile,
          ),
        ),
      );
    });

    test('publish failure uses publish phase and keeps draft id', () async {
      final write = FakeBeaconWritePort()
        ..publishError = Exception('parent closed');
      final sut = _sut(write: write);
      final session = await sut.openComposer(creationContext: _context);
      final cmd = _child(
        clientCommandId: session.clientCommandId!,
        save: _save(id: 'child-draft'),
      );

      await expectLater(
        sut.publishChildDraft(
          beaconId: 'child-draft',
          command: cmd,
          images: const [],
          coverKey: null,
          coverThumb: null,
        ),
        throwsA(
          isA<BeaconSaveFailure>()
              .having((e) => e.phase, 'phase', BeaconSavePhase.publish)
              .having((e) => e.beaconId, 'beaconId', 'child-draft'),
        ),
      );
    });
  });

  group('denied publication retaining draft', () {
    test('publish-time parent rejection keeps draft intact', () async {
      final write = FakeBeaconWritePort()
        ..publishError = const BeaconParentNotCoordinatableException();
      final sut = _sut(write: write);
      final session = await sut.openComposer(creationContext: _context);
      final cmd = _child(
        clientCommandId: session.clientCommandId!,
        save: _save(id: 'child-draft'),
      );

      await expectLater(
        sut.publishChildDraft(
          beaconId: 'child-draft',
          command: cmd,
          images: const [],
          coverKey: null,
          coverThumb: null,
        ),
        throwsA(isA<BeaconSaveFailure>()),
      );
      expect(write.deletedIds, isEmpty);
    });
  });

  group('promotion conflict', () {
    test('alreadyPromoted is never treated as this drafts successful publication', () async {
      final hierarchy = FakeBeaconHierarchyRepositoryPort()
        ..createOutcomeOverride = const BeaconChildCreateOutcome(
          outcome: BeaconChildCommandOutcome.alreadyPromoted,
          beaconId: 'existing-child',
        );
      final sut = _sut(hierarchy: hierarchy);
      final session = await sut.openComposer(creationContext: _context);
      final cmd = _child(
        clientCommandId: session.clientCommandId!,
        save: _save(),
      );

      await expectLater(
        sut.ensureChildDraft(cmd),
        throwsA(
          isA<BeaconChildPromotionConflict>().having(
            (e) => e.existingChildBeaconId,
            'existingChildBeaconId',
            'existing-child',
          ),
        ),
      );
    });
  });

  group('promotion source preview', () {
    test('seeds description only from authorized source preview', () async {
      final hierarchy = FakeBeaconHierarchyRepositoryPort();
      final sut = _sut(hierarchy: hierarchy);
      const promoContext = BeaconCreationContextPromotedChild(
        parentBeaconId: _parentId,
        sourceMessageId: 'msg-1',
      );

      final session = await sut.openComposer(creationContext: promoContext);

      expect(session.descriptionSeed, 'Promoted text');
      expect(session.promotionSource?.textPreview, 'Promoted text');
    });
  });

  group('hierarchy field failures', () {
    test('forbidden create preserves command id for retry', () async {
      final hierarchy = FakeBeaconHierarchyRepositoryPort()
        ..createError = const BeaconChildCreateForbiddenException();
      final store = InMemoryBeaconChildCommandStore();
      final sut = _sut(hierarchy: hierarchy, store: store);
      final session = await sut.openComposer(creationContext: _context);
      final cmd = _child(
        clientCommandId: session.clientCommandId!,
        save: _save(),
      );

      await expectLater(
        sut.ensureChildDraft(cmd),
        throwsA(
          isA<BeaconSaveFailure>()
              .having((e) => e.phase, 'phase', BeaconSavePhase.fields)
              .having((e) => e.clientCommandId, 'clientCommandId', session.clientCommandId),
        ),
      );
      expect(await store.read(_context), session.clientCommandId);
    });
  });
}
