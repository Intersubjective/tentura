@Tags(['pg', 'repo-files'])
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io' show File, HttpServer, HttpStatus, InternetAddress;
import 'dart:typed_data';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:http/http.dart' as http;
// MultipartFile exposes the media type from http's dependency.
// ignore: depend_on_referenced_packages
import 'package:http_parser/http_parser.dart';
import 'package:image/image.dart' as image;
import 'package:injectable/injectable.dart' show Environment;
import 'package:logging/logging.dart';
import 'package:postgres/postgres.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_plus/shelf_plus.dart' show Handler, Request, Response;
import 'package:test/test.dart';

import 'package:tentura_server/api/root_router.dart';
import 'package:tentura_server/app/di.dart';
import 'package:tentura_server/domain/port/remote_storage_port.dart';
import 'package:tentura_server/domain/use_case/auth_case.dart';
import 'package:tentura_server/env.dart';

import '../../../support/disposable_pg_target.dart';
import '../../../support/hasura_pg_jwt_keys.dart';
import '../../../support/isolated_hasura_session.dart';
import '../../../support/pg_test_public_keys.dart';
import '../../../support/session_database_di_harness.dart';

const _origin = 'http://127.0.0.1:2080';
const _owner = 'U781a00000001';
const _viewer = 'U781b00000002';
const _requestId = 'B781a00000001';
const _ownerName = 'Riley Request Author';
const _viewerName = 'Casey Request Helper';
const _privateNames = ['Clover Private 731', 'Rowan Private 846'];
const _privateTag = 'PT781a000001';
const _privateTagName = 'Orchid Private Circle';
const _viewerTag = 'PT781b000002';
const _noteSearch = 'GardenLedger731';
const _entryNote = 'Seed order for GardenLedger731';
const _accountNote = 'Pickup schedule for GardenLedger731';
const _pendingForwardNote = 'Bring the blue watering can from Plot 43';
const _ownerAvatarPrefix = 'private/$_owner/';

