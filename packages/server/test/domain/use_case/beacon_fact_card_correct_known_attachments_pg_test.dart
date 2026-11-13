@Tags(['pg'])
library;

import 'dart:convert';

import 'package:drift_postgres/drift_postgres.dart';
import 'package:injectable/injectable.dart' show Environment;
import 'package:logging/logging.dart';
import 'package:mockito/mockito.dart';
import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'package:tentura_server/consts/beacon_fact_card_consts.dart';
import 'package:tentura_server/consts/beacon_room_consts.dart';
import 'package:tentura_server/data/database/tentura_db.dart'
    hide isNotNull, isNull;
import 'package:tentura_server/data/repository/beacon_fact_card_repository.dart';
import 'package:tentura_server/data/repository/beacon_room_repository.dart';
import 'package:tentura_server/domain/exception.dart';
import 'package:tentura_server/domain/port/beacon_hierarchy_repository_port.dart';
import 'package:tentura_server/domain/port/image_repository_port.dart';
import 'package:tentura_server/domain/port/task_repository_port.dart';
import 'package:tentura_server/domain/use_case/beacon_fact_card_case.dart';
import 'package:tentura_server/env.dart';

import '../../support/disposable_pg_target.dart';
import '../../support/fake_beacon_access_guard.dart';
import '../../support/pg_test_public_keys.dart';

class _UnusedImage extends Fake implements ImageRepositoryPort {}

class _UnusedTasks extends Fake implements TaskRepositoryPort {}

class _UnusedHierarchy extends Fake implements BeaconHierarchyRepositoryPort {}

