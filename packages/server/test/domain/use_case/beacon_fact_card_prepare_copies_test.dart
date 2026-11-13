import 'dart:convert';
import 'dart:typed_data';

import 'package:injectable/injectable.dart' show Environment;
import 'package:logging/logging.dart';
import 'package:mockito/mockito.dart';
import 'package:test/test.dart';

import 'package:tentura_server/consts/beacon_fact_card_consts.dart';
import 'package:tentura_server/consts/beacon_room_consts.dart';
import 'package:tentura_server/domain/entity/beacon_fact_room_access.dart';
import 'package:tentura_server/domain/entity/fact_copy_source.dart';
import 'package:tentura_server/domain/entity/prepared_fact_copy.dart';
import 'package:tentura_server/domain/entity/task_entity.dart';
import 'package:tentura_server/domain/exception.dart';
import 'package:tentura_server/domain/port/beacon_fact_card_repository_port.dart';
import 'package:tentura_server/domain/port/beacon_hierarchy_repository_port.dart';
import 'package:tentura_server/domain/port/beacon_room_repository_port.dart';
import 'package:tentura_server/domain/port/image_repository_port.dart';
import 'package:tentura_server/domain/port/task_repository_port.dart';
import 'package:tentura_server/domain/use_case/beacon_fact_card_case.dart';
import 'package:tentura_server/env.dart';

import '../../support/fake_beacon_access_guard.dart';

const _actor = 'Uactorcopy01';
const _sourceAuthor = 'Uauthorsrc01';
const _sourceRequest = 'Bsourcereq01';
const _sourcePost = 'Bsourcepst01';
const _otherRequest = 'Botherreq001';
const _destination = 'Bdestinat001';

/// A syntactically valid image id (UUID) for source image [n].
String _sourceImageId(int n) =>
    '00000000-0000-4000-8000-${n.toString().padLeft(12, '0')}';

/// Source image attachment [n] as stored on a fact's head revision.
Map<String, Object?> _imageEntry(int n, {int position = 0}) => {
  'id': 'Asrcatt${n.toString().padLeft(5, '0')}',
  'kind': BeaconRoomMessageAttachmentKind.image,
  'position': position,
  'mime': 'image/png',
  'sizeBytes': 1000 + n,
  'fileName': 'picture-$n.png',
  'imageId': _sourceImageId(n),
  'imageAuthorId': _sourceAuthor,
  'blurHash': 'LKO2?U%2Tw=w$n',
  'width': 40 + n,
  'height': 30 + n,
};

FactCopySourceAttachment _image(int n, {int position = 0}) =>
    FactCopySourceAttachment(
      fields: _imageEntry(n, position: position),
      imageExists: true,
    );

FactCopySource _fact(
  String id, {
  String beaconId = _sourceRequest,
  int beaconKind = 0,
  int status = BeaconFactCardStatusBits.active,
  int visibility = BeaconFactCardVisibilityBits.public,
  int headRevisionSeq = 3,
  String? headText,
  List<FactCopySourceAttachment> attachments = const [],
}) => FactCopySource(
  factCardId: id,
  beaconId: beaconId,
  beaconKind: beaconKind,
  status: status,
  visibility: visibility,
  headRevisionSeq: headRevisionSeq,
  headText: headText ?? 'Text of $id',
  attachments: attachments,
);

BeaconFactRoomAccess _access({
  bool canRead = true,
  bool canUseRoom = true,
  int kind = 0,
}) => BeaconFactRoomAccess(
  beaconStatus: 0,
  canUseRoom: canUseRoom,
  canReadContent: canRead,
  exists: true,
  kind: kind,
  isDraft: false,
  isExpiredPost: false,
);

class _Facts extends Fake implements BeaconFactCardRepositoryPort {
  final sources = <String, FactCopySource>{};
  final accessByBeacon = <String, BeaconFactRoomAccess>{};

  /// destination beacon id → (origin fact id → live copy id).
  final liveCopies = <String, Map<String, String>>{};
  int liveCopyLookups = 0;

  /// Every user id source access was checked for.
  final accessUserIds = <String>[];

  void add(FactCopySource source) => sources[source.factCardId] = source;

  @override
  Future<List<FactCopySource>> loadCopySources({
    required List<String> factCardIds,
  }) async => [
    for (final id in factCardIds) ?sources[id],
  ];

