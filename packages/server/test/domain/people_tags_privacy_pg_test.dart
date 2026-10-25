@Tags(['pg'])
library;

import 'dart:async';
import 'dart:convert';

import 'package:graphql_server2/graphql_server2.dart' show GraphQL;
import 'package:injectable/injectable.dart' show Environment;
import 'package:logging/logging.dart';
import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'package:tentura_server/api/controllers/graphql/input/_input_types.dart';
import 'package:tentura_server/api/controllers/graphql/schema.dart';
import 'package:tentura_server/api/controllers/graphql/mappers/constellation_gql_maps.dart';
import 'package:tentura_server/app/di.dart';
import 'package:tentura_server/consts/constellation_consts.dart';
import 'package:tentura_server/domain/entity/constellation_anchor_projection.dart';
import 'package:tentura_server/domain/entity/constellation_field.dart';
import 'package:tentura_server/domain/entity/jwt_entity.dart';
import 'package:tentura_server/domain/use_case/constellation_field_case.dart';
import 'package:tentura_server/domain/use_case/constellation_field_requests_case.dart';
import 'package:tentura_server/env.dart';

import '../support/disposable_pg_target.dart';

const _tagger = 'Uptprivtagger001';
const _tagged = 'Uptprivtagged0001';
const _bystander = 'Uptprivbystand001';

const _request = 'Bptprivrequest1';

/// Unique enough that finding it anywhere outside the tagger's own responses
/// is a leak. Every tag name used by the run contains it.
const _secret = 'Secret-Name-123';
const _created = _secret;
const _renamed = '$_secret-renamed';
const _fromRequest = '$_secret-from-request';
const _fromAutoTag = '$_secret-from-auto';
const _glyph = 'Ж';

const _mutualContact = 0;
const _sourceManual = 0;

const _tagFields = 'id name glyph color ord count countOffField';

const _createDoc =
    '''
mutation Create(
  \$name: String!, \$clientOpId: String!, \$glyph: String,
  \$fromAutoKind: Int, \$fromBeaconId: String, \$color: Int
) {
  personTagCreate(
    name: \$name, clientOpId: \$clientOpId, glyph: \$glyph,
    fromAutoKind: \$fromAutoKind, fromBeaconId: \$fromBeaconId,
    color: \$color
  ) { $_tagFields }
}
''';

const _updateDoc =
    '''
mutation Update(\$id: String!, \$name: String, \$clientOpId: String!) {
  personTagUpdate(id: \$id, name: \$name, clientOpId: \$clientOpId) {
    $_tagFields
  }
}
''';

const _deleteDoc = r'''
mutation Delete($id: String!, $clientOpId: String!) {
  personTagDelete(id: $id, clientOpId: $clientOpId) {
    tag { id name glyph color ord }
    memberIds
    sources
  }
}
''';

const _restoreDoc =
    '''
mutation Restore(\$snapshot: PersonTagSnapshotInput!, \$clientOpId: String!) {
  personTagRestore(snapshot: \$snapshot, clientOpId: \$clientOpId) {
    $_tagFields
  }
}
''';

const _applyDoc = r'''
mutation Apply($ops: [PersonTagMemberOpInput!]!, $clientOpId: String!) {
  personTagMembersApply(ops: $ops, clientOpId: $clientOpId)
}
''';

/// Every people-tag read the app has, as the viewer sees it.
const _tagReadsDoc = r'''
query TagReads($personId: String!, $kind: Int!) {
  personTags { id name glyph color ord count countOffField }
  personTagsOf(personId: $personId) { own auto { kind } }
  personAutoTags { kind count showInFilters }
  personTagMemberships { tagId personIds }
  personAutoTagMembers(kind: $kind)
  personTagSuggestionState { canSuggest silencedUntil disabled }
}
''';

const _prefDoc = r'''
mutation Pref($kind: Int!, $showInFilters: Boolean!) {
  personAutoTagPrefSet(kind: $kind, showInFilters: $showInFilters) {
    kind count showInFilters
  }
}
''';

/// The profile surface: the Requests the viewer shares with one person.
const _sharedContextsDoc = r'''
query SharedContexts($userId: String!) {
  personSharedContexts(userId: $userId) { beaconId title }
}
''';