/// An edit stores a known attachment (one whose id is on any revision of the
/// same fact in the same beacon) as the server last saved it, taking only
/// `position` from the client. An unknown entry is accepted only as an image
/// whose row belongs to the actor, and the list cannot exceed
/// [kMaxRoomMessageAttachments].
Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_FACT_CORRECT_ATTACHMENTS_PG_TEST_DB',
    defaultNamePrefix: 'tentura_test_fact_correct_attachments',
  );
  final reachable = await canReachPostgresAdmin(target);
  final skipReason = reachable
      ? false as Object
      : 'Postgres admin database not reachable for disposable test target';

  group('BeaconFactCardCase.correct attachment ownership', () {
    late DisposablePgWriterSession session;
    late Connection writer;
    late TenturaDb db;
    late BeaconFactCardCase case_;

    if (reachable) {
      setUpAll(() async {
        session = await setUpDisposablePgWriter(target: target);
        writer = session.writer;
        await _seed(writer);

        db = TenturaDb.forTest(
          database: PgDatabase.opened(
            Pool<dynamic>.withEndpoints(
              [target.databaseEnv.pgEndpoint],
              settings: target.databaseEnv.pgPoolSettings,
            ),
            enableMigrations: false,
          ),
        );
        final room = BeaconRoomRepository(db);
        case_ = BeaconFactCardCase(
          BeaconFactCardRepository(db, room),
          room,
          _UnusedImage(),
          _UnusedTasks(),
          _UnusedHierarchy(),
          FakeBeaconAccessGuard(),
          // Every test edits as the same actor; keep the per-actor edit
          // rate limit out of the way.
          env: Env(environment: Environment.test, factEditRateMax: 1000),
          logger: Logger('BeaconFactCardCorrectKnownAttachmentsPgTest'),
        );
      });

      tearDownAll(() async {
        await tearDownDisposablePgWriter(session: session, drift: db);
      });
    }

    test(
      'an edit that keeps an existing attachment stores that attachment '
      'unchanged',
      () async {
        final server = _image(
          id: 'Akeep000001',
          position: 0,
          fileName: 'kept.jpg',
          imageId: _imageA,
          imageAuthorId: _authorId,
          blurHash: 'LKO2',
        );
        await _seedFact(
          writer,
          id: _factKeep,
          headText: 'Caption',
          revisions: [
            [server],
          ],
        );

        final seq = await case_.correct(
          factCardId: _factKeep,
          beaconId: _beaconId,
          actorUserId: _editorId,
          newText: 'Caption edited',
          baseRevisionSeq: 1,
          attachmentsJson: jsonEncode([
            _copy(
              server,
              fileName: 'renamed-by-client.jpg',
              imageAuthorId: _editorId,
              blurHash: 'FORGED',
              width: 99,
              height: 99,
            ),
          ]),
        );

        expect(seq, 2);
        final stored = await _attachmentsAt(
          writer,
          factId: _factKeep,
          seq: seq,
        );
        expect(stored, hasLength(1));
        _expectServerObject(stored.single, server, position: 0);
      },
      skip: skipReason,
    );

    test(
      'a reordered edit stores each server attachment at the new position',
      () async {
        final first = _image(
          id: 'Aorder00001',
          position: 0,
          fileName: 'alpha.jpg',
          imageId: _imageA,
          imageAuthorId: _authorId,
        );
        final second = _image(
          id: 'Aorder00002',
          position: 1,
          fileName: 'beta.jpg',
          imageId: _imageB,
          imageAuthorId: _authorId,
        );
        await _seedFact(
          writer,
          id: _factOrder,
          headText: 'Two photos',
          revisions: [
            [first, second],
          ],
        );

        final seq = await case_.correct(
          factCardId: _factOrder,
          beaconId: _beaconId,
          actorUserId: _editorId,
          newText: 'Two photos, swapped',
          baseRevisionSeq: 1,
          attachmentsJson: jsonEncode([
            _copy(second, position: 0, fileName: 'client-beta.jpg'),
            _copy(first, position: 1, fileName: 'client-alpha.jpg'),
          ]),
        );

        expect(seq, 2);
        final stored = await _attachmentsAt(
          writer,
          factId: _factOrder,
          seq: seq,
        );
        expect(stored, hasLength(2));
        final byId = {for (final item in stored) item['id']! as String: item};
        _expectServerObject(byId['Aorder00002']!, second, position: 0);
        _expectServerObject(byId['Aorder00001']!, first, position: 1);
      },
      skip: skipReason,
    );

    test(
      'a known attachment keeps the server imageId when the edit swaps it',
      () async {
        final server = _image(
          id: 'Aswap000001',
          position: 0,
          fileName: 'real.jpg',
          imageId: _imageA,
          imageAuthorId: _authorId,
        );
        await _seedFact(
          writer,
          id: _factSwap,
          headText: 'One photo',
          revisions: [
            [server],
          ],
        );

        final seq = await case_.correct(
          factCardId: _factSwap,
          beaconId: _beaconId,
          actorUserId: _editorId,
          newText: 'One photo, claimed swap',
          baseRevisionSeq: 1,
          attachmentsJson: jsonEncode([
            _copy(server, imageId: _forgedImageId),
          ]),
        );

        expect(seq, 2);
        final stored = await _attachmentsAt(
          writer,
          factId: _factSwap,
          seq: seq,
        );
        expect(stored, hasLength(1));
        expect(stored.single['imageId'], _imageA);
        _expectServerObject(stored.single, server, position: 0);
      },
      skip: skipReason,
    );

    test(
      'an edit that adds an image owned by someone else is refused',
      () async {
        await _seedFact(
          writer,
          id: _factForeign,
          headText: 'No photo yet',
          revisions: [const []],
        );

        await expectLater(
          case_.correct(
            factCardId: _factForeign,
            beaconId: _beaconId,
            actorUserId: _editorId,
            newText: 'No photo yet',
            baseRevisionSeq: 1,
            attachmentsJson: jsonEncode([
              _image(
                id: 'Aforeign001',
                position: 0,
                fileName: 'theirs.jpg',
                imageId: _foreignImage,
                imageAuthorId: _editorId,
              ),
            ]),
          ),
          throwsA(isA<BeaconCreateException>()),
        );
        expect(await _revisionCount(writer, _factForeign), 1);
      },
      skip: skipReason,
    );

    test(
      'a known file attachment keeps its empty imageId when the edit sends '
      'one',
      () async {
        final server = _file(
          id: 'Afile000001',
          position: 0,
          fileName: 'notes.pdf',
        );
        await _seedFact(
          writer,
          id: _factFile,
          headText: 'Notes',
          revisions: [
            [server],
          ],
        );

        final seq = await case_.correct(
          factCardId: _factFile,
          beaconId: _beaconId,
          actorUserId: _editorId,
          newText: 'Notes edited',
          baseRevisionSeq: 1,
          attachmentsJson: jsonEncode([
            _copy(server, imageId: _forgedImageId, fileName: 'stolen.jpg'),
          ]),
        );

        expect(seq, 2);
        final stored = await _attachmentsAt(
          writer,
          factId: _factFile,
          seq: seq,
        );
        expect(stored, hasLength(1));
        expect(stored.single['imageId'], '');
        _expectServerObject(stored.single, server, position: 0);
      },
      skip: skipReason,
    );

    test(
      'an attachment that exists only on an older revision is stored with '
      "that revision's image",
      () async {
        final older = _image(
          id: 'Aolder00001',
          position: 0,
          fileName: 'first.jpg',
          imageId: _imageA,
          imageAuthorId: _authorId,
        );
        final head = _image(
          id: 'Ahead000001',
          position: 0,
          fileName: 'second.jpg',
          imageId: _imageB,
          imageAuthorId: _editorId,
        );
        await _seedFact(
          writer,
          id: _factOlder,
          headText: 'Second version',
          revisions: [
            [older],
            [head],
          ],
        );

        final seq = await case_.correct(
          factCardId: _factOlder,
          beaconId: _beaconId,
          actorUserId: _editorId,
          newText: 'Back to the first photo',
          baseRevisionSeq: 2,
          attachmentsJson: jsonEncode([
            _copy(older, imageId: _forgedImageId, fileName: 'client-first.jpg'),
          ]),
        );

        expect(seq, 3);
        final stored = await _attachmentsAt(
          writer,
          factId: _factOlder,
          seq: seq,
        );
        expect(stored, hasLength(1));
        expect(stored.single['id'], 'Aolder00001');
        expect(stored.single['imageId'], _imageA);
        _expectServerObject(stored.single, older, position: 0);
      },
      skip: skipReason,
    );

    test(
      'an edit that adds an image the actor uploaded stores it next to the '
      'kept attachment',
      () async {
        final kept = _image(
          id: 'Aownkeep001',
          position: 0,
          fileName: 'kept.jpg',
          imageId: _imageA,
          imageAuthorId: _authorId,
        );
        await _seedFact(
          writer,
          id: _factOwn,
          headText: 'One photo',
          revisions: [
            [kept],
          ],
        );
        final added = _image(
          id: 'Aownnew0001',
          position: 1,
          fileName: 'mine.jpg',
          imageId: _ownedImage,
          imageAuthorId: _editorId,
        );

        final seq = await case_.correct(
          factCardId: _factOwn,
          beaconId: _beaconId,
          actorUserId: _editorId,
          newText: 'Two photos',
          baseRevisionSeq: 1,
          attachmentsJson: jsonEncode([kept, added]),
        );

        expect(seq, 2);
        final stored = await _attachmentsAt(writer, factId: _factOwn, seq: seq);
        expect(stored, hasLength(2));
        final byId = {for (final item in stored) item['id']! as String: item};
        _expectServerObject(byId['Aownkeep001']!, kept, position: 0);
        final storedNew = byId['Aownnew0001']!;
        expect(storedNew['kind'], BeaconRoomMessageAttachmentKind.image);
        expect(storedNew['imageId'], _ownedImage);
        expect(storedNew['position'], 1);
      },
      skip: skipReason,
    );

    test(
      'an edit that adds a file attachment with an unknown id is refused',
      () async {
        await _seedFact(
          writer,
          id: _factNewFile,
          headText: 'No file yet',
          revisions: [const []],
        );

        await expectLater(
          case_.correct(
            factCardId: _factNewFile,
            beaconId: _beaconId,
            actorUserId: _editorId,
            newText: 'No file yet',
            baseRevisionSeq: 1,
            attachmentsJson: jsonEncode([
              _file(id: 'Anewfile001', position: 0, fileName: 'made-up.pdf'),
            ]),
          ),
          throwsA(isA<BeaconCreateException>()),
        );
        expect(await _revisionCount(writer, _factNewFile), 1);
      },
      skip: skipReason,
    );

    test(
      'an attachment id from another fact in the same beacon counts as new '
      "and is refused when its image is not the actor's",
      () async {
        final elsewhere = _image(
          id: 'Asibling001',
          position: 0,
          fileName: 'sibling.jpg',
          imageId: _foreignImage,
          imageAuthorId: _otherId,
        );
        await _seedFact(
          writer,
          id: _factSibling,
          headText: 'Sibling fact',
          revisions: [
            [elsewhere],
          ],
        );
        await _seedFact(
          writer,
          id: _factScopeSame,
          headText: 'Target fact',
          revisions: [const []],
        );

        await expectLater(
          case_.correct(
            factCardId: _factScopeSame,
            beaconId: _beaconId,
            actorUserId: _editorId,
            newText: 'Target fact',
            baseRevisionSeq: 1,
            attachmentsJson: jsonEncode([elsewhere]),
          ),
          throwsA(isA<BeaconCreateException>()),
        );
        expect(await _revisionCount(writer, _factScopeSame), 1);
      },
      skip: skipReason,
    );

    test(
      'an attachment id from a fact in another beacon counts as new and is '
      "refused when its image is not the actor's",
      () async {
        final elsewhere = _image(
          id: 'Aotherbcn01',
          position: 0,
          fileName: 'other-beacon.jpg',
          imageId: _foreignImage,
          imageAuthorId: _otherId,
        );
        await _seedFact(
          writer,
          id: _factOtherBeacon,
          beaconId: _otherBeaconId,
          headText: 'Fact in another beacon',
          revisions: [
            [elsewhere],
          ],
        );
        await _seedFact(
          writer,
          id: _factScopeOther,
          headText: 'Target fact',
          revisions: [const []],
        );

        await expectLater(
          case_.correct(
            factCardId: _factScopeOther,
            beaconId: _beaconId,
            actorUserId: _editorId,
            newText: 'Target fact',
            baseRevisionSeq: 1,
            attachmentsJson: jsonEncode([elsewhere]),
          ),
          throwsA(isA<BeaconCreateException>()),
        );
        expect(await _revisionCount(writer, _factScopeOther), 1);
      },
      skip: skipReason,
    );

    test(
      'an edit with exactly as many attachments as a room message allows '
      'stores them all',
      () async {
        final server = [
          for (var i = 0; i < kMaxRoomMessageAttachments; i++)
            _image(
              id: 'Amax${i.toString().padLeft(2, '0')}',
              position: i,
              fileName: 'frame-$i.jpg',
              imageId: _imageA,
              imageAuthorId: _authorId,
            ),
        ];
        await _seedFact(
          writer,
          id: _factAtMax,
          headText: 'Full set',
          revisions: [server],
        );

        final seq = await case_.correct(
          factCardId: _factAtMax,
          beaconId: _beaconId,
          actorUserId: _editorId,
          newText: 'Full set edited',
          baseRevisionSeq: 1,
          attachmentsJson: jsonEncode([
            for (final item in server)
              _copy(item, fileName: 'client-${item['fileName']}'),
          ]),
        );

        expect(seq, 2);
        final stored = await _attachmentsAt(
          writer,
          factId: _factAtMax,
          seq: seq,
        );
        expect(stored, hasLength(kMaxRoomMessageAttachments));
        final byId = {for (final item in stored) item['id']! as String: item};
        for (final item in server) {
          _expectServerObject(
            byId[item['id']]!,
            item,
            position: item['position']! as int,
          );
        }
      },
      skip: skipReason,
    );

    test(
      'an edit with more attachments than a room message allows is refused',
      () async {
        final server = [
          for (var i = 0; i < kMaxRoomMessageAttachments + 1; i++)
            _image(
              id: 'Aover${i.toString().padLeft(2, '0')}',
              position: i,
              fileName: 'frame-$i.jpg',
              imageId: _ownedImage,
              imageAuthorId: _editorId,
            ),
        ];
        await _seedFact(
          writer,
          id: _factTooMany,
          headText: 'Many frames',
          revisions: [server],
        );

        await expectLater(
          case_.correct(
            factCardId: _factTooMany,
            beaconId: _beaconId,
            actorUserId: _editorId,
            newText: 'Many frames edited',
            baseRevisionSeq: 1,
            attachmentsJson: jsonEncode([
              for (final item in server)
                _copy(item, fileName: 'forged-${item['fileName']}'),
            ]),
          ),
          throwsA(isA<BeaconCreateException>()),
        );
        expect(await _revisionCount(writer, _factTooMany), 1);
      },
      skip: skipReason,
    );

    test(
      'an edit of a fact without attachments that adds only an image the '
      'actor uploaded stores that image',
      () async {
        await _seedFact(
          writer,
          id: _factOwnOnly,
          headText: 'Text only',
          revisions: [const []],
        );
        final added = _image(
          id: 'Aownonly001',
          position: 0,
          fileName: 'mine.jpg',
          imageId: _ownedImage,
          imageAuthorId: _editorId,
        );

        final seq = await case_.correct(
          factCardId: _factOwnOnly,
          beaconId: _beaconId,
          actorUserId: _editorId,
          newText: 'Text and my photo',
          baseRevisionSeq: 1,
          attachmentsJson: jsonEncode([added]),
        );

        expect(seq, 2);
        final stored = await _attachmentsAt(
          writer,
          factId: _factOwnOnly,
          seq: seq,
        );
        expect(stored, hasLength(1));
        expect(stored.single['id'], 'Aownonly001');
        expect(stored.single['kind'], BeaconRoomMessageAttachmentKind.image);
        expect(stored.single['imageId'], _ownedImage);
        expect(stored.single['position'], 0);
      },
      skip: skipReason,
    );

    test(
      'a file attachment copied from the pinned source message keeps the '
      "message's file details and empty imageId through an edit",
      () async {
        await writer.execute(
          Sql.named('''
INSERT INTO public.beacon_room_message (id, beacon_id, author_id, body)
VALUES (@id, @beacon, @author, 'See the brief')
'''),
          parameters: {
            'id': _sourceMessageId,
            'beacon': _beaconId,
            'author': _editorId,
          },
        );
        await writer.execute(
          Sql.named('''
INSERT INTO public.beacon_room_message_attachment
  (id, message_id, kind, mime, size_bytes, position, file_name)
VALUES (@id, @message, @kind, 'application/pdf', 20, 0, 'brief.pdf')
'''),
          parameters: {
            'id': _sourceFileId,
            'message': _sourceMessageId,
            'kind': BeaconRoomMessageAttachmentKind.file,
          },
        );
        final pinned = await case_.pin(
          beaconId: _beaconId,
          factText: 'The brief',
          visibility: BeaconFactCardVisibilityBits.public,
          userId: _editorId,
          sourceMessageId: _sourceMessageId,
        );
        final factId = pinned['id']! as String;
        final copied = await _attachmentsAt(writer, factId: factId, seq: 1);
        expect(copied, hasLength(1), reason: 'pin copies the message file');
        final server = copied.single;
        expect(server['id'], _sourceFileId);
        expect(server['imageId'], '');

        final seq = await case_.correct(
          factCardId: factId,
          beaconId: _beaconId,
          actorUserId: _editorId,
          newText: 'The brief, edited',
          baseRevisionSeq: 1,
          attachmentsJson: jsonEncode([
            _copy(server, imageId: _forgedImageId, fileName: 'stolen.jpg'),
          ]),
        );

        expect(seq, 2);
        final stored = await _attachmentsAt(writer, factId: factId, seq: seq);
        expect(stored, hasLength(1));
        expect(stored.single['imageId'], '');
        _expectServerObject(stored.single, server, position: 0);
      },
      skip: skipReason,
    );

    test(
      'an edit that sends an empty attachment list removes every attachment',
      () async {
        final server = _image(
          id: 'Aclear00001',
          position: 0,
          fileName: 'gone.jpg',
          imageId: _imageA,
          imageAuthorId: _authorId,
        );
        await _seedFact(
          writer,
          id: _factClear,
          headText: 'With photo',
          revisions: [
            [server],
          ],
        );

        final seq = await case_.correct(
          factCardId: _factClear,
          beaconId: _beaconId,
          actorUserId: _editorId,
          newText: 'Photo removed',
          baseRevisionSeq: 1,
          attachmentsJson: '[]',
        );

        expect(seq, 2);
        expect(
          await _attachmentsAt(writer, factId: _factClear, seq: seq),
          isEmpty,
        );
      },
      skip: skipReason,
    );

    test(
      'an edit without an attachment list keeps the previous attachments',
      () async {
        final server = _image(
          id: 'Akeepnull01',
          position: 0,
          fileName: 'stays.jpg',
          imageId: _imageA,
          imageAuthorId: _authorId,
        );
        await _seedFact(
          writer,
          id: _factNullList,
          headText: 'With photo',
          revisions: [
            [server],
          ],
        );

        final seq = await case_.correct(
          factCardId: _factNullList,
          beaconId: _beaconId,
          actorUserId: _editorId,
          newText: 'Text changed only',
          baseRevisionSeq: 1,
        );

        expect(seq, 2);
        final stored = await _attachmentsAt(
          writer,
          factId: _factNullList,
          seq: seq,
        );
        expect(stored, hasLength(1));
        _expectServerObject(stored.single, server, position: 0);
      },
      skip: skipReason,
    );

    group('an edit is refused and stores nothing when', () {
      final ownImage = _image(
        id: 'Arefused001',
        position: 0,
        fileName: 'mine.jpg',
        imageId: _ownedImage,
        imageAuthorId: _editorId,
      );
      final cases = <String, ({String factId, String attachmentsJson})>{
        'the attachment list is not valid JSON': (
          factId: 'Fattbadjson1',
          attachmentsJson: '[{"id": ',
        ),
        'the attachment list is a JSON object instead of a list': (
          factId: 'Fattnotlist1',
          attachmentsJson: jsonEncode(ownImage),
        ),
        'an entry has no id': (
          factId: 'Fattnoid0001',
          attachmentsJson: jsonEncode([
            {...ownImage}..remove('id'),
          ]),
        ),
        'an unknown entry has a kind other than image or file': (
          factId: 'Fattbadkind1',
          attachmentsJson: jsonEncode([
            {...ownImage, 'kind': 7, 'mime': 'video/mp4'},
          ]),
        ),
        'an unknown image entry names an image that has no row': (
          factId: 'Fattnoimgrw1',
          attachmentsJson: jsonEncode([
            {...ownImage, 'imageId': _missingImage},
          ]),
        ),
      };

      for (final MapEntry(key: reason, value: c) in cases.entries) {
        test(reason, () async {
          await _seedFact(
            writer,
            id: c.factId,
            headText: 'Unchanged',
            revisions: [const []],
          );

          await expectLater(
            case_.correct(
              factCardId: c.factId,
              beaconId: _beaconId,
              actorUserId: _editorId,
              newText: 'Should not be stored',
              baseRevisionSeq: 1,
              attachmentsJson: c.attachmentsJson,
            ),
            throwsA(isA<BeaconCreateException>()),
          );
          expect(await _revisionCount(writer, c.factId), 1);
        }, skip: skipReason);
      }
    });
  });
}