final _phantomIdPattern = RegExp('PH[0-9a-f]{12}');

Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_PRIVATE_PEOPLE_VISIBILITY_TEST_DB',
    defaultNamePrefix: 'tentura_test_private_people_visibility',
  );
  final skip = await pgSkipReason(target);
  final hasDocker =
      skip == null &&
      await IsolatedHasuraSession.isDockerAvailable(requiredForPg: false);

  group('Private Field entries on a shared Request', () {
    late _Api api;
    late List<String> privateIds;
    late String inviteCode;
    late _JsonReply previewBeforeForward;
    late Connection writer;
    late List<String> avatarKeys;
    final storage = _AvatarStorage();
    final jpeg = image.encodeJpg(image.Image(width: 8, height: 8));

    void expectNoPrivateNotesOrAvatarKeys(String wire, {String? read}) {
      expect(
        wire,
        isNot(
          anyOf(
            contains(_entryNote),
            contains(_accountNote),
            contains(_pendingForwardNote),
            contains(_ownerAvatarPrefix),
            contains(Uri.encodeComponent(_ownerAvatarPrefix)),
          ),
        ),
        reason: read,
      );
    }

    void expectNoPrivateEntries(String wire) {
      // Search the entire body, including IDs embedded in URLs or text.
      expect(wire, isNot(matches(_phantomIdPattern)));
      for (final value in [...privateIds, ..._privateNames]) {
        expect(wire, isNot(contains(value)));
      }
    }

    setUpAll(() async {
      final previousWarning =
          driftRuntimeOptions.dontWarnAboutMultipleDatabases;
      driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
      addTearDown(() {
        driftRuntimeOptions.dontWarnAboutMultipleDatabases = previousWarning;
      });
      final session = await setUpDisposablePgWriter(
        target: target,
        createPgmer2Extension: true,
      );
      writer = session.writer;
      addTearDown(() => tearDownDisposablePgWriter(session: session));
      addTearDown(() async {
        getIt.skipDoubleRegistration = false;
        await getIt.reset();
      });

      final jwt = loadJwtKeysForHasuraPgTests();
      final db = target.databaseEnv;
      getIt.registerSingleton<RemoteStoragePort>(storage);
      await configureSessionDatabaseTestGraph(
        Env(
          environment: Environment.dev,
          serverUri: Uri.parse(_origin),
          publicOrigin: _origin,
          publicKey: jwt.publicKey,
          privateKey: jwt.privateKey,
          pgHost: db.pgHost,
          pgPort: db.pgPort,
          pgDatabase: db.pgDatabase,
          pgUsername: db.pgUsername,
          pgPassword: db.pgPassword,
          maxConnectionCount: 1,
          workersCount: 1,
          printEnv: false,
          isDebugModeOn: false,
          sentryDsn: '',
        ),
      );
      final handler = (await getIt.getAsync<RootRouter>()).routeHandler();
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      shelf_io.serveRequests(server, handler);
      api = _Api(handler, Uri.parse('http://127.0.0.1:${server.port}'));
      await _seedSharedRequest(writer);
      privateIds = [
        for (final name in _privateNames) await api.createPerson(name),
      ];
      await _seedTags(writer, privateIds);
      inviteCode = await api.ensureInvite(privateIds.first);

      final entry = {'phantomId': privateIds.first};
      const account = {'userId': _viewer};
      for (final (subject, body) in [
        (entry, _entryNote),
        (account, _accountNote),
      ]) {
        await api.saveNote(subject, body);
        final note = await api.query(_owner, _readNote, subject);
        expect(note['personNote'], [containsPair('body', body)]);
        await api.uploadAvatar(subject, jpeg);
      }
      avatarKeys = storage.objects.keys.toList();
      expect(avatarKeys, hasLength(2));
      expect(avatarKeys, everyElement(startsWith(_ownerAvatarPrefix)));
      final ownerField = await api.query(_owner, _field);
      expect(
        (ownerField['constellationField']! as Map)['phantoms'],
        contains(
          allOf(
            containsPair('id', privateIds.first),
            containsPair('hasPrivateAvatar', true),
          ),
        ),
      );

      final forwarded = await api.query(
        _owner,
        r'''
mutation ForwardToHelper($request: String!, $helper: String!) {
  beaconForward(id: $request, recipientIds: [$helper]) { deliveredRecipientIds }
}
''',
        {'request': _requestId, 'helper': _viewer},
      );
      expect(
        forwarded['beaconForward'],
        containsPair('deliveredRecipientIds', [_viewer]),
      );

      previewBeforeForward = await api.preview(
        inviteCode,
        requestId: _requestId,
      );
      final saved = await api.query(
        _owner,
        r'''
mutation SaveInviteForward($request: String!, $person: String!, $note: String!) {
  beaconForwardToPhantom(beaconId: $request, phantomId: $person, note: $note)
}
''',
        {
          'request': _requestId,
          'person': privateIds.first,
          'note': _pendingForwardNote,
        },
      );
      expect(
        saved['beaconForwardToPhantom'],
        '/invite/$inviteCode?r=$_requestId',
      );
      final pending = await writer.execute(
        Sql.named('''
SELECT state, note FROM public.phantom_pending_forward
WHERE sender_id = @owner AND phantom_id = @person AND beacon_id = @request
'''),
        parameters: {
          'owner': _owner,
          'person': privateIds.first,
          'request': _requestId,
        },
      );
      expect(pending.map((row) => row.toList()), [
        ['pending', _pendingForwardNote],
      ]);

      await writer.execute('''
INSERT INTO public.beacon_participant (beacon_id, user_id, role, status, room_access)
VALUES ('$_requestId', '$_viewer', 6, 0, 3)
''');

      if (hasDocker) {
        await _seedMeritRankGraph(writer);
        final hasura = await IsolatedHasuraSession.start(
          databaseEnv: db,
          jwtPublicPem: jwt.publicKey,
        );
        addTearDown(hasura.stop);
        await hasura.applyRepoMetadata();
        api.hasura = hasura;
      }
    });

    test(
      'each account sees the shared Request and only its own entries',
      () async {
        final asOwner = await api.query(_owner, _field);
        final ownerField = asOwner['constellationField']! as Map;
        expect(ownerField['peers'], contains(containsPair('id', _viewer)));
        expect(
          ownerField['requests'],
          contains(containsPair('id', _requestId)),
        );
        expect(
          ownerField['phantoms'],
          unorderedEquals([
            for (final (index, id) in privateIds.indexed)
              allOf(
                containsPair('id', id),
                containsPair('displayName', _privateNames[index]),
                containsPair('ownTagIds', [_privateTag]),
                containsPair('hasPrivateAvatar', index == 0),
              ),
          ]),
        );

        final asViewer = await api.query(_viewer, _field);
        final viewerField = asViewer['constellationField']! as Map;
        expect(viewerField['peers'], contains(containsPair('id', _owner)));
        expect(
          viewerField['requests'],
          contains(containsPair('id', _requestId)),
        );
        expect(viewerField['phantoms'], isEmpty);
        expectNoPrivateEntries(asViewer.wire);
        expectNoPrivateNotesOrAvatarKeys(
          asViewer.wire,
          read: 'constellationField',
        );
      },
    );

    test('people tags show the viewer’s tags and members', () async {
      const tags = r'''
query PeopleTags($person: String!) {
  personTags { id name }
  personTagMemberships { tagId personIds inherited { personId inviterId } }
  personTagsOf(personId: $person) { own auto { kind n direction } }
}
''';
      final asOwner = await api.query(_owner, tags, {'person': _viewer});
      expect(
        asOwner['personTagMemberships'],
        contains(
          allOf(
            containsPair('tagId', _privateTag),
            containsPair('personIds', unorderedEquals(privateIds)),
          ),
        ),
      );

      final asViewer = await api.query(_viewer, tags, {'person': _owner});
      expect(asViewer['personTags'], contains(containsPair('id', _viewerTag)));
      expect(
        asViewer['personTagMemberships'],
        contains(
          allOf(
            containsPair('tagId', _viewerTag),
            containsPair('personIds', [_owner]),
          ),
        ),
      );
      expect(asViewer['personTagsOf'], containsPair('own', [_viewerTag]));
      expectNoPrivateEntries(asViewer.wire);
      expectNoPrivateNotesOrAvatarKeys(
        asViewer.wire,
        read: 'people tags and memberships',
      );
    });

    test(
      'forward candidates show the real contact on the shared Request',
      () async {
        final response = await api.query(
          _viewer,
          '''
query RequestForwardCandidates {
  forwardCandidates(context: "") {
    id displayName
    forward_reach {
      via { id displayName }
      shared_request_id shared_request_title
    }
  }
}
''',
        );
        expect(
          response['forwardCandidates'],
          contains(
            allOf(
              containsPair('id', _owner),
              containsPair('displayName', _ownerName),
              containsPair(
                'forward_reach',
                containsPair('shared_request_id', _requestId),
              ),
            ),
          ),
        );
        expectNoPrivateEntries(response.wire);
        expectNoPrivateNotesOrAvatarKeys(
          response.wire,
          read: 'forwardCandidates',
        );
      },
    );

    test(
      'the Request’s forward graph and inbound sources show the real forward',
      () async {
        final response = await api.query(
          _viewer,
          r'''
query RequestForwards($request: String!) {
  beaconForwardGraph(id: $request) {
    beaconId authorId viewerId helpOffererIds
    edges {
      id senderId recipientId
      sender { userId displayName }
      recipient { userId displayName }
    }
  }
  beaconEligibleInboundForwards(id: $request) { edgeId senderId senderName }
}
''',
          {'request': _requestId},
        );
        final graph = response['beaconForwardGraph']! as Map;
        expect(graph['beaconId'], _requestId);
        final edges = (graph['edges']! as List).cast<Map<String, Object?>>();
        expect(edges, [
          allOf(
            containsPair('senderId', _owner),
            containsPair('recipientId', _viewer),
            containsPair(
              'sender',
              {'userId': _owner, 'displayName': _ownerName},
            ),
            containsPair(
              'recipient',
              {'userId': _viewer, 'displayName': _viewerName},
            ),
          ),
        ]);
        expect(response['beaconEligibleInboundForwards'], [
          allOf(
            containsPair('edgeId', edges.single['id']),
            containsPair('senderId', _owner),
            containsPair('senderName', _ownerName),
          ),
        ]);
        expectNoPrivateEntries(response.wire);
        expectNoPrivateNotesOrAvatarKeys(
          response.wire,
          read: 'beaconForwardGraph and beaconEligibleInboundForwards',
        );
      },
    );

    test(
      'only the issuer sees the linked person when opening the invite code',
      () async {
        const document = r'''
query InvitationDetails($code: String!) {
  invitationById(id: $code) {
    id issuer_id invited_id beacon_id phantom_id addressee_name
    issuer { id displayName }
  }
}
''';
        final asOwner = await api.query(_owner, document, {'code': inviteCode});
        expect(
          asOwner['invitationById'],
          allOf(
            containsPair('id', inviteCode),
            containsPair('phantom_id', privateIds.first),
            containsPair('addressee_name', _privateNames.first),
          ),
        );

        final asViewer = await api.query(_viewer, document, {
          'code': inviteCode,
        });
        final invitation = asViewer['invitationById']! as Map;
        expect(invitation['id'], inviteCode);
        expect(invitation['issuer'], containsPair('id', _owner));
        expect(invitation['phantom_id'], isNull);
        expect(invitation['addressee_name'], isNull);
        expectNoPrivateEntries(asViewer.wire);
        expectNoPrivateNotesOrAvatarKeys(asViewer.wire, read: 'invitationById');
      },
    );

    for (final (description, hasForward, includeRequest) in [
      (
        'a bare Request hint grants no preview before a forward is saved',
        false,
        true,
      ),
      (
        'an invite preview without a Request hint protects the saved forward',
        true,
        false,
      ),
      (
        'a Request hint shows the saved Request and protects the invite recipient',
        true,
        true,
      ),
    ]) {
      test(
        description,
        () async {
          final preview = hasForward
              ? await api.preview(
                  inviteCode,
                  requestId: includeRequest ? _requestId : null,
                )
              : previewBeforeForward;
          expect(preview['codeStatus'], 'available');
          expect(preview['callerStatus'], 'existing-user');
          expect(preview['inviter'], {
            'id': _owner,
            'displayName': _ownerName,
            'image': null,
          });
          expect(
            preview['beacon'],
            hasForward && includeRequest
                ? containsPair('id', _requestId)
                : isNull,
          );
          expectNoPrivateEntries(preview.wire);
          expectNoPrivateNotesOrAvatarKeys(
            preview.wire,
            read: includeRequest
                ? 'invite preview with r'
                : 'invite preview without r',
          );
          expect(preview.wire, isNot(contains(_privateTag)));
          expect(preview.wire, isNot(contains(_privateTagName)));
        },
      );
    }

    test('the attention feed shows the real Request forward', () async {
      final response = await api.query(
        _viewer,
        '''
query SharedRequestActivity {
  attentionFeed(view: "all") {
    page {
      items {
        ...Receipt
        eventsPreview { ...Receipt }
      }
    }
  }
}
fragment Receipt on AttentionReceipt {
  id beaconId actorUserId beaconAuthorId beaconAuthorName
  title body targetEntityId presentationPayloadJson provenanceJson
}
''',
      );
      final feed = response['attentionFeed']! as Map;
      final page = feed['page']! as Map;
      expect(page['items'], contains(containsPair('beaconId', _requestId)));
      expectNoPrivateEntries(response.wire);
      expectNoPrivateNotesOrAvatarKeys(response.wire, read: 'attentionFeed');
    });

    for (final (centre, description) in [
      (_viewer, 'the viewer'),
      (_owner, 'the invite issuer'),
    ]) {
      test(
        'the graph centred on $description shows real trust edges',
        () async {
          final response = await api.graph(centre);
          expect(
            response['graph'],
            contains(
              allOf(
                containsPair('src', centre == _viewer ? _owner : _viewer),
                containsPair('dst', centre),
                containsPair(
                  'user',
                  allOf(
                    containsPair('id', centre),
                    containsPair(
                      'display_name',
                      centre == _viewer ? _viewerName : _ownerName,
                    ),
                  ),
                ),
              ),
            ),
          );
          expectNoPrivateEntries(response.wire);
          expectNoPrivateNotesOrAvatarKeys(
            response.wire,
            read: 'graph around $description',
          );
        },
        skip: hasDocker
            ? false
            : 'Docker required for the authenticated Hasura graph',
      );
    }

    test('Hasura tracks no view derived from private avatar storage', () async {
      final Object? document = jsonDecode(
        File('../../hasura/metadata.json').readAsStringSync(),
      );
      final sources = switch (document) {
        {'metadata': {'sources': final List<Object?> sources}} => sources,
        _ => throw const FormatException('Missing Hasura metadata sources'),
      };
      final tracked = <(String, String)>{};
      for (final source in sources) {
        final entries = switch (source) {
          {'tables': final List<Object?> tables} => tables,
          Map<String, Object?>() when source['tables'] == null =>
            const <Object?>[],
          _ => throw const FormatException('Invalid Hasura table list'),
        };
        for (final entry in entries) {
          tracked.add(switch (entry) {
            {
              'table': {
                'schema': final String schema,
                'name': final String name,
              },
            } =>
              (
                schema,
                name,
              ),
            _ => throw const FormatException('Invalid Hasura table entry'),
          });
        }
      }
      expect(tracked, contains(('public', 'user')));

      // PostgreSQL records dependencies even when views rename their output
      // columns, and the recursion follows views built on top of other views.
      final relations = await writer.execute('''
WITH RECURSIVE avatar_relations(oid) AS (
  VALUES ('public.person_private_avatar'::regclass::oid),
         ('public.private_object_gc'::regclass::oid)
  UNION
  SELECT rewrite.ev_class
  FROM avatar_relations AS source
  JOIN pg_depend AS dependency
    ON dependency.refclassid = 'pg_class'::regclass
    AND dependency.refobjid = source.oid
    AND dependency.classid = 'pg_rewrite'::regclass
  JOIN pg_rewrite AS rewrite ON rewrite.oid = dependency.objid
  JOIN pg_class AS view ON view.oid = rewrite.ev_class
  WHERE view.relkind IN ('v', 'm')
)
SELECT ns.nspname::text, relation.relname::text
FROM avatar_relations
JOIN pg_class AS relation USING (oid)
JOIN pg_namespace AS ns ON ns.oid = relation.relnamespace
''');
      final privateRelations = {
        for (final row in relations)
          switch (row) {
            [final String schema, final String name] => (schema, name),
            _ => throw const FormatException('Invalid PostgreSQL relation row'),
          },
      };
      expect(tracked.intersection(privateRelations), isEmpty);
    });

    test('the note subject cannot read the owner’s note about them', () async {
      final reply = await api.query(_viewer, _readNote, {'userId': _viewer});
      expect(reply['personNote'], isEmpty);
      expectNoPrivateNotesOrAvatarKeys(reply.wire);
    });

    test(
      'a contact cannot read notes on the owner’s private Field entry',
      () async {
        final wire = await api.post(_viewer, _readNote, {
          'phantomId': privateIds.first,
        });
        final reply = jsonDecode(wire) as Map<String, Object?>;
        expectNoPrivateNotesOrAvatarKeys(wire);
        expect(wire, isNot(contains(_privateNames.first)));

        if (reply['errors'] != null) {
          expect(
            reply['errors'],
            contains(
              containsPair(
                'extensions',
                containsPair('code', allOf(matches(r'^\d+$'), isNot('1000'))),
              ),
            ),
            reason: wire,
          );
          expect(
            (reply['data'] as Map?)?['personNote'],
            anyOf(isNull, isFalse),
          );
        } else {
          expect(
            reply['data'],
            containsPair(
              'personNote',
              anyOf(isNull, isFalse, equals(const [])),
            ),
            reason: wire,
          );
        }
      },
    );

    test(
      'contacts cannot find the owner’s notes by changing the query case',
      () async {
        final asOwner = await api.query(_owner, _searchNotes, {
          'q': _noteSearch,
        });
        expect(
          asOwner['personNoteSearch'],
          unorderedEquals([
            {'subjectUserId': _viewer, 'subjectPhantomId': null},
            {'subjectUserId': null, 'subjectPhantomId': privateIds.first},
          ]),
        );

        for (final q in [_noteSearch, _noteSearch.toUpperCase()]) {
          final asViewer = await api.query(_viewer, _searchNotes, {'q': q});
          expect(asViewer['personNoteSearch'], isEmpty, reason: q);
          expectNoPrivateEntries(asViewer.wire);
          expectNoPrivateNotesOrAvatarKeys(
            asViewer.wire,
            read: 'personNoteSearch',
          );
          expect(asViewer.wire, isNot(contains(_viewer)));
        }
      },
    );

    test('only the uploader can download either private avatar', () async {
      for (final key in avatarKeys) {
        final ownerDownload = await api.downloadAvatar(_owner, key);
        expect(ownerDownload.statusCode, HttpStatus.ok);
        expect(
          await ownerDownload.read().expand((chunk) => chunk).toList(),
          jpeg,
        );

        final viewerDownload = await api.downloadAvatar(_viewer, key);
        expect(viewerDownload.statusCode, HttpStatus.forbidden);
        expect(
          viewerDownload.headers['content-type'] ?? '',
          isNot(startsWith('image/')),
        );
        final deniedBytes = await viewerDownload
            .read()
            .expand((chunk) => chunk)
            .toList();
        expect(deniedBytes, isNot(equals(jpeg)));
        expect(
          deniedBytes.take(3).toList(),
          isNot(equals(jpeg.take(3).toList())),
        );
      }
    });

    for (final (caller, person, status) in [
      ('the owner', _owner, HttpStatus.ok),
      ('a denied viewer', _viewer, HttpStatus.forbidden),
    ]) {
      test(
        'avatar download logs hide the key for $caller when the parameter name has a UTF-8 BOM',
        () async {
          final key = avatarKeys.first;
          final requestLogs = <String>[];
          final response = await runZoned(
            () => api.downloadAvatar(
              person,
              key,
              queryName: '%EF%BB%BFobjectKey',
            ),
            zoneSpecification: ZoneSpecification(
              print: (_, _, _, line) => requestLogs.add(line),
            ),
          );
          expect(response.statusCode, status);
          final bytes = await response.read().expand((chunk) => chunk).toList();
          expect(
            bytes,
            status == HttpStatus.ok ? equals(jpeg) : isNot(equals(jpeg)),
          );

          final downloads = requestLogs.where(
            (line) => line.contains('/api/v2/private-avatars'),
          );
          expect(downloads, hasLength(1));
          expect(downloads.single, contains('[$status]'));
          expect(
            requestLogs.join('\n'),
            isNot(
              anyOf(contains(key), contains(Uri.encodeQueryComponent(key))),
            ),
          );
        },
      );
    }

    test(
      'saving, reading, searching and deleting notes keeps their text out of server logs',
      () async {
        const initial = 'PrivateLogNoteCreate731';
        const edited = 'PrivateLogNoteEdit846';
        const search = 'NoteEdit846';
        final subject = {'phantomId': privateIds.last};
        final records = <LogRecord>[];
        final requestLogs = <String>[];
        final previousLevel = Logger.root.level;
        Logger.root.level = Level.ALL;
        final subscription = Logger.root.onRecord.listen(records.add);
        addTearDown(() async {
          await subscription.cancel();
          Logger.root.level = previousLevel;
        });

        await runZoned(
          () async {
            await api.saveNote(subject, initial);
            await api.saveNote(subject, edited);
            final read = await api.query(_owner, _readNote, subject);
            expect(read['personNote'], [containsPair('body', edited)]);
            final hits = await api.query(_owner, _searchNotes, {'q': search});
            expect(hits['personNoteSearch'], [
              containsPair('subjectPhantomId', privateIds.last),
            ]);
            final deleted = await api.query(_owner, r'''
mutation personNoteDelete($phantomId: String!) {
  personNoteDelete(subjectPhantomId: $phantomId)
}
''', subject);
            expect(deleted['personNoteDelete'], isTrue);
          },
          zoneSpecification: ZoneSpecification(
            print: (_, _, _, line) => requestLogs.add(line),
          ),
        );

        expect(
          requestLogs.where((line) => line.contains('/api/v2/graphql')),
          hasLength(5),
        );
        final logText = [
          ...requestLogs,
          for (final record in records)
            '${record.loggerName}: ${record.message} ${record.error} ${record.stackTrace} ${record.object}',
        ].join('\n');
        expect(
          logText,
          isNot(anyOf(contains(initial), contains(edited), contains(search))),
        );
      },
    );

    test(
      'creating, renaming and inviting a private person keeps names out of server logs',
      () async {
        const initial = 'PrivateCreateMarker 287';
        const renamed = 'PrivateRenameMarker 942';
        final records = <LogRecord>[];
        final requestLogs = <String>[];
        final previousLevel = Logger.root.level;
        Logger.root.level = Level.ALL;
        final subscription = Logger.root.onRecord.listen(records.add);
        addTearDown(() async {
          await subscription.cancel();
          Logger.root.level = previousLevel;
        });

        await runZoned(
          () async {
            final person = await api.createPerson(initial);
            final updated = await api.query(
              _owner,
              r'''
mutation RenamePrivatePerson($id: String!, $name: String!) {
  phantomUpdate(id: $id, name: $name)
}
''',
              {'id': person, 'name': renamed},
            );
            expect(updated['phantomUpdate'], isTrue);
            final invite = await api.ensureInvite(person);
            final details = await api.query(
              _owner,
              r'''
query RenamedInvite($id: String!) {
  invitationById(id: $id) { phantom_id addressee_name }
}
''',
              {'id': invite},
            );
            expect(details['invitationById'], {
              'phantom_id': person,
              'addressee_name': renamed,
            });
          },
          zoneSpecification: ZoneSpecification(
            print: (_, _, _, line) => requestLogs.add(line),
          ),
        );

        expect(
          requestLogs.where((line) => line.contains('/api/v2/graphql')),
          hasLength(4),
        );
        final logText = [
          ...requestLogs,
          for (final record in records)
            '${record.loggerName}: ${record.message} ${record.error} ${record.stackTrace}',
        ].join('\n');
        expect(
          logText,
          allOf(isNot(contains(initial)), isNot(contains(renamed))),
        );
      },
    );
  }, skip: skip);
}

