@Tags(['pg'])
library;

import 'package:postgres/postgres.dart';
import 'package:tentura_root/domain/constellation/constellation_anchor.dart';
import 'package:tentura_root/domain/entity/person_auto_tag_kind.dart';
import 'package:tentura_server/consts/people_tag_consts.dart';
import 'package:tentura_server/data/database/tentura_db.dart'
    hide isNotNull, isNull;
import 'package:tentura_server/data/repository/constellation_anchor_repository.dart';
import 'package:tentura_server/data/repository/constellation_tag_magnet_repository.dart';
import 'package:tentura_server/data/repository/owner_graph_unit_of_work.dart';
import 'package:tentura_server/data/repository/people_tags_repository.dart';
import 'package:tentura_server/domain/entity/constellation_tag_magnet.dart';
import 'package:tentura_server/domain/entity/person_tag.dart';
import 'package:tentura_server/domain/exception.dart';
import 'package:tentura_server/domain/exception_codes.dart';
import 'package:tentura_server/domain/port/constellation_anchor_repository_port.dart';
import 'package:tentura_server/domain/port/constellation_tag_magnet_repository_port.dart';
import 'package:tentura_server/domain/port/owner_graph_transaction_port.dart';
import 'package:tentura_server/domain/port/people_tags_repository_port.dart';
import 'package:test/test.dart';

import '../../support/disposable_pg_target.dart';
import '../../support/owner_graph_contention.dart';
import '../../support/pg_test_public_keys.dart';