const _authorId = 'Uattathor01';
const _editorId = 'Uatteditor1';
const _otherId = 'Uattother001';
const _beaconId = 'Battbeacon01';
const _otherBeaconId = 'Battbeacon02';

const _factKeep = 'Fattkeep0001';
const _factOrder = 'Fattorder001';
const _factSwap = 'Fattswap0001';
const _factForeign = 'Fattforeign1';
const _factFile = 'Fattfile0001';
const _factOlder = 'Fattoldrev01';
const _factTooMany = 'Fatttoomany1';
const _factOwn = 'Fattown00001';
const _factNewFile = 'Fattnewfile1';
const _factSibling = 'Fattsibling1';
const _factScopeSame = 'Fattscopesm1';
const _factOtherBeacon = 'Fattothbcn01';
const _factScopeOther = 'Fattscopeot1';
const _factAtMax = 'Fattatmax001';
const _factOwnOnly = 'Fattownonly1';
const _factClear = 'Fattclear001';
const _factNullList = 'Fattnulllst1';

const _sourceMessageId = 'Rattsource01';
const _sourceFileId = 'Attsrcfile01';

const _imageA = '11111111-1111-4111-8111-111111111111';
const _imageB = '22222222-2222-4222-8222-222222222222';
const _foreignImage = '33333333-3333-4333-8333-333333333333';
const _ownedImage = '44444444-4444-4444-8444-444444444444';
const _forgedImageId = '99999999-9999-4999-8999-999999999999';
const _missingImage = '55555555-5555-4555-8555-555555555555';