  @override
  Future<Map<String, String>> liveCopiesByOrigin({
    required String beaconId,
    required List<String> originFactCardIds,
  }) async {
    liveCopyLookups++;
    final copies = liveCopies[beaconId] ?? const {};
    return {
      for (final id in originFactCardIds) id: ?copies[id],
    };
  }

  @override
  Future<BeaconFactRoomAccess> loadRoomAccess({
    required String beaconId,
    required String userId,
  }) async {
    accessUserIds.add(userId);
    return accessByBeacon[beaconId] ?? _access();
  }
}

class _Images extends Fake implements ImageRepositoryPort {
  final gets = <String>[];
  final puts = <({String authorId, Uint8List bytes, String imageId})>[];
  final compensated = <({String imageId, String authorId})>[];

  /// Source image id → error thrown by [get].
  final getErrors = <String, Object>{};

  /// 1-based put call number → error thrown by that [put].
  final putErrors = <int, Object>{};

  static Uint8List bytesOf(String imageId) =>
      Uint8List.fromList(utf8.encode('blob:$imageId'));

  @override
  Future<Uint8List> get({required String id}) async {
    gets.add(id);
    if (getErrors[id] case final error?) {
      Error.throwWithStackTrace(error, StackTrace.current);
    }
    return bytesOf(id);
  }

  @override
  Future<String> put({
    required String authorId,
    required Stream<Uint8List> bytes,
  }) async {
    final call = puts.length + attemptedFailedPuts + 1;
    final builder = BytesBuilder(copy: false);
    await bytes.forEach(builder.add);
    if (putErrors[call] case final error?) {
      attemptedFailedPuts++;
      Error.throwWithStackTrace(error, StackTrace.current);
    }
    final imageId =
        'ffffffff-0000-4000-8000-${call.toString().padLeft(12, '0')}';
    puts.add((
      authorId: authorId,
      bytes: builder.takeBytes(),
      imageId: imageId,
    ));
    return imageId;
  }

  int attemptedFailedPuts = 0;

  List<String> get putIds => [for (final p in puts) p.imageId];

  Set<String> get compensatedIds => {for (final c in compensated) c.imageId};

  @override
  Future<void> compensateOrphanedUpload({
    required String imageId,
    required String authorId,
  }) async {
    compensated.add((imageId: imageId, authorId: authorId));
  }
}

class _Tasks extends Fake implements TaskRepositoryPort {
  final scheduled = <TaskEntity>[];

  @override
  Future<String> schedule(TaskEntity task) async {
    scheduled.add(task);
    return 'task-${scheduled.length}';
  }
}

class _UnusedRoom extends Fake implements BeaconRoomRepositoryPort {}

class _UnusedHierarchy extends Fake implements BeaconHierarchyRepositoryPort {}

List<Map<String, Object?>> _attachmentsOf(PreparedFactCopy copy) => [
  for (final e in jsonDecode(copy.attachmentsJson) as List<Object?>)
    Map<String, Object?>.from(e! as Map),
];

