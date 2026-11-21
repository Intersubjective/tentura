@Tags(['pg', 'multi-connection'])
library;

import 'dart:convert';

import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'package:tentura_root/domain/entity/beacon_status.dart';

import '../../support/disposable_pg_target.dart';
import '../../support/pg_notification_recorder.dart';
import '../../support/pg_test_public_keys.dart';
import '../../support/post_publish_pg_support.dart';

const _postAuthor = 'Ubuddelpostau';
const _budAuthor = 'Ubuddelbudaut';
const _invitee = 'Ubuddelinvite';
const _uninvited = 'Ubuddeluninv0';
const _cancelled = 'Ubuddelcancel';
const _requestAuthor = 'Ubuddelreqaut';
const _requestMember = 'Ubuddelreqmem';

const _post = 'Bbuddelpost01';
const _bud = 'Bbuddelchild1';
const _request = 'Bbuddelreq001';
const _requestChild = 'Bbuddelreqch1';

Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_POST_BUD_DELETE_REALTIME_PG_TEST_DB',
    defaultNamePrefix: 'tentura_test_bud_delete_rt',
  );
  final skip = await pgSkipReason(target);
  if (skip != null) {
    test('Postgres unavailable', () {}, skip: skip);
    return;
  }

  late Connection writer;
  late PgNotificationRecorder recorder;
  late PostPublishHarness harness;

  setUpAll(() async {
    final session = await setUpDisposablePgWriter(target: target);
    final database = openDisposablePgDatabase(target);
    addTearDown(
      () => tearDownDisposablePgWriter(session: session, drift: database),
    );
    writer = session.writer;
    harness = PostPublishHarness.build(database, target.databaseEnv);

    final listener = await Connection.open(
      target.databaseEnv.pgEndpoint,
      settings: target.databaseEnv.pgEndpointSettings,
    );
    addTearDown(listener.close);
    await listener.execute('LISTEN entity_changes');
    recorder = PgNotificationRecorder(listener.channels['entity_changes']);
    addTearDown(recorder.cancel);
  });

  setUp(() async {
    await writer.execute('TRUNCATE public.beacon, public."user" CASCADE');
    await _seed(writer);

    final postMembers = await writer.execute('''
SELECT user_id FROM public.beacon_participant
WHERE beacon_id = '$_post' AND room_access = 3
''');
    expect(
      postMembers.map((row) => row.single),
      containsAll([_budAuthor, _invitee, _uninvited, _cancelled]),
    );
    final budReaders = await writer.execute('''
SELECT id FROM public."user"
WHERE public.beacon_can_read_content('$_bud', id)
''');
    expect(
      budReaders.map((row) => row.single).toSet(),
      {_budAuthor, _invitee},
      reason: 'Only the bud author and the active invitee can read the bud.',
    );
  });

  Future<void> barrier(String token) => writer.execute(
    Sql.named("SELECT pg_notify('entity_changes', @payload)"),
    parameters: {
      'payload': jsonEncode({'entity': 'barrier', 'id': token}),
    },
  );

  Future<List<Map<String, dynamic>>> record(
    Future<void> Function() write,
  ) async {
    await recorder.drain(sendBarrier: barrier);
    await write();
    // The use case returns after committing its write on the repository pool.
    await recorder.flush(sendBarrier: barrier);
    return List.of(recorder.messages);
  }

  Future<void> softDelete(String id, String author) async {
    expect(
      await harness.beacons.deleteById(beaconId: id, userId: author),
      isTrue,
    );
    final row = await writer.execute(
      Sql.named('SELECT status FROM public.beacon WHERE id = @id'),
      parameters: {'id': id},
    );
    expect(row.single.single, BeaconStatus.deleted.smallintValue);
  }

  Future<void> hardDelete(String id) async {
    final deleted = await writer.execute(
      Sql.named('DELETE FROM public.beacon WHERE id = @id'),
      parameters: {'id': id},
    );
    expect(deleted.affectedRows, 1);
    final remaining = await writer.execute(
      Sql.named('SELECT id FROM public.beacon WHERE id = @id'),
      parameters: {'id': id},
    );
    expect(remaining, isEmpty);
  }

  test('soft-deleting a Post bud refreshes its former readers', () async {
    final edited = await record(
      () => writer.execute('''
UPDATE public.beacon SET title = 'Updated bud' WHERE id = '$_bud'
'''),
    );
    expect(_audience(edited, 'beacon_hierarchy', _post), {
      _budAuthor,
      _invitee,
    });

    final requestHints = await record(
      () => softDelete(_requestChild, _requestAuthor),
    );
    expect(_audience(requestHints, 'beacon_hierarchy', _request), {
      _requestAuthor,
      _requestMember,
    });

    final hints = await record(() => softDelete(_bud, _budAuthor));
    _expectNoHintsToNonReaders(hints);
    expect(
      _audience(hints, 'beacon', _bud),
      contains(_invitee),
      reason: 'The soft delete must invalidate the bud. Hints: $hints',
    );
    expect(
      _audience(hints, 'beacon_hierarchy', _post),
      {_budAuthor, _invitee},
      reason:
          'The soft delete must invalidate the Post hierarchy. Hints: $hints',
    );
  });

  test('hard-deleting a Post bud refreshes its former readers', () async {
    final requestHints = await record(() => hardDelete(_requestChild));
    expect(
      _audience(requestHints, 'beacon_hierarchy', _request, event: 'delete'),
      {_requestAuthor, _requestMember},
    );

    final hints = await record(() => hardDelete(_bud));
    _expectNoHintsToNonReaders(hints);
    expect(
      _audience(hints, 'beacon_hierarchy', _post, event: 'delete'),
      {_budAuthor, _invitee},
      reason:
          'The hard delete must invalidate the Post hierarchy. Hints: $hints',
    );
  });

  test(
    'Post bud Chat preview refreshes for former readers after hard delete',
    () async {
      final hints = await record(() => hardDelete(_bud));
      _expectNoHintsToNonReaders(hints);
      expect(
        _audience(hints, 'beacon_hierarchy', _post, event: 'delete'),
        {_budAuthor, _invitee},
        reason: 'The Post hierarchy must still refresh. Hints: $hints',
      );
      expect(
        _audience(hints, 'beacon_hierarchy', _bud, event: 'delete'),
        {_budAuthor, _invitee},
        reason:
            'The deleted bud must invalidate its Chat preview. Hints: $hints',
      );
    },
  );

  test(
    'Post bud Chat preview refreshes for former readers after soft delete',
    () async {
      final hints = await record(() => softDelete(_bud, _budAuthor));
      expect(
        _audience(hints, 'beacon_hierarchy', _post, event: 'update'),
        {_budAuthor, _invitee},
        reason: 'The Post hierarchy must still refresh. Hints: $hints',
      );
      expect(
        _audience(hints, 'beacon_hierarchy', _bud, event: 'update'),
        {_budAuthor, _invitee},
        reason:
            'The soft-deleted bud must invalidate its Chat preview. '
            'Hints: $hints',
      );
    },
  );
}