final _t0 = DateTime.utc(2026, 3, 1, 12);

Map<String, Object?> _image({
  required String id,
  required int position,
  required String fileName,
  required String imageId,
  required String imageAuthorId,
  String blurHash = '',
  int width = 1,
  int height = 1,
}) => {
  'id': id,
  'kind': BeaconRoomMessageAttachmentKind.image,
  'position': position,
  'mime': 'image/jpeg',
  'sizeBytes': 10,
  'fileName': fileName,
  'imageId': imageId,
  'imageAuthorId': imageAuthorId,
  'blurHash': blurHash,
  'width': width,
  'height': height,
};

Map<String, Object?> _file({
  required String id,
  required int position,
  required String fileName,
}) => {
  'id': id,
  'kind': BeaconRoomMessageAttachmentKind.file,
  'position': position,
  'mime': 'application/pdf',
  'sizeBytes': 20,
  'fileName': fileName,
  'imageId': '',
  'imageAuthorId': '',
  'blurHash': '',
  'width': 0,
  'height': 0,
};

Map<String, Object?> _copy(
  Map<String, Object?> source, {
  int? position,
  String? fileName,
  String? imageId,
  String? imageAuthorId,
  String? blurHash,
  int? width,
  int? height,
}) => {
  ...source,
  'position': ?position,
  'fileName': ?fileName,
  'imageId': ?imageId,
  'imageAuthorId': ?imageAuthorId,
  'blurHash': ?blurHash,
  'width': ?width,
  'height': ?height,
};

