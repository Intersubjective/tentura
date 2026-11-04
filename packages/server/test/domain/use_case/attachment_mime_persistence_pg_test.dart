@Tags(['pg'])
library;

import 'package:logging/logging.dart';
import 'package:mockito/mockito.dart';
import 'package:postgres/postgres.dart';
import 'package:tentura_server/data/database/tentura_db.dart'
    hide isNotNull, isNull;
import 'package:tentura_server/data/repository/beacon_room_repository.dart';
import 'package:tentura_server/data/repository/image_object_gc_repository.dart';
import 'package:tentura_server/data/repository/image_repository.dart';
import 'package:tentura_server/data/repository/mutating_unit_of_work.dart';
import 'package:tentura_server/data/repository/upload_quota_repository.dart';
import 'package:tentura_server/domain/entity/task_entity.dart';
import 'package:tentura_server/domain/policy/discussion_product_policy.dart';
import 'package:tentura_server/domain/port/beacon_fact_card_repository_port.dart';
import 'package:tentura_server/domain/port/coordination_item_repository_port.dart';
import 'package:tentura_server/domain/port/polling_repository_port.dart';
import 'package:tentura_server/domain/port/remote_storage_port.dart';
import 'package:tentura_server/domain/port/task_repository_port.dart';
import 'package:tentura_server/domain/use_case/beacon_room_case.dart';
import 'package:test/test.dart';

import '../../support/disposable_pg_target.dart';
import '../../support/fake_beacon_hierarchy_repository.dart';
import '../../support/fake_user_block_repository.dart';
import '../../support/pg_test_public_keys.dart';

const _author = 'Uattachmime001';
const _beacon = 'Battachmime001';
const _message = 'Rattachmime001';

void main() {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_ATTACHMENT_MIME_TEST_DB',
    defaultNamePrefix: 'tentura_test_attachment_mime',
  );
  late DisposablePgWriterSession session;
  late TenturaDb database;
  late BeaconRoomCase room;
  late _Storage storage;
  setUpAll(() async {
    session = await setUpDisposablePgWriter(target: target);
    database = TenturaDb(target.databaseEnv);
    storage = _Storage();
    final quota = UploadQuotaRepository(database);
    room = BeaconRoomCase(
      BeaconRoomRepository(database),
      _Items(),
      _Cards(),
      ImageRepository(
        database,
        storage,
        quota,
        ImageObjectGcRepository(database, storage),
        target.databaseEnv,
        Logger('AttachmentMimePersistence'),
      ),
      _Tasks(),
      storage,
      _Polling(),
      quota,
      FakeUserBlockRepository(),
      MutatingUnitOfWork(database),
      FakeBeaconHierarchyRepository(),
      const ProductionDiscussionProductPolicy(),
      env: target.databaseEnv,
      logger: Logger('AttachmentMimePersistence'),
    );
    await session.writer.execute(
      Sql.named('''
INSERT INTO public."user" (id, display_name, public_key) VALUES (@id, 'Author', @key)
'''),
      parameters: {'id': _author, 'key': pgTestPublicKey('attachmentmime', 1)},
    );
    await session.writer.execute('''
INSERT INTO public.beacon (id, user_id, title, description, status, published_at)
VALUES ('$_beacon', '$_author', 'Attachments', '', 0, now())
''');
    await session.writer.execute('''
INSERT INTO public.beacon_room_message (id, beacon_id, author_id, body)
VALUES ('$_message', '$_beacon', '$_author', 'Files')
''');
  });
  tearDownAll(() async {
    await database.close();
    await tearDownDisposablePgWriter(session: session);
  });

  for (final ext in ['png', 'webp']) {
    test(
      '$ext attachments retain their extension MIME type when saved to a discussion',
      () async {
        final name = '/uploads/Отчёт.$ext   ';
        final saved = await room.addMessageAttachment(
          beaconId: _beacon,
          userId: _author,
          messageId: _message,
          attachmentBytes: Stream.value(Uint8List.fromList([1, 2, 3])),
          attachmentFilename: name,
        );
        expect(saved, isTrue);
        expect(storage.uploads, greaterThan(0));
        final rows = await session.writer.execute(
          Sql.named('''
SELECT a.file_name, a.mime, a.size_bytes, a.image_id
FROM public.beacon_room_message_attachment a
WHERE a.message_id = @message AND a.file_name = @name
'''),
          parameters: {'message': _message, 'name': 'Отчёт.$ext'},
        );
        expect(rows, hasLength(1));
        expect(rows.single[0], 'Отчёт.$ext');
        expect(rows.single[2], 3);
        expect(rows.single[3], isNotNull);
        expect(rows.single[1], 'image/$ext');
      },
    );
  }
}

class _Storage extends Fake implements RemoteStoragePort {
  int uploads = 0;
  @override
  Future<String> putObject(
    String path,
    Stream<Uint8List> bytes, {
    Map<String, String>? metadata,
  }) async {
    await bytes.drain<void>();
    uploads++;
    return path;
  }
}

class _Items extends Fake implements CoordinationItemRepositoryPort {}

class _Cards extends Fake implements BeaconFactCardRepositoryPort {}

class _Polling extends Fake implements PollingRepositoryPort {}

class _Tasks extends Fake implements TaskRepositoryPort {
  @override
  Future<String> schedule(TaskEntity task) async => 'task';
}