void main() {
  late _Facts facts;
  late _Images images;
  late _Tasks tasks;
  late BeaconFactCardCase case_;

  setUp(() {
    facts = _Facts();
    images = _Images();
    tasks = _Tasks();
    case_ = BeaconFactCardCase(
      facts,
      _UnusedRoom(),
      images,
      tasks,
      _UnusedHierarchy(),
      FakeBeaconAccessGuard(),
      env: Env(environment: Environment.test),
      logger: Logger('BeaconFactCardPrepareCopiesTest'),
    );
  });

  Future<({List<PreparedFactCopy> prepared, Map<String, String> alreadyThere})>
  prepare(
    List<String> ids, {
    String? destination = _destination,
    String? requiredSource,
    bool skipUnavailable = false,
  }) async {
    final result = await case_.prepareCopies(
      sourceFactCardIds: ids,
      actorUserId: _actor,
      destinationBeaconId: destination,
      requiredSourceBeaconId: requiredSource,
      skipUnavailable: skipUnavailable,
    );
    expect(
      facts.accessUserIds.toSet(),
      everyElement(_actor),
      reason: 'source access is checked for the actor',
    );
    return (prepared: result.prepared, alreadyThere: result.alreadyThere);
  }

  List<String> originsOf(
    ({List<PreparedFactCopy> prepared, Map<String, String> alreadyThere}) r,
  ) => [for (final p in r.prepared) p.originFactCardId];

  group('A fact the actor cannot copy is refused or skipped', () {
    const okId = 'Fcopyok00001';

    /// Each cause, set up so that the fact under test has one image.
    final causes =
        <
          String,
          ({String id, String? requiredSource, void Function() arrange})
        >{
          'a missing fact': (
            id: 'Fmissing0001',
            requiredSource: null,
            arrange: () {},
          ),
          'a removed fact': (
            id: 'Fremoved0001',
            requiredSource: null,
            arrange: () => facts.add(
              _fact(
                'Fremoved0001',
                status: BeaconFactCardStatusBits.removed,
                attachments: [_image(1)],
              ),
            ),
          ),
          'a request-visible fact the actor cannot read': (
            id: 'Fnoread00001',
            requiredSource: null,
            arrange: () {
              facts
                ..add(
                  _fact(
                    'Fnoread00001',
                    beaconId: _otherRequest,
                    attachments: [_image(1)],
                  ),
                )
                ..accessByBeacon[_otherRequest] = _access(
                  canRead: false,
                  canUseRoom: false,
                );
            },
          ),
          'a discussion-only fact the actor cannot use the room for': (
            id: 'Fnoroom00001',
            requiredSource: null,
            arrange: () {
              facts
                ..add(
                  _fact(
                    'Fnoroom00001',
                    beaconId: _otherRequest,
                    visibility: BeaconFactCardVisibilityBits.room,
                    attachments: [_image(1)],
                  ),
                )
                ..accessByBeacon[_otherRequest] = _access(canUseRoom: false);
            },
          ),
          'a fact that already lives in the destination': (
            id: 'Fsameep00001',
            requiredSource: null,
            arrange: () => facts.add(
              _fact(
                'Fsameep00001',
                beaconId: _destination,
                attachments: [_image(1)],
              ),
            ),
          ),
          'a fact outside the required source episode': (
            id: 'Foutside0001',
            requiredSource: _sourceRequest,
            arrange: () => facts.add(
              _fact(
                'Foutside0001',
                beaconId: _otherRequest,
                attachments: [_image(1)],
              ),
            ),
          ),
        };

    for (final MapEntry(key: name, value: c) in causes.entries) {
      test('$name throws FactCopySourceUnavailableException', () async {
        c.arrange();
        await expectLater(
          prepare([c.id], requiredSource: c.requiredSource),
          throwsA(isA<FactCopySourceUnavailableException>()),
        );
        expect(images.gets, isEmpty);
        expect(images.puts, isEmpty);
      });

      test('$name is dropped silently when unavailable facts are skipped, '
          'and the other facts are still copied', () async {
        c.arrange();
        facts.add(_fact(okId, headText: 'Still copied'));
        final r = await prepare(
          [c.id, okId],
          requiredSource: c.requiredSource,
          skipUnavailable: true,
        );
        expect(originsOf(r), [okId]);
        expect(r.prepared.single.factText, 'Still copied');
        expect(r.alreadyThere, isEmpty);
        expect(images.gets, isEmpty);
        expect(images.puts, isEmpty);
      });
    }

    test('every cause gives the same exception, revealing nothing about '
        'which one applied', () async {
      final seen = <String>{};
      for (final c in causes.values) {
        facts.sources.clear();
        facts.accessByBeacon.clear();
        c.arrange();
        try {
          await prepare([c.id], requiredSource: c.requiredSource);
          fail('${c.id} was not refused');
        } on FactCopySourceUnavailableException catch (e) {
          seen.add('${e.code.codeNumber}|${e.description}');
        }
      }
      expect(seen, hasLength(1));
    });

    test('a request-visible fact is copyable with read access alone', () async {
      facts
        ..add(_fact('Fpublic00001', beaconId: _otherRequest))
        ..accessByBeacon[_otherRequest] = _access(canUseRoom: false);
      final r = await prepare(['Fpublic00001']);
      expect(originsOf(r), ['Fpublic00001']);
    });
  });

  group('A fact that already has a live copy in the destination', () {
    test('is reported as already there with the existing copy id, and its '
        'images are neither read nor stored', () async {
      facts
        ..add(_fact('Fthere000001', attachments: [_image(1), _image(2)]))
        ..add(_fact('Fnew00000001'))
        ..liveCopies[_destination] = {'Fthere000001': 'Fexisting001'};
      final r = await prepare(['Fthere000001', 'Fnew00000001']);
      expect(r.alreadyThere, {'Fthere000001': 'Fexisting001'});
      expect(originsOf(r), ['Fnew00000001']);
      expect(images.gets, isEmpty);
      expect(images.puts, isEmpty);
    });

    test(
      'without a destination (fork or bud) nothing is looked up, nothing '
      'is already there, and a fact of the required source is prepared',
      () async {
        facts
          ..add(_fact('Ffork0000001'))
          ..liveCopies[_sourceRequest] = {'Ffork0000001': 'Fsomecopy001'};
        final r = await prepare(
          ['Ffork0000001'],
          destination: null,
          requiredSource: _sourceRequest,
          skipUnavailable: true,
        );
        expect(originsOf(r), ['Ffork0000001']);
        expect(r.alreadyThere, isEmpty);
        expect(facts.liveCopyLookups, 0);
      },
    );
  });

  group('A required source episode with a destination', () {
    test('a readable fact inside the required source is prepared and source '
        'access is checked for that episode', () async {
      facts.add(_fact('Freqdest0001', attachments: [_image(1)]));
      final r = await prepare(
        ['Freqdest0001'],
        requiredSource: _sourceRequest,
        skipUnavailable: true,
      );
      expect(originsOf(r), ['Freqdest0001']);
      expect(r.prepared.single.newImageIds, images.putIds);
      expect(r.alreadyThere, isEmpty);
      expect(facts.accessUserIds, isNotEmpty);
    });
  });

  group('A prepared copy', () {
    test(
      'snapshots the head revision seq and text and records its origin',
      () async {
        facts
          ..add(
            _fact(
              'Frequest0001',
              headRevisionSeq: 7,
              headText: 'Head of seven',
            ),
          )
          ..add(
            _fact(
              'Fpost0000001',
              beaconId: _sourcePost,
              beaconKind: 1,
              headRevisionSeq: 2,
              headText: 'Post fact',
            ),
          )
          ..accessByBeacon[_sourcePost] = _access(kind: 1);
        final r = await prepare(['Frequest0001', 'Fpost0000001']);
        expect(r.prepared, hasLength(2));
        final [request, post] = r.prepared;
        expect(request.originFactCardId, 'Frequest0001');
        expect(request.originRevisionSeq, 7);
        expect(request.factText, 'Head of seven');
        expect(request.originBeaconKind, 0);
        expect(request.newImageIds, isEmpty);
        expect(_attachmentsOf(request), isEmpty);
        expect(post.originFactCardId, 'Fpost0000001');
        expect(post.originRevisionSeq, 2);
        expect(post.factText, 'Post fact');
        expect(post.originBeaconKind, 1);
      },
    );

    test('re-stores each image under the actor and points its attachments at '
        'the new blobs, keeping every other field', () async {
      facts.add(
        _fact(
          'Fimages00001',
          attachments: [_image(1), _image(2, position: 1)],
        ),
      );
      final r = await prepare(['Fimages00001']);
      final copy = r.prepared.single;

      expect(images.gets, [_sourceImageId(1), _sourceImageId(2)]);
      expect(images.puts, hasLength(2));
      for (final (i, p) in images.puts.indexed) {
        expect(p.authorId, _actor);
        expect(p.bytes, _Images.bytesOf(_sourceImageId(i + 1)));
      }
      expect(copy.newImageIds, images.putIds);

      final attachments = _attachmentsOf(copy);
      expect(attachments, hasLength(2));
      for (final (i, a) in attachments.indexed) {
        final source = _imageEntry(i + 1, position: i);
        expect(a['imageId'], images.putIds[i]);
        expect(a['imageId'], isNot(source['imageId']));
        expect(a['imageAuthorId'], _actor);
        expect(a['id'], isA<String>());
        expect(a['id'], isNot(source['id']));
        expect(a['id'], isNotEmpty);
        expect(
          {...a}..removeWhere(
            (k, _) => k == 'id' || k == 'imageId' || k == 'imageAuthorId',
          ),
          {...source}..removeWhere(
            (k, _) => k == 'id' || k == 'imageId' || k == 'imageAuthorId',
          ),
        );
      }
      expect(attachments[0]['id'], isNot(attachments[1]['id']));
    });

    test('drops non-image, dangling and malformed attachments without reading '
        'them, and keeps the rest', () async {
      facts.add(
        _fact(
          'Fmixed000001',
          attachments: [
            FactCopySourceAttachment(
              fields: {
                ..._imageEntry(9),
                'kind': BeaconRoomMessageAttachmentKind.file,
                'mime': 'application/pdf',
              },
              imageExists: false,
            ),
            FactCopySourceAttachment(
              fields: _imageEntry(2, position: 1),
              imageExists: false,
            ),
            FactCopySourceAttachment(
              fields: {..._imageEntry(3, position: 2), 'imageId': 'not-an-id'},
              imageExists: true,
            ),
            _image(4, position: 3),
          ],
        ),
      );
      final r = await prepare(['Fmixed000001']);
      final copy = r.prepared.single;
      expect(images.gets, [_sourceImageId(4)]);
      expect(images.puts, hasLength(1));
      expect(copy.newImageIds, images.putIds);
      final attachments = _attachmentsOf(copy);
      expect(attachments, hasLength(1));
      expect(attachments.single['imageId'], images.putIds.single);
      expect(attachments.single['fileName'], 'picture-4.png');
    });

    test(
      'of a fact whose attachments were all dropped still carries its text',
      () async {
        facts.add(
          _fact(
            'Fdangling001',
            headText: 'Only text survives',
            attachments: [
              FactCopySourceAttachment(
                fields: _imageEntry(1),
                imageExists: false,
              ),
            ],
          ),
        );
        final r = await prepare(['Fdangling001']);
        final copy = r.prepared.single;
        expect(copy.factText, 'Only text survives');
        expect(copy.newImageIds, isEmpty);
        expect(_attachmentsOf(copy), isEmpty);
        expect(images.gets, isEmpty);
        expect(images.puts, isEmpty);
      },
    );
  });

  group('Source ids', () {
    test('are de-duplicated: a repeated id is copied once', () async {
      facts.add(_fact('Ftwice000001', attachments: [_image(1)]));
      final r = await prepare(['Ftwice000001', 'Ftwice000001']);
      expect(originsOf(r), ['Ftwice000001']);
      expect(images.gets, hasLength(1));
      expect(images.puts, hasLength(1));
    });

    test('give prepared copies in input order', () async {
      for (final id in ['Forder000001', 'Forder000002', 'Forder000003']) {
        facts.add(_fact(id));
      }
      final r = await prepare(['Forder000003', 'Forder000001', 'Forder000002']);
      expect(originsOf(r), ['Forder000003', 'Forder000001', 'Forder000002']);
    });

    for (final skip in [false, true]) {
      test('exactly 20 readable text-only ids give 20 prepared copies '
          '(skipUnavailable: $skip)', () async {
        final ids = [
          for (var i = 0; i < 20; i++) 'Flimit${'$i'.padLeft(6, '0')}',
        ];
        for (final id in ids) {
          facts.add(_fact(id));
        }
        final r = await prepare(ids, skipUnavailable: skip);
        expect(originsOf(r), ids);
      });
    }

    for (final skip in [false, true]) {
      test('more than 20 throw BeaconCreateException before any image work '
          '(skipUnavailable: $skip)', () async {
        final ids = [
          for (var i = 0; i < 21; i++) 'Flimit${'$i'.padLeft(6, '0')}',
        ];
        for (final (i, id) in ids.indexed) {
          facts.add(_fact(id, attachments: [_image(i + 1)]));
        }
        await expectLater(
          prepare(ids, skipUnavailable: skip),
          throwsA(isA<BeaconCreateException>()),
        );
        expect(images.gets, isEmpty);
        expect(images.puts, isEmpty);
      });
    }
  });

  group('The 40-image limit per call', () {
    void seedFortyOneImages() {
      var n = 0;
      List<FactCopySourceAttachment> imagesFor(int count) => [
        for (var i = 0; i < count; i++) _image(++n, position: i),
      ];
      facts
        ..add(_fact('Fforty000001', attachments: imagesFor(20)))
        ..add(_fact('Fforty000002', attachments: imagesFor(20)))
        ..add(_fact('Fforty000003', attachments: imagesFor(1)))
        ..add(_fact('Fforty000004', headText: 'Text only'))
        ..add(_fact('Fforty000005', attachments: imagesFor(1)));
    }

    const ids = [
      'Fforty000001',
      'Fforty000002',
      'Fforty000003',
      'Fforty000004',
      'Fforty000005',
    ];

    test('the 41st image throws BeaconCreateException and leaves no new blob '
        'behind', () async {
      seedFortyOneImages();
      await expectLater(prepare(ids), throwsA(isA<BeaconCreateException>()));
      // Images 1–40 were stored before the 41st was reached; the 41st is
      // never read nor stored. The limit error is an exception thrown
      // mid-call, so (plan §5.2 step 9: any other exception compensates
      // every blob created so far) no stored blob may be left orphaned.
      expect(images.puts, hasLength(40));
      expect(images.gets, isNot(contains(_sourceImageId(41))));
      expect(images.compensatedIds, images.putIds.toSet());
    });

    test('when skipping, the fact holding the 41st image and every later fact '
        'with images are dropped; text-only facts continue', () async {
      seedFortyOneImages();
      final r = await prepare(ids, skipUnavailable: true);
      expect(originsOf(r), ['Fforty000001', 'Fforty000002', 'Fforty000004']);
      final kept = {for (final p in r.prepared) ...p.newImageIds};
      expect(kept, hasLength(40));
      expect(images.compensatedIds, images.putIds.toSet().difference(kept));
      expect(images.compensatedIds.intersection(kept), isEmpty);
    });
  });

  group('The daily upload cap', () {
    void seedCapScenario() {
      facts
        ..add(_fact('Fcap00000001', attachments: [_image(1)]))
        ..add(
          _fact(
            'Fcap00000002',
            attachments: [_image(2), _image(3, position: 1)],
          ),
        )
        ..add(_fact('Fcap00000003', headText: 'Text only after cap'))
        ..add(_fact('Fcap00000004', attachments: [_image(4)]))
        ..add(_fact('Fcap00000005', headText: 'Last text only'));
      images.putErrors[3] = const RateLimitedException(
        description: 'Daily upload limit reached, try again tomorrow',
      );
    }

    const ids = [
      'Fcap00000001',
      'Fcap00000002',
      'Fcap00000003',
      'Fcap00000004',
      'Fcap00000005',
    ];

    test('rethrows after compensating every blob created so far', () async {
      seedCapScenario();
      await expectLater(prepare(ids), throwsA(isA<RateLimitedException>()));
      expect(images.putIds, hasLength(2));
      expect(images.compensatedIds, images.putIds.toSet());
      expect({for (final c in images.compensated) c.authorId}, {_actor});
    });

    test('when skipping, drops that fact after compensating its blobs, drops '
        'later facts with images, and keeps text-only facts', () async {
      seedCapScenario();
      final r = await prepare(ids, skipUnavailable: true);
      expect(originsOf(r), ['Fcap00000001', 'Fcap00000003', 'Fcap00000005']);
      final first = r.prepared.first;
      expect(first.newImageIds, [images.putIds[0]]);
      expect(images.compensatedIds, {images.putIds[1]});
      expect(images.gets, isNot(contains(_sourceImageId(4))));
      expect(images.puts, hasLength(2));
    });
  });

  group('Any other failure while copying images', () {
    for (final skip in [false, true]) {
      test('from storing a blob compensates every blob created so far and '
          'rethrows it (skipUnavailable: $skip)', () async {
        final failure = StateError('storage is down');
        facts
          ..add(_fact('Ffail0000001', attachments: [_image(1)]))
          ..add(
            _fact(
              'Ffail0000002',
              attachments: [_image(2), _image(3, position: 1)],
            ),
          );
        images.putErrors[3] = failure;
        await expectLater(
          prepare(['Ffail0000001', 'Ffail0000002'], skipUnavailable: skip),
          throwsA(same(failure)),
        );
        expect(images.putIds, hasLength(2));
        expect(images.compensatedIds, images.putIds.toSet());
      });

      test(
        'from reading an existing source image is not treated as a missing '
        'image: it compensates and rethrows (skipUnavailable: $skip)',
        () async {
          final failure = StateError('object storage read failed');
          facts
            ..add(_fact('Fread0000001', attachments: [_image(1)]))
            ..add(_fact('Fread0000002', attachments: [_image(2)]));
          images.getErrors[_sourceImageId(2)] = failure;
          await expectLater(
            prepare(['Fread0000001', 'Fread0000002'], skipUnavailable: skip),
            throwsA(same(failure)),
          );
          expect(images.putIds, hasLength(1));
          expect(images.compensatedIds, images.putIds.toSet());
        },
      );
    }
  });

  test(
    'a successful call schedules no hash task and compensates nothing',
    () async {
      facts
        ..add(_fact('Fok000000001', attachments: [_image(1), _image(2)]))
        ..add(_fact('Fok000000002'));
      final r = await prepare(['Fok000000001', 'Fok000000002']);
      expect(r.prepared, hasLength(2));
      expect(images.puts, hasLength(2));
      expect(tasks.scheduled, isEmpty);
      expect(images.compensated, isEmpty);
    },
  );
}