void _expectNoHintsToNonReaders(List<Map<String, dynamic>> hints) {
  final related = hints.where(
    (hint) =>
        hint['id'] == _bud ||
        (hint['id'] == _post && hint['entity'] == 'beacon_hierarchy'),
  );
  expect(
    _recipients(related).difference({_budAuthor, _invitee}),
    isEmpty,
    reason: 'Only former bud readers should get these hints. Hints: $related',
  );
}

Set<String> _audience(
  List<Map<String, dynamic>> hints,
  String entity,
  String id, {
  String? event,
}) => _recipients(
  hints.where(
    (hint) =>
        hint['entity'] == entity &&
        hint['id'] == id &&
        (event == null || hint['event'] == event),
  ),
);

Set<String> _recipients(Iterable<Map<String, dynamic>> hints) => {
  for (final hint in hints) ...(hint['user_ids']! as List).cast<String>(),
};

Future<void> _seed(Connection writer) async {
  for (final (index, user) in [
    _postAuthor,
    _budAuthor,
    _invitee,
    _uninvited,
    _cancelled,
    _requestAuthor,
    _requestMember,
  ].indexed) {
    await writer.execute(
      Sql.named('''
INSERT INTO public."user" (id, display_name, public_key)
VALUES (@id, @id, @key)
'''),
      parameters: {'id': user, 'key': pgTestPublicKey('bud-delete', index + 1)},
    );
  }
  await writer.execute('''
INSERT INTO public.beacon
  (id, user_id, title, description, kind, is_discoverable,
   parent_beacon_id, published_at)
VALUES
  ('$_post', '$_postAuthor', '', '', 1, false, NULL, now()),
  ('$_bud', '$_budAuthor', 'Bud', '', 0, false, '$_post', now()),
  ('$_request', '$_requestAuthor', 'Request', '', 0, false, NULL, now()),
  ('$_requestChild', '$_requestAuthor', 'Child Request', '', 0, false,
   '$_request', now())
''');
  await writer.execute('''
INSERT INTO public.beacon_forward_edge (beacon_id, sender_id, recipient_id)
VALUES
  ('$_post', '$_postAuthor', '$_budAuthor'),
  ('$_post', '$_postAuthor', '$_invitee'),
  ('$_post', '$_postAuthor', '$_uninvited'),
  ('$_post', '$_postAuthor', '$_cancelled'),
  ('$_bud', '$_budAuthor', '$_invitee'),
  ('$_bud', '$_budAuthor', '$_cancelled')
''');
  await writer.execute('''
UPDATE public.beacon_forward_edge SET cancelled_at = now()
WHERE beacon_id = '$_bud' AND recipient_id = '$_cancelled'
''');
  await writer.execute('''
INSERT INTO public.beacon_participant (beacon_id, user_id, room_access)
VALUES ('$_request', '$_requestMember', 3)
''');
}