const _field = '''
query PrivatePeopleField {
  constellationField {
    phantoms { id displayName ownTagIds hasPrivateAvatar }
    linkHints { phantomId userId }
    peers { id displayName temporaryBeaconId }
    directContactIds
    requests { id authorId forwardedById forwardedByName }
    edges { src dst }
    memberWebs { beaconId personId }
    anchorProjection {
      anchors { targetId }
      pinnedPeers { id displayName }
      pinnedRequests { id authorId forwardedById forwardedByName }
      supportPeers { id displayName }
      supportEdges { src dst }
    }
  }
}
''';

const _readNote = r'''
query personNote($userId: String, $phantomId: String) {
  personNote(subjectUserId: $userId, subjectPhantomId: $phantomId) {
    body phantomName
  }
}
''';

const _searchNotes = r'''
query personNoteSearch($q: String!) {
  personNoteSearch(q: $q) { subjectUserId subjectPhantomId }
}
''';

Future<void> _seedSharedRequest(Connection writer) async {
  for (final (index, (id, name)) in [
    (_owner, _ownerName),
    (_viewer, _viewerName),
  ].indexed) {
    await writer.execute(
      Sql.named('''
INSERT INTO public."user" (id, display_name, public_key)
VALUES (@id, @name, @key)
'''),
      parameters: {
        'id': id,
        'name': name,
        'key': pgTestPublicKey('private-field-entries', index + 1),
      },
    );
  }
  await writer.execute('''
INSERT INTO public.vote_user (subject, object, amount)
VALUES ('$_owner', '$_viewer', 1), ('$_viewer', '$_owner', 1)
''');
  await writer.execute('''
INSERT INTO public.user_trust_edge (subject, object, trust_w, target_w)
VALUES ('$_owner', '$_viewer', 1, 1), ('$_viewer', '$_owner', 1, 1)
ON CONFLICT (subject, object) DO NOTHING
''');
  await writer.execute('''
INSERT INTO public.beacon
  (id, user_id, title, description, status, kind, is_discoverable, published_at)
VALUES ('$_requestId', '$_owner', 'Help with the garden', '', 0, 0, true, now())
''');
}