void _expectServerObject(
  Map<String, Object?> actual,
  Map<String, Object?> server, {
  required int position,
}) {
  expect(actual['id'], server['id']);
  expect(actual['kind'], server['kind']);
  expect(actual['position'], position);
  expect(actual['mime'], server['mime']);
  expect(actual['sizeBytes'], server['sizeBytes']);
  expect(actual['fileName'], server['fileName']);
  expect(actual['imageId'], server['imageId']);
  expect(actual['imageAuthorId'], server['imageAuthorId']);
  expect(actual['blurHash'], server['blurHash']);
  expect(actual['width'], server['width']);
  expect(actual['height'], server['height']);
}

Future<void> _seed(Connection writer) async {
  var n = 0;
  for (final id in [_authorId, _editorId, _otherId]) {
    n++;
    await writer.execute(
      Sql.named('''
INSERT INTO public."user" (id, display_name, public_key)
VALUES (@id, @id, @key)
'''),
      parameters: {'id': id, 'key': pgTestPublicKey('factatt', n)},
    );
  }
  await writer.execute(
    Sql.named('''
INSERT INTO public.beacon
  (id, user_id, title, description, status, published_at, is_discoverable)
VALUES (@beacon, @author, 't', 'd', 0, @t0, false),
       (@other, @author, 't2', 'd2', 0, @t0, false)
'''),
    parameters: {
      'beacon': _beaconId,
      'other': _otherBeaconId,
      'author': _authorId,
      't0': _t0,
    },
  );
  await writer.execute(
    Sql.named('''
INSERT INTO public.beacon_steward (beacon_id, user_id)
VALUES (@beacon, @editor)
'''),
    parameters: {'beacon': _beaconId, 'editor': _editorId},
  );
  await writer.execute(
    Sql.named('''
INSERT INTO public.image (id, author_id) VALUES
  (@foreign, @other),
  (@owned, @editor)
'''),
    parameters: {
      'foreign': _foreignImage,
      'other': _otherId,
      'owned': _ownedImage,
      'editor': _editorId,
    },
  );
}