const _fieldDoc = '''
query Field {
  constellationField {
    context
    peers {
      id displayName handle pinState visible contactOnly presence
      temporaryBeaconId bondContexts { beaconId title }
    }
    edges { __typename }
    requests { id authorId title status }
    directContactIds
    posts { __typename }
    memberWebs { __typename }
  }
}
''';

/// A tagged person must learn nothing about the tagger's private tags: not
/// from their own reads, not from side channels (notifications, activity,
/// error text, realtime hints, the server log). The tagger uses every tag
/// operation on the tagged person, then everything the tagged person can ask
/// or receive is searched for the tag names and ids.
Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_PEOPLE_TAGS_PRIVACY_TEST_DB',
    defaultNamePrefix: 'tentura_test_people_tags_privacy',
  );
  final pgSkip = await pgSkipReason(target);
  if (pgSkip != null) {
    test('Postgres unavailable', () {}, skip: pgSkip);
    return;
  }

  group('people tags privacy', () {
    late DisposablePgWriterSession session;
    late Connection writer;
    late Connection listener;
    late StreamSubscription<String> notificationSubscription;
    late StreamSubscription<LogRecord> logSubscription;
    late GraphQL schema;
    var opCounter = 0;

    final rawNotifications = <String>[];
    final logLines = <String>[];
    final seenTagIds = <String>{};

    // Every tag name any request of the run carried; the inline literals of
    // the validation cases use the shared secret prefix.
    final exercisedNames = <String>{_secret};

    // What the tagged person (and a bystander) got back, one entry per read.
    final taggedResponses = <String>[];
    final bystanderResponses = <String>[];
    final failureDescriptions = <String>[];
    late Set<String> rowsBefore;
    late Map<String, dynamic> restoredTag;
    late String liveTagId;
    late bool taggerDefaultShowInFilters;

    String nextOp() => 'op-privacy-${opCounter++}';

    Future<Map<String, dynamic>> run(
      String document,
      Map<String, dynamic> variables, {
      required String sub,
    }) async {
      final snapshot = variables['snapshot'];
      for (final name in [
        if (sub == _tagger) ...[
          variables['name'],
          if (snapshot is Map<String, dynamic>)
            (snapshot['tag'] as Map<String, dynamic>)['name'],
        ],
      ]) {
        if (name is String) exercisedNames.add(name);
      }
      return await schema.parseAndExecute(
            document,
            variableValues: variables,
            globalVariables: {kGlobalInputQueryJwt: JwtEntity(sub: sub)},
          )
          as Map<String, dynamic>;
    }

    Future<Map<String, dynamic>> asTagger(
      String document,
      Map<String, dynamic> variables,
    ) => run(document, variables, sub: _tagger);

    /// Runs [document] as [sub]; returns the failure text, or null when it
    /// succeeded.
    Future<String?> outcomeAs(
      String sub,
      String document,
      Map<String, dynamic> variables,
    ) async {
      try {
        final result = await run(document, variables, sub: sub);
        // An executor may report a validation failure in the result.
        if (result['errors'] != null) return jsonEncode(result);
      } on Object catch (e) {
        return e.toString();
      }
      return null;
    }

    /// A refused tagger mutation: its error text, thrown or returned in the
    /// result, is kept for the error-text checks.
    Future<String> failureOf(
      String document,
      Map<String, dynamic> variables,
    ) async {
      final text = await outcomeAs(_tagger, document, variables);
      if (text == null) fail('expected the operation to fail');
      failureDescriptions.add(text);
      return text;
    }

    /// Fails when [text] carries any tag name the run used.
    void expectNoTagName(String text, {String? reason}) {
      for (final name in exercisedNames) {
        expect(text, isNot(contains(name)), reason: reason ?? 'name $name');
      }
    }

    Future<List<ConstellationPeerRecord>> fieldPeersOf(String viewer) async =>
        (await getIt<ConstellationFieldCase>().readSnapshot(
          viewerId: viewer,
          context: kConstellationContext,
          params: (
            filters: ConstellationFieldMembershipFilters.defaults,
            projection: ConstellationProjection.full,
          ),
        )).peers;

    Future<List<Map<String, dynamic>>> requestsOf(String viewer) async => [
      for (final r
          in await getIt<ConstellationFieldRequestsCase>()
              .discoverableRequestsByIds(
                viewerId: viewer,
                beaconIds: {_request},
                filters: ConstellationFieldMembershipFilters.defaults,
              ))
        constellationRequestToGqlMap(r),
    ];

    String asJson(Object? value) =>
        jsonEncode(value, toEncodable: (o) => o.toString());

    /// Everything the viewer can read about tags, the Field, the profile of
    /// the tagger and the shared Request right now.
    Future<void> readAs(String viewer, List<String> into) async {
      into
        ..add(
          jsonEncode(
            await run(
              _tagReadsDoc,
              {'personId': _tagger, 'kind': _mutualContact},
              sub: viewer,
            ),
          ),
        )
        ..add(jsonEncode(await run(_fieldDoc, {}, sub: viewer)))
        // The Field peers with the tag-bearing fields the V2 schema omits.
        ..add(
          asJson([
            for (final p in await fieldPeersOf(viewer))
              {
                'id': p.id,
                'ownTagIds': p.ownTagIds,
                'autoTagKinds': p.autoTagKinds,
              },
          ]),
        )
        ..add(
          jsonEncode(
            await run(_sharedContextsDoc, {'userId': _tagger}, sub: viewer),
          ),
        )
        ..add(asJson(await requestsOf(viewer)));
    }

    Future<void> afterEachStep() async {
      await readAs(_tagged, taggedResponses);
      await readAs(_bystander, bystanderResponses);
    }

    Future<void> insertUsers() async {
      for (final id in [_tagger, _tagged, _bystander]) {
        await writer.execute(
          Sql.named(
            'INSERT INTO public."user" (id, display_name, public_key) '
            'VALUES (@id, @id, @key)',
          ),
          parameters: {'id': id, 'key': '$id-key'},
        );
      }
    }

    Future<void> trust(String from, String to) => writer.execute(
      Sql.named(
        'INSERT INTO public.vote_user (subject, object, amount) '
        'VALUES (@a, @b, 1)',
      ),
      parameters: {'a': from, 'b': to},
    );

    Future<Set<String>> sideChannelRows() async {
      final rows = <String>{};
      for (final table in const [
        'notification_outbox',
        'attention_occurrence',
        'attention_occurrence_recipient',
        'beacon_activity_event',
      ]) {
        for (final r in await writer.execute(
          'SELECT to_jsonb(t)::text FROM public.$table t',
        )) {
          rows.add('$table ${r.single}');
        }
      }
      return rows;
    }

    /// Waits until asynchronous writes from the run stop arriving: the side
    /// channel tables and the notification feed stay unchanged for a while.
    Future<void> settle() async {
      var stable = 0;
      var last = (await sideChannelRows()).length + rawNotifications.length;
      while (stable < 4) {
        await Future<void>.delayed(const Duration(milliseconds: 150));
        final now = (await sideChannelRows()).length + rawNotifications.length;
        stable = now == last ? stable + 1 : 0;
        last = now;
      }
    }

    PersonTagOpMap member(String tagId, {required bool add}) => {
      'tagId': tagId,
      'personId': _tagged,
      'op': add ? 'add' : 'remove',
      'source': _sourceManual,
    };

    /// The tagged person is on the tagger's Field, trusts them back and
    /// shares a Request with them.
    Future<void> prepareWorld() async {
      // The tagged person is on the tagger's Field and trusts them back.
      await trust(_tagger, _tagged);
      await trust(_tagged, _tagger);
      await writer.execute(
        Sql.named(
          'INSERT INTO public.beacon '
          '(id, user_id, title, description, status, kind, published_at) '
          "VALUES (@id, @author, 'Request', 'd', 0, 0, now())",
        ),
        parameters: {'id': _request, 'author': _tagger},
      );
      await writer.execute(
        Sql.named(
          'INSERT INTO public.beacon_participant '
          '(beacon_id, user_id, role, room_access) '
          'VALUES (@b, @u, 1, 3)',
        ),
        parameters: {'b': _request, 'u': _tagged},
      );
    }

    /// The whole life of a tag that has the tagged person in it.
    Future<void> runScenario() async {
      await afterEachStep();

      final created = await asTagger(_createDoc, {
        'name': _created,
        'glyph': _glyph,
        'clientOpId': nextOp(),
      });
      final tagId =
          (created['personTagCreate'] as Map<String, dynamic>)['id']! as String;
      seenTagIds.add(tagId);
      await afterEachStep();

      await asTagger(_applyDoc, {
        'ops': [member(tagId, add: true)],
        'clientOpId': nextOp(),
      });
      await afterEachStep();

      await asTagger(_applyDoc, {
        'ops': [member(tagId, add: false)],
        'clientOpId': nextOp(),
      });
      await afterEachStep();

      await asTagger(_applyDoc, {
        'ops': [member(tagId, add: true)],
        'clientOpId': nextOp(),
      });
      await afterEachStep();

      await asTagger(_updateDoc, {
        'id': tagId,
        'name': _renamed,
        'clientOpId': nextOp(),
      });
      await afterEachStep();

      final deleted = await asTagger(_deleteDoc, {
        'id': tagId,
        'clientOpId': nextOp(),
      });
      final snapshot = deleted['personTagDelete'] as Map<String, dynamic>;
      await afterEachStep();

      final restored = await asTagger(_restoreDoc, {
        'snapshot': snapshot,
        'clientOpId': nextOp(),
      });
      restoredTag = restored['personTagRestore'] as Map<String, dynamic>;
      liveTagId = restoredTag['id']! as String;
      seenTagIds.add(liveTagId);
      await afterEachStep();

      final fromRequest = await asTagger(_createDoc, {
        'name': _fromRequest,
        'clientOpId': nextOp(),
        'fromBeaconId': _request,
      });
      seenTagIds.add(
        (fromRequest['personTagCreate'] as Map<String, dynamic>)['id']!
            as String,
      );
      await afterEachStep();

      final fromAuto = await asTagger(_createDoc, {
        'name': _fromAutoTag,
        'clientOpId': nextOp(),
        'fromAutoKind': _mutualContact,
      });
      seenTagIds.add(
        (fromAuto['personTagCreate'] as Map<String, dynamic>)['id']! as String,
      );
      await afterEachStep();

      // The tagger's automatic tag switch is theirs alone.
      final autoBefore = await asTagger(_tagReadsDoc, {
        'personId': _tagged,
        'kind': _mutualContact,
      });
      taggerDefaultShowInFilters =
          _autoTag(autoBefore)['showInFilters']! as bool;
      await asTagger(_prefDoc, {
        'kind': _mutualContact,
        'showInFilters': !taggerDefaultShowInFilters,
      });
      await afterEachStep();

      // Failing mutations that carry the name in their input.
      await failureOf(_createDoc, {
        'name': '$_secret-${'x' * 40}',
        'clientOpId': nextOp(),
      });
      await failureOf(_createDoc, {
        'name': _secret,
        'glyph': 'two words',
        'clientOpId': nextOp(),
      });
      await failureOf(_createDoc, {
        'name': _secret,
        'color': 99,
        'clientOpId': nextOp(),
      });
      await failureOf(_updateDoc, {
        'id': 'Ptnosuchtag00',
        'name': _secret,
        'clientOpId': nextOp(),
      });
      await failureOf(_createDoc, {
        'name': _secret,
        'clientOpId': nextOp(),
        'fromAutoKind': _mutualContact,
        'fromBeaconId': _request,
      });
      await failureOf(_restoreDoc, {
        'snapshot': {
          'tag': {
            'id': 'Ptnosuchtag01',
            'name': _secret,
            'glyph': _glyph,
            'color': 99,
            'ord': 0,
          },
          'memberIds': <String>[],
          'sources': <int>[],
        },
        'clientOpId': nextOp(),
      });
      // A name that is already taken, however it is spelled.
      await failureOf(_createDoc, {
        'name': _renamed.toUpperCase(),
        'clientOpId': nextOp(),
      });
      await failureOf(_updateDoc, {
        'id': liveTagId,
        'name': _fromRequest.toLowerCase(),
        'clientOpId': nextOp(),
      });
      // A restore that collides with a live tag by name, and by id.
      final liveTag = restoredTag;
      await failureOf(_restoreDoc, {
        'snapshot': {
          'tag': {
            'id': 'Ptfreshid0001',
            'name': liveTag['name'],
            'glyph': _glyph,
            'color': 0,
            'ord': 0,
          },
          'memberIds': <String>[],
          'sources': <int>[],
        },
        'clientOpId': nextOp(),
      });
      await failureOf(_restoreDoc, {
        'snapshot': {
          'tag': {
            'id': liveTag['id'],
            'name': '$_secret-other',
            'glyph': _glyph,
            'color': 0,
            'ord': 0,
          },
          'memberIds': <String>[],
          'sources': <int>[],
        },
        'clientOpId': nextOp(),
      });
      // An operation id reused for a different request.
      final reusedOp = nextOp();
      await asTagger(_updateDoc, {
        'id': liveTagId,
        'name': '$_secret-first',
        'clientOpId': reusedOp,
      });
      await failureOf(_updateDoc, {
        'id': liveTagId,
        'name': '$_secret-second',
        'clientOpId': reusedOp,
      });
      await afterEachStep();
    }

    final validationFailures = <String, String?>{};
    setUpAll(() async {
      session = await setUpDisposablePgWriter(target: target);
      writer = session.writer;
      listener = await Connection.open(
        target.databaseEnv.pgEndpoint,
        settings: target.databaseEnv.pgEndpointSettings,
      );
      await listener.execute('LISTEN entity_changes');
      notificationSubscription = listener.channels['entity_changes'].listen(
        rawNotifications.add,
      );

      Logger.root.level = Level.ALL;
      logSubscription = Logger.root.onRecord.listen(
        (r) => logLines.add('${r.loggerName} ${r.message} ${r.error}'),
      );

      final db = target.databaseEnv;
      await configureDependencies(
        Env(
          environment: Environment.dev,
          serverUri: Uri.parse('http://127.0.0.1:2080'),
          publicKey: Env.kJwtPublicKey,
          privateKey: Env.kJwtPrivateKey,
          pgHost: db.pgHost,
          pgPort: db.pgPort,
          pgDatabase: db.pgDatabase,
          pgUsername: db.pgUsername,
          pgPassword: db.pgPassword,
          publicOrigin: 'http://127.0.0.1:2080',
          workersCount: 1,
          printEnv: false,
          isDebugModeOn: false,
        ),
      );
      await getIt.allReady(ignorePendingAsyncCreation: true);
      schema = graphqlSchema;

      await writer.execute('TRUNCATE TABLE public."user" CASCADE');
      await insertUsers();
      await prepareWorld();
      rowsBefore = await sideChannelRows();
      await settle();
      rawNotifications.clear();

      await runScenario();
      // Another person who guesses the tag id: whatever the refusal says, it
      // must not carry the tagger's tag names.
      Future<void> refusedForTagged(
        String document,
        Map<String, dynamic> variables,
      ) async {
        final text = await outcomeAs(_tagged, document, variables);
        if (text != null) failureDescriptions.add(text);
      }

      await refusedForTagged(_updateDoc, {
        'id': liveTagId,
        'name': 'Hijacked',
        'clientOpId': nextOp(),
      });
      await refusedForTagged(_deleteDoc, {
        'id': liveTagId,
        'clientOpId': nextOp(),
      });
      await refusedForTagged(_applyDoc, {
        'ops': [
          {
            'tagId': liveTagId,
            'personId': _bystander,
            'op': 'add',
            'source': _sourceManual,
          },
        ],
        'clientOpId': nextOp(),
      });
      await refusedForTagged(_restoreDoc, {
        'snapshot': {
          'tag': {
            'id': liveTagId,
            'name': 'Hijacked',
            'glyph': 'H',
            'color': 0,
            'ord': 0,
          },
          'memberIds': <String>[],
          'sources': <int>[],
        },
        'clientOpId': nextOp(),
      });

      // Requests refused by argument validation, before any tag code runs.
      for (final (label, document) in [
        (
          'restore snapshot missing a field',
          'mutation { personTagRestore(snapshot: {tag: {id: "Ptvalid00001", '
              'name: "$_secret", glyph: "G", color: 1}, memberIds: [], '
              'sources: []}, clientOpId: "valid-1") { id } }',
        ),
        (
          'restore snapshot with a wrongly typed field',
          'mutation { personTagRestore(snapshot: {tag: {id: "Ptvalid00002", '
              'name: "$_secret", glyph: "G", color: "red", ord: 0}, '
              'memberIds: [], sources: []}, clientOpId: "valid-2") { id } }',
        ),
        (
          'restore snapshot with a wrongly typed list',
          'mutation { personTagRestore(snapshot: {tag: {id: "Ptvalid00003", '
              'name: "$_secret", glyph: "G", color: 1, ord: 0}, '
              'memberIds: "$_secret", sources: []}, clientOpId: "valid-3") '
              '{ id } }',
        ),
      ]) {
        validationFailures[label] = await outcomeAs(_tagger, document, {});
      }

      await settle();
    });

    tearDownAll(() async {
      await logSubscription.cancel();
      await notificationSubscription.cancel();
      await listener.close();
      await getIt.reset();
      await tearDownDisposablePgWriter(session: session);
    });

    void expectNoTagTraces(Iterable<String> texts, {required String where}) {
      expect(texts, isNotEmpty, reason: '$where: nothing was captured');
      expect(seenTagIds, isNotEmpty);
      for (final text in texts) {
        expectNoTagName(text, reason: where);
        for (final id in seenTagIds) {
          expect(text, isNot(contains(id)), reason: '$where leaks tag $id');
        }
      }
    }

    test('the tagged person sees no tag name or id of the tagger in any tag '
        'read or in the Field, after every step', () {
      expectNoTagTraces(taggedResponses, where: 'tagged person reads');
    });

    test('the tagged person has no tags of their own created by being '
        'tagged', () async {
      final reads = await run(
        _tagReadsDoc,
        {'personId': _tagger, 'kind': _mutualContact},
        sub: _tagged,
      );

      expect(reads['personTags'], isEmpty);
      expect(reads['personTagMemberships'], isEmpty);
      expect(
        (reads['personTagsOf'] as Map<String, dynamic>)['own'],
        isEmpty,
      );
    });

    test('a bystander the tagger never tagged sees no tag name or id', () {
      expectNoTagTraces(bystanderResponses, where: 'bystander reads');
    });

    test('the tagger reads back the tags they created, renamed and '
        'restored', () async {
      final reads = await asTagger(_tagReadsDoc, {
        'personId': _tagged,
        'kind': _mutualContact,
      });

      final names = [
        for (final t in reads['personTags'] as List<Object?>)
          (t! as Map<String, dynamic>)['name'],
      ];
      expect(
        names,
        containsAll(['$_secret-first', _fromRequest, _fromAutoTag]),
      );
    });

    test('no notification, attention occurrence or activity event created '
        'during the run contains a tag name', () async {
      final tables = await writer.execute(
        Sql.named(
          'SELECT table_name FROM information_schema.tables '
          "WHERE table_schema = 'public' AND table_name = ANY(@t)",
        ),
        parameters: {
          't': [
            'notification_outbox',
            'attention_occurrence',
            'attention_occurrence_recipient',
            'beacon_activity_event',
          ],
        },
      );
      expect(tables, hasLength(4));

      (await sideChannelRows()).difference(rowsBefore).forEach(expectNoTagName);
    });

    test('error descriptions of refused tag mutations contain no tag name', () {
      expect(failureDescriptions, hasLength(greaterThanOrEqualTo(11)));
      for (final text in failureDescriptions) {
        expectNoTagName(text);
        expect(text, isNot(contains(_glyph)));
      }
    });

    test('the tagged person sees only their own automatic tag state, not the '
        "tagger's switch or the tagger's automatic members", () async {
      final asTagged = await run(
        _tagReadsDoc,
        {'personId': _tagger, 'kind': _mutualContact},
        sub: _tagged,
      );
      final asOwner = await asTagger(_tagReadsDoc, {
        'personId': _tagged,
        'kind': _mutualContact,
      });

      // The tagger tagged the tagged person automatically and flipped the
      // switch; the tagged person trusts the tagger, so their own list holds
      // the tagger only, with their own default switch.
      expect(asOwner['personAutoTagMembers'], [_tagged]);
      expect(_autoTag(asOwner)['showInFilters'], !taggerDefaultShowInFilters);
      expect(asTagged['personAutoTagMembers'], [_tagger]);
      expect(_autoTag(asTagged)['showInFilters'], taggerDefaultShowInFilters);
      expect(_autoTag(asTagged)['count'], 1);
    });

    test('tagging someone leaves their profile and Request reads '
        'working', () async {
      final contexts = await run(
        _sharedContextsDoc,
        {'userId': _tagger},
        sub: _tagged,
      );
      final requests = await requestsOf(_tagged);

      expect(
        (contexts['personSharedContexts'] as List<Object?>)
            .cast<Map<String, dynamic>>()
            .map(
              (c) => c['beaconId'],
            ),
        contains(_request),
      );
      expect(requests.map((r) => r['id']), contains(_request));
    });

    test('the Field peers of the tagged person carry no tag ids of the '
        "tagger, while the tagger's own Field peer carries them", () async {
      final taggedPeers = await fieldPeersOf(_tagged);
      final taggerPeers = await fieldPeersOf(_tagger);

      expect(taggedPeers, isNotEmpty);
      for (final peer in taggedPeers) {
        expect(peer.ownTagIds, isEmpty, reason: 'peer ${peer.id}');
      }
      final aboutTagged = taggerPeers.singleWhere((p) => p.id == _tagged);
      expect(aboutTagged.ownTagIds, contains(liveTagId));
      expect(aboutTagged.autoTagKinds, contains(_mutualContact));
    });

    test('a request refused by argument validation does not echo the tag '
        'name back in its error', () {
      expect(validationFailures, hasLength(3));
      validationFailures.forEach((label, failure) {
        expect(failure, isNotNull, reason: '$label was not refused');
      });
      final echoing = [
        for (final e in validationFailures.entries)
          if (exercisedNames.any(e.value!.contains)) e.key,
      ];
      expect(echoing, isEmpty, reason: 'these errors echo the tag name');
    });

    test('every person_tag realtime payload goes to the tagger only and '
        'carries no name or glyph', () {
      final hints = [
        for (final raw in rawNotifications)
          if (jsonDecode(raw) as Map<String, dynamic> case final m
              when m['entity'] == 'person_tag')
            (raw: raw, json: m),
      ];

      expect(hints, isNotEmpty);
      for (final hint in hints) {
        expect(hint.json['user_ids'], [_tagger]);
        expect(hint.json['id'], _tagger);
        expect(hint.json.containsKey('name'), isFalse);
        expect(hint.json.containsKey('glyph'), isFalse);
        expectNoTagName(hint.raw);
        expect(hint.raw, isNot(contains(_glyph)));
        expect(hint.raw, isNot(contains(_tagged)));
        for (final id in seenTagIds) {
          expect(hint.raw, isNot(contains(id)));
        }
      }
    });

    test('no realtime payload of any kind reaches the tagged person with '
        'tag content', () {
      for (final raw in rawNotifications) {
        final json = jsonDecode(raw) as Map<String, dynamic>;
        if ((json['user_ids'] as List<Object?>?)?.contains(_tagged) ?? false) {
          expectNoTagName(raw);
          for (final id in seenTagIds) {
            expect(raw, isNot(contains(id)));
          }
        }
      }
    });

    test('the server log of the run contains no tag name', () {
      expect(logLines, isNotEmpty);
      logLines.forEach(expectNoTagName);
    });
  });
}

/// The mutual-contact automatic tag entry of a `TagReads` result.
Map<String, dynamic> _autoTag(Map<String, dynamic> reads) =>
    (reads['personAutoTags'] as List<Object?>)
        .cast<Map<String, dynamic>>()
        .singleWhere((t) => t['kind'] == _mutualContact);

typedef PersonTagOpMap = Map<String, Object>;