Future<void> _seedTags(Connection writer, List<String> privateIds) =>
    withPgOwnerScopes(writer, [_owner, _viewer], (tx) async {
      await tx.execute('''
INSERT INTO public.person_tag (id, owner_id, name, glyph, color, ord)
VALUES ('$_privateTag', '$_owner', '$_privateTagName', 'O', 0, 0),
       ('$_viewerTag', '$_viewer', 'Gardeners', 'G', 0, 0)
''');
      await tx.execute(
        Sql.named('''
INSERT INTO public.phantom_tag_member (tag_id, owner_id, phantom_id, source)
SELECT '$_privateTag', '$_owner', id, 0 FROM unnest(@ids::text[]) AS id
'''),
        parameters: {'ids': privateIds},
      );
      await tx.execute('''
INSERT INTO public.person_tag_member (tag_id, owner_id, person_id, source)
VALUES ('$_viewerTag', '$_viewer', '$_owner', 0)
''');
    });

// The extension normally fetches its graph from a shared MeritRank service.
// Supply its external snapshot from the fixture’s committed trust edges. The
// tracked graph function, Hasura permissions and user relationship run as-is.
Future<void> _seedMeritRankGraph(Connection writer) => writer.execute(r'''
CREATE OR REPLACE FUNCTION public.mr_graph(
  ego text, focus text, context text DEFAULT '',
  positive_only boolean DEFAULT false, index bigint DEFAULT 0, count bigint DEFAULT 16
) RETURNS TABLE (
  src text, dst text, weight double precision,
  score_value_of_dst double precision, score_value_of_ego double precision,
  score_cluster_of_dst integer, score_cluster_of_ego integer
) LANGUAGE sql STABLE AS $snapshot$
  SELECT e.subject, e.object, e.target_w,
         0::double precision, 0::double precision, 0::integer, 0::integer
  FROM public.user_trust_edge e
  WHERE e.target_w > 0 AND (e.subject = focus OR e.object = focus)
$snapshot$
''');