Future<void> _seedFact(
  Connection writer, {
  required String id,
  required String headText,
  required List<List<Map<String, Object?>>> revisions,
  String beaconId = _beaconId,
}) async {
  final headSeq = revisions.length;
  await writer.execute(
    Sql.named('''
INSERT INTO public.beacon_fact_card
  (id, beacon_id, fact_text, visibility, pinned_by, status, created_at,
   updated_at, revision_seq)
VALUES (@id, @beacon, @text, ${BeaconFactCardVisibilityBits.public},
        @author, ${BeaconFactCardStatusBits.active}, @at, @at, @head)
'''),
    parameters: {
      'id': id,
      'beacon': beaconId,
      'text': headText,
      'author': _authorId,
      'at': _t0,
      'head': headSeq,
    },
  );
  for (var i = 0; i < revisions.length; i++) {
    final seq = i + 1;
    await writer.execute(
      Sql.named('''
INSERT INTO public.beacon_fact_card_revision
  (fact_card_id, seq, fact_text, actor_id, kind, created_at, attachments_json)
VALUES (@id, @seq, @text, @author, @kind, @at, @att::jsonb)
'''),
      parameters: {
        'id': id,
        'seq': seq,
        'text': seq == headSeq ? headText : 'Earlier $seq',
        'author': _authorId,
        'kind': seq == 1
            ? BeaconFactCardRevisionKindBits.created
            : BeaconFactCardRevisionKindBits.edited,
        'at': _t0,
        'att': jsonEncode(revisions[i]),
      },
    );
  }
}

Future<List<Map<String, Object?>>> _attachmentsAt(
  Connection writer, {
  required String factId,
  required int seq,
}) async {
  final snap = await writer.execute(
    Sql.named('''
SELECT attachments_json::text
FROM public.beacon_fact_card_revision
WHERE fact_card_id = @id AND seq = @seq
'''),
    parameters: {'id': factId, 'seq': seq},
  );
  final decoded = jsonDecode(snap.single.single! as String) as List<Object?>;
  return [
    for (final item in decoded) Map<String, Object?>.from(item! as Map),
  ];
}

Future<int> _revisionCount(Connection writer, String factId) async {
  final rows = await writer.execute(
    Sql.named('''
SELECT count(*)::integer FROM public.beacon_fact_card_revision
WHERE fact_card_id = @id
'''),
    parameters: {'id': factId},
  );
  return rows.single.single! as int;
}