const _owner = 'Utaggraphown1';
const _other = 'Utaggraphown2';
const _person = 'Utaggraphpeer';
final _autoKind = PersonAutoTagKind.newOnField.smallintValue;
const _anchorPosition = ConstellationAnchorPosition(
  xUnits: 4,
  yUnits: -2,
  coordinateSpaceVersion: 1,
);

Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_PEOPLE_GRAPH_OWNER_SCOPE_TEST_DB',
    defaultNamePrefix: 'tentura_test_people_graph_scope',
  );
  final skipReason = await pgSkipReason(target);
  if (skipReason != null) {
    test('Postgres unavailable', () {}, skip: skipReason);
    return;
  }

  late DisposablePgWriterSession session;
  late OwnerGraphTransactionPort graph;
  late PeopleTagsRepositoryPort tags;
  late ConstellationTagMagnetRepositoryPort magnets;

  TenturaDb openDatabase() {
    final database = openDisposablePgDatabase(target);
    addTearDown(database.close);
    return database;
  }

  setUpAll(() async {
    final previous = driftRuntimeOptions.dontWarnAboutMultipleDatabases;
    // The holder and competing writes use independent database executors.
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    addTearDown(
      () => driftRuntimeOptions.dontWarnAboutMultipleDatabases = previous,
    );
    session = await setUpDisposablePgWriter(target: target);
    addTearDown(() => tearDownDisposablePgWriter(session: session));
    graph = OwnerGraphUnitOfWork(openDatabase());
    for (final (index, id) in [_owner, _other, _person].indexed) {
      await session.writer.execute(
        Sql.named('''
INSERT INTO public."user" (id, display_name, public_key)
VALUES (@id, @id, @key)
'''),
        parameters: {'id': id, 'key': pgTestPublicKey('tagsc', index + 1)},
      );
    }
    // This fact gives the automatic tag a filter row even before it is edited.
    await session.writer.execute(
      Sql.named('''
INSERT INTO public.person_field_first_seen (viewer_id, peer_id)
VALUES (@owner, @person)
'''),
      parameters: {'owner': _owner, 'person': _person},
    );
  });

  setUp(() async {
    await session.writer.execute('''
TRUNCATE public.person_tag, public.person_tag_op_log,
  public.person_tag_suggestion_state, public.person_tag_revision,
  public.person_auto_tag_pref, public.constellation_anchor,
  public.constellation_anchor_cursor, public.constellation_anchor_op_log,
  public.constellation_anchor_target_watermark CASCADE
''');
    final db = openDatabase();
    tags = PeopleTagsRepository(db);
    magnets = ConstellationTagMagnetRepository(db);
  });

  Future<PersonTag> create(
    PeopleTagsRepositoryPort repository,
    String name,
    String opId, {
    String owner = _owner,
  }) => repository.create(
    ownerId: owner,
    name: name,
    glyph: 'F',
    clientOpId: opId,
    fingerprint: 'create:$name',
  );

  Future<void> addMember(PeopleTagsRepositoryPort repository, String tagId) =>
      repository.applyMembers(
        ownerId: _owner,
        clientOpId: 'add-member',
        fingerprint: 'add:$tagId:$_person',
        ops: [
          PersonTagMemberOp(
            tagId: tagId,
            personId: _person,
            add: true,
            source: kPersonTagSourceManual,
          ),
        ],
      );

  Future<ConstellationTagMagnet> placeMagnet(
    ConstellationTagMagnetRepositoryPort repository,
    String tagId,
  ) => repository.upsert(
    viewerId: _owner,
    tagId: tagId,
    xUnits: 2.5,
    yUnits: -1.25,
    clientOpId: 'place-magnet',
  );

  Future<List<String>> tagReceipts() async => [
    for (final row in await session.writer.execute(
      Sql.named('''
SELECT client_op_id FROM public.person_tag_op_log WHERE owner_id = @owner
'''),
      parameters: {'owner': _owner},
    ))
      row.single! as String,
  ];

  Future<(T, bool)> writeWhileScopeHeld<T>(Future<T> Function() write) async {
    late Future<T> result;
    final waited = await whileOwnerGraphScopeHeld(graph, _owner, () {
      result = write().timeout(ownerGraphWriteLimit)..ignore();
      return waitsForOwnerGraphScope(session.writer, _owner, result);
    });
    return (await result, waited);
  }

  group('People graph writes sharing the owner scope', () {
    test(
      'two tag creates queue for their owner while another owner can commit',
      () async {
        final otherConnection = PeopleTagsRepository(openDatabase());
        late Future<PersonTag> first;
        late Future<PersonTag> second;
        final (
          sameOwnerWaited,
          visibleWhileHeld,
        ) = await whileOwnerGraphScopeHeld(graph, _owner, () async {
          final differentOwner = create(
            otherConnection,
            'Neighbours',
            'other-create',
            owner: _other,
          ).timeout(ownerGraphWriteLimit)..ignore();
          expect(
            await waitsForOwnerGraphScope(
              session.writer,
              _owner,
              differentOwner,
            ),
            isFalse,
          );
          expect(await otherConnection.list(_other), [await differentOwner]);

          first = create(
            tags,
            'Friends',
            'friends-create',
          ).timeout(ownerGraphWriteLimit)..ignore();
          final waited = await waitsForOwnerGraphScope(
            session.writer,
            _owner,
            first,
          );
          second = create(
            otherConnection,
            'Colleagues',
            'colleagues-create',
          ).timeout(ownerGraphWriteLimit)..ignore();
          final visible = await session.writer.execute(
            Sql.named(
              'SELECT id FROM public.person_tag WHERE owner_id = @owner',
            ),
            parameters: {'owner': _owner},
          );
          return (waited, visible);
        });

        final created = await Future.wait([first, second]);
        expect(created.map((tag) => tag.name), ['Friends', 'Colleagues']);
        expect(await tags.list(_owner), unorderedEquals(created));
        expect(
          sameOwnerWaited,
          isTrue,
          reason: 'The tag create must queue on its own owner scope.',
        );
        expect(visibleWhileHeld, isEmpty);
      },
    );

    test(
      'tag membership and an anchor batch can both commit for an owner',
      () async {
        final tag = await create(tags, 'Friends', 'create-for-membership');
        final anchors = ConstellationAnchorRepository(openDatabase());
        final anchorTarget = ConstellationAnchorTarget.person(_person);
        late Future<void> membership;
        late Future<AnchorApplyBatchResult> batch;
        final tagWaited = await whileOwnerGraphScopeHeld(
          graph,
          _owner,
          () async {
            membership = addMember(tags, tag.id).timeout(ownerGraphWriteLimit)
              ..ignore();
            final waited = await waitsForOwnerGraphScope(
              session.writer,
              _owner,
              membership,
            );
            batch =
                anchors
                    .applyBatch(
                      viewerId: _owner,
                      ops: [
                        AnchorApplyOp(
                          clientOpId: 'pin-person',
                          kind: AnchorOpKind.upsert,
                          target: anchorTarget,
                          position: _anchorPosition,
                        ),
                      ],
                    )
                    .timeout(ownerGraphWriteLimit)
                  ..ignore();
            return waited;
          },
        );

        await membership;
        final result = (await batch).results.single;
        expect(result.status, AnchorOpStatus.ok);
        expect(
          await anchors.readWatermark(_owner),
          result.resultingTargetRevision,
        );
        expect(await tags.tagIdsOf(_owner, _person), [tag.id]);
        expect(
          tagWaited,
          isTrue,
          reason:
              'Tag membership must queue on the same scope as an anchor batch.',
        );
      },
    );

    test(
      'placing a tag magnet waits for its viewer and persists its position',
      () async {
        final tag = await create(tags, 'Friends', 'create-for-magnet');
        final (placed, waited) = await writeWhileScopeHeld(
          () => placeMagnet(magnets, tag.id),
        );

        expect(
          (placed.tagId, placed.xUnits, placed.yUnits),
          (tag.id, 2.5, -1.25),
        );
        expect(await magnets.list(_owner), [placed]);
        expect(
          waited,
          isTrue,
          reason: 'The magnet placement must wait for its viewer.',
        );
      },
    );

    test(
      'hiding an automatic tag filter waits for its owner and persists',
      () async {
        expect((await tags.autoTags(_owner)).single.showInFilters, isTrue);
        final (updated, waited) = await writeWhileScopeHeld(
          () => tags.setAutoTagPref(
            ownerId: _owner,
            kind: _autoKind,
            showInFilters: false,
          ),
        );

        expect(
          (updated.kind, updated.count, updated.showInFilters),
          (_autoKind, 1, false),
        );
        final listed = (await tags.autoTags(_owner)).single;
        expect((listed.kind, listed.showInFilters), (_autoKind, false));
        expect(
          waited,
          isTrue,
          reason: 'The filter preference must wait for its owner scope.',
        );
      },
    );

    test(
      'a queued tag mutation replays its receipt only for the same payload',
      () async {
        final first = await create(tags, 'Friends', 'create-once');
        final (replayed, waited) = await writeWhileScopeHeld(
          () => create(tags, 'Friends', 'create-once'),
        );

        expect(replayed, first);
        await expectLater(
          create(tags, 'Family', 'create-once'),
          throwsA(
            isA<PeopleTagsException>().having(
              (error) => (error.code as PeopleTagsExceptionCodes).exceptionCode,
              'exception code',
              PeopleTagsExceptionCode.opIdReused,
            ),
          ),
        );
        expect(await tags.list(_owner), [first]);
        expect(await tagReceipts(), ['create-once']);
        expect(
          waited,
          isTrue,
          reason:
              'Tag replays must go through the same owner scope as new writes.',
        );
      },
    );
  });

  group('People graph writes with owner scope enforcement enabled', () {
    Future<TenturaDb> enforcedDatabase() async {
      await enforceOwnerScope(session);
      final database = openDatabase();
      final setting = await database
          .customSelect(
            "SELECT current_setting('tentura.owner_scope_enforce') AS setting",
          )
          .getSingle();
      expect(setting.read<String>('setting'), 'on');
      return database;
    }

    test('tag creation commits both the tag and its receipt', () async {
      final enforced = PeopleTagsRepository(await enforcedDatabase());
      final tag = await create(enforced, 'Friends', 'scoped-create');
      expect(tag.name, 'Friends');
      expect(await tags.list(_owner), [tag]);
      expect(await tagReceipts(), ['scoped-create']);
    });

    test('adding a person commits the membership and its receipt', () async {
      final tag = await create(tags, 'Friends', 'create-before-enforcement');
      final enforced = PeopleTagsRepository(await enforcedDatabase());
      await addMember(enforced, tag.id);
      expect(await tags.tagIdsOf(_owner, _person), [tag.id]);
      expect(
        await tagReceipts(),
        unorderedEquals(['create-before-enforcement', 'add-member']),
      );
    });

    test(
      'disabling tag suggestions commits the decision and its receipt',
      () async {
        final enforced = PeopleTagsRepository(await enforcedDatabase());
        final result = await enforced.recordSuggestion(
          ownerId: _owner,
          clientOpId: 'disable-suggestions',
          fingerprint: 'suggestion:disabled',
          outcome: 'disabled',
        );

        expect(result.canSuggest, isFalse);
        expect((await tags.suggestionState(_owner)).disabled, isTrue);
        expect(await tagReceipts(), ['disable-suggestions']);
      },
    );

    test('placing a tag magnet commits its position for the viewer', () async {
      final tag = await create(tags, 'Friends', 'create-before-enforcement');
      final enforced = ConstellationTagMagnetRepository(
        await enforcedDatabase(),
      );
      final placed = await placeMagnet(enforced, tag.id);
      expect(
        (placed.tagId, placed.xUnits, placed.yUnits),
        (tag.id, 2.5, -1.25),
      );
      expect(await magnets.list(_owner), [placed]);
    });

    test(
      'showing an automatic tag filter commits the owner preference',
      () async {
        final enforced = PeopleTagsRepository(await enforcedDatabase());
        final updated = await enforced.setAutoTagPref(
          ownerId: _owner,
          kind: _autoKind,
          showInFilters: true,
        );
        expect((updated.kind, updated.showInFilters), (_autoKind, true));
        final rows = await session.writer.execute(
          Sql.named('''
SELECT show_in_filters FROM public.person_auto_tag_pref
WHERE owner_id = @owner AND kind = @kind
'''),
          parameters: {'owner': _owner, 'kind': _autoKind},
        );
        expect(rows.map((row) => row.single), [true]);
      },
    );
  });
}