final class _Api {
  _Api(this._handler, this._uploadOrigin);

  final Handler _handler;
  final Uri _uploadOrigin;
  late IsolatedHasuraSession hasura;

  String _authorization(String person) =>
      'Bearer ${getIt<AuthCase>().issueAccessToken(person).rawToken}';

  Future<String> createPerson(String name) async {
    final data = await query(
      _owner,
      r'mutation CreatePrivatePerson($name: String!) { phantomCreate(name: $name) }',
      {'name': name},
    );
    final id = data['phantomCreate'];
    expect(id, startsWith('PH'));
    return id! as String;
  }

  Future<String> ensureInvite(String id) async {
    final data = await query(
      _owner,
      r'mutation EnsurePrivateInvite($id: String!) { phantomInviteEnsure(id: $id) }',
      {'id': id},
    );
    final code = data['phantomInviteEnsure'];
    expect(code, allOf(isA<String>(), isNotEmpty));
    return code! as String;
  }

  Future<_JsonReply> preview(String code, {String? requestId}) async {
    final uri = Uri.parse('$_origin/api/v2/invite/$code/preview');
    final response = await _handler(
      Request(
        'GET',
        requestId == null
            ? uri
            : uri.replace(queryParameters: {'r': requestId}),
        headers: {'authorization': _authorization(_viewer)},
      ),
    );
    final body = await response.readAsString();
    expect(response.statusCode, 200, reason: body);
    return _JsonReply(body, jsonDecode(body) as Map<String, Object?>);
  }

  Future<void> saveNote(Map<String, Object?> subject, String body) async {
    final reply = await query(
      _owner,
      r'''
mutation personNoteUpsert($userId: String, $phantomId: String, $body: String!) {
  personNoteUpsert(subjectUserId: $userId, subjectPhantomId: $phantomId, body: $body)
}
''',
      {...subject, 'body': body},
    );
    expect(reply['personNoteUpsert'], isTrue);
  }

  Future<void> uploadAvatar(
    Map<String, Object?> subject,
    Uint8List jpeg,
  ) async {
    final multipart =
        http.MultipartRequest(
            'POST',
            _uploadOrigin.resolve('/api/v2/graphql'),
          )
          ..headers['authorization'] = _authorization(_owner)
          ..fields['operations'] = jsonEncode({
            'operationName': 'UploadAvatar',
            'query': r'''
mutation UploadAvatar($userId: String, $phantomId: String, $file: Upload) {
  personPrivateAvatarUpload(subjectUserId: $userId, subjectPhantomId: $phantomId, file: $file)
}
''',
            'variables': {
              ...subject,
              'file': {'filename': 'avatar.jpg', 'type': 'image/jpeg'},
            },
          })
          ..fields['map'] = jsonEncode({
            '0': ['variables.file'],
          })
          ..files.add(
            http.MultipartFile.fromBytes(
              '0',
              jpeg,
              filename: 'avatar.jpg',
              contentType: MediaType('image', 'jpeg'),
            ),
          );
    final response = await http.Response.fromStream(await multipart.send());
    expect(response.statusCode, 200, reason: response.body);
    final reply = _responseData(response.body);
    expect(reply['personPrivateAvatarUpload'], isTrue);
  }

  Future<Response> downloadAvatar(
    String person,
    String key, {
    String queryName = 'objectKey',
  }) async => _handler(
    Request(
      'GET',
      Uri.parse(
        '$_origin/api/v2/private-avatars',
      ).replace(query: '$queryName=${Uri.encodeQueryComponent(key)}'),
      headers: {'authorization': _authorization(person)},
    ),
  );

  Future<String> post(
    String person,
    String document,
    Map<String, Object?> variables,
  ) async {
    final response = await _handler(
      Request(
        'POST',
        Uri.parse('$_origin/api/v2/graphql'),
        headers: {
          'content-type': 'application/json',
          'authorization': _authorization(person),
        },
        body: jsonEncode({'query': document, 'variables': variables}),
      ),
    );
    final wire = await response.readAsString();
    expect(response.statusCode, 200, reason: wire);
    return wire;
  }

  Future<_JsonReply> query(
    String person,
    String document, [
    Map<String, Object?> variables = const {},
  ]) async => _responseData(await post(person, document, variables));

  Future<_JsonReply> graph(String centre) async {
    final response = await http.post(
      Uri.parse('${hasura.baseUrl}/v1/graphql'),
      headers: {
        'content-type': 'application/json',
        'authorization': _authorization(_viewer),
      },
      body: jsonEncode({
        'query': r'''
query GraphAroundPerson($centre: String!) {
  graph(args: {focus: $centre, context: "", positive_only: true}) {
    src dst user { id display_name }
  }
}
''',
        'variables': {'centre': centre},
      }),
    );
    expect(response.statusCode, 200, reason: response.body);
    return _responseData(response.body);
  }

  _JsonReply _responseData(String body) {
    final payload = jsonDecode(body) as Map<String, Object?>;
    expect(payload['errors'], isNull, reason: body);
    final data = payload['data'];
    expect(data, isA<Map<String, Object?>>(), reason: body);
    return _JsonReply(body, data! as Map<String, Object?>);
  }
}

final class _JsonReply {
  const _JsonReply(this.wire, this._data);

  final String wire;
  final Map<String, Object?> _data;

  Object? operator [](String field) => _data[field];
}

// Keep the GraphQL, database and download paths real while replacing S3.
final class _AvatarStorage implements RemoteStoragePort {
  final objects = <String, Uint8List>{};

  @override
  Future<String> putObject(
    String path,
    Stream<Uint8List> bytes, {
    Map<String, String>? metadata,
  }) async {
    final buffer = BytesBuilder(copy: false);
    await bytes.forEach(buffer.add);
    objects[path] = buffer.takeBytes();
    return path;
  }

  @override
  Future<Uint8List> getObject(String path) async => objects[path]!;

  @override
  Future<void> removeObject(String path) async {
    objects.remove(path);
  }
}
