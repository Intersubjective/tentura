@Tags(['pg', 'repo-files'])
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:logging/logging.dart';

import 'package:tentura/data/service/remote_api_service.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/env.dart';
import 'package:tentura/features/people_tags/data/model/people_tags_mapper.dart';
import 'package:tentura/features/people_tags/data/gql/_g/person_tag_delete.req.gql.dart';
import 'package:tentura/features/people_tags/data/repository/people_tags_repository.dart';
import 'package:tentura/features/people_tags/domain/entity/people_tags_entities.dart';
import 'package:tentura/features/people_tags/domain/port/people_tags_repository_port.dart';
import 'package:tentura/features/people_tags/domain/use_case/people_tags_case.dart';
import 'package:tentura/features/people_tags/ui/screen/people_tags_screen.dart';
import 'package:tentura/ui/l10n/l10n.dart';

import '../../support/test_realtime_sync.dart';

// Keep unrelated initial screen reads local; delete and restore use the
// production repository and real responses from a disposable server database.
final class _DeleteRepository implements PeopleTagsRepositoryPort {
  _DeleteRepository(this.remote, this.tag, this.memberId);

  final PeopleTagsRepository remote;
  final PersonTag tag;
  final String memberId;
  final finished = Completer<void>();
  PersonTagSnapshot? deletedSnapshot;
  PersonTagSnapshot? restoredSnapshot;
  bool deleted = false;

  @override
  Future<List<PersonTag>> personTags() async => deleted ? [] : [tag];

  @override
  Future<List<PersonTagMembers>> personTagMemberships() async => deleted
      ? []
      : [
          PersonTagMembers(tagId: tag.id, personIds: [memberId]),
        ];

  @override
  Future<List<PersonAutoTag>> personAutoTags() async => [];

  @override
  Future<PersonTagSuggestionState> personTagSuggestionState() async =>
      const PersonTagSuggestionState(canSuggest: false, disabled: false);

  @override
  Future<PersonTagSnapshot> personTagDelete({
    required String id,
    required String clientOpId,
  }) async {
    try {
      final snapshot = await remote.personTagDelete(
        id: id,
        clientOpId: clientOpId,
      );
      deletedSnapshot = snapshot;
      deleted = true;
      return snapshot;
    } finally {
      finished.complete();
    }
  }

  @override
  Future<PersonTag> personTagRestore({
    required PersonTagSnapshot snapshot,
    required String clientOpId,
  }) async {
    restoredSnapshot = snapshot;
    final restored = await remote.personTagRestore(
      snapshot: snapshot,
      clientOpId: clientOpId,
    );
    deleted = false;
    return restored;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

void main() {
  testWidgets(
    'deleting a populated tag shows Undo and restores its member without errors',
    (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(900, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      late Process fixture;
      late StreamIterator<String> replies;
      late String deleteDocument;
      late String deleteResponse;
      late String deleteId;
      var preparingDelete = true;
      Map<String, dynamic>? restoreRequest;
      late Completer<http.Response> restoreResponse;

      await http.runWithClient(
        () async {
          final diagnostics = StringBuffer();
          late _DeleteRepository repository;
          final realtime = buildTestRealtimeSync();
          final remote = RemoteApiService(
            const Env(),
            const WebSocketClientRealtimeSocketFactory(),
          );
          late PeopleTagsCase peopleTags;
          try {
            await tester.runAsync(() async {
              restoreResponse = Completer<http.Response>();
              fixture = await Process.start(
                'dart',
                ['run', 'test/support/people_tag_delete_graphql_fixture.dart'],
                workingDirectory: '../server',
              );
              fixture.stderr.transform(utf8.decoder).listen(diagnostics.write);
              replies = StreamIterator(
                fixture.stdout
                    .transform(utf8.decoder)
                    .transform(const LineSplitter())
                    .where((line) => line.startsWith('fixture:'))
                    .map((line) => line.substring('fixture:'.length)),
              );
              expect(
                await replies.moveNext().timeout(const Duration(minutes: 1)),
                isTrue,
                reason: 'Server fixture did not initialize: $diagnostics',
              );
              final seed = jsonDecode(replies.current) as Map<String, dynamic>;
              final tag = mapPersonTag(
                Map<String, dynamic>.from(seed['tag']! as Map),
              );
              expect(tag.count, 1);
              deleteId = tag.id;
              final deleteRequest = GPersonTagDeleteReq(
                (b) => b.vars
                  ..id = tag.id
                  ..clientOpId = 'delete-widget',
              );
              // Capture Ferry's actual outgoing document (including its
              // __typename transformation) and the fresh server response.
              // Consume the Link response even when it contains GraphQL errors;
              // the screen below must handle that same response itself.
              await remote.setSessionAuth();
              await remote
                  .request(deleteRequest)
                  .firstWhere(
                    (response) => response.dataSource == DataSource.Link,
                  );
              preparingDelete = false;
              repository = _DeleteRepository(
                PeopleTagsRepository(remote),
                tag,
                seed['memberId']! as String,
              );
              peopleTags = PeopleTagsCase(
                repository,
                realtime.case_,
                env: const Env(),
                logger: Logger('test'),
              );
              await peopleTags.load();
              GetIt.I
                ..registerSingleton<PeopleTagsCase>(peopleTags)
                ..registerSingleton<Logger>(Logger('test'));
            });

            await tester.pumpWidget(
              MaterialApp(
                locale: const Locale('en'),
                theme: TenturaTheme.light(),
                localizationsDelegates: L10n.localizationsDelegates,
                supportedLocales: L10n.supportedLocales,
                home: const TenturaResponsiveScope(child: PeopleTagsScreen()),
              ),
            );
            await tester.pumpAndSettle();
            expect(find.text('Neighbours'), findsOneWidget);
            expect(find.byType(SnackBar), findsNothing);

            final id = repository.tag.id;
            await tester.tap(find.byKey(Key('people-tags-row-menu-$id')));
            await tester.pumpAndSettle();
            await tester.tap(find.byKey(Key('people-tags-delete-$id')));
            await tester.pumpAndSettle();
            expect(repository.finished.isCompleted, isTrue);

            final context = tester.element(find.byType(PeopleTagsScreen));
            final l10n = L10n.of(context)!;
            expect(
              find.text(l10n.copyErrorDetails),
              findsNothing,
              reason:
                  'A successful tag deletion must not show the error effect. '
                  'Live server response: $deleteResponse',
            );
            expect(find.text(l10n.peopleTagsDeleted), findsOneWidget);
            expect(find.byType(SnackBarAction), findsOneWidget);
            expect(find.text('Neighbours'), findsNothing);
            expect(peopleTags.peopleInTag(id), isEmpty);
            expect(repository.deletedSnapshot!.tag.count, repository.tag.count);
            expect(repository.deletedSnapshot!.memberIds, [
              repository.memberId,
            ]);
            expect(repository.deletedSnapshot!.sources, [2]);

            await tester.tap(find.text(l10n.peopleTagsUndo));
            await tester.pumpAndSettle();
            expect(
              restoreRequest,
              isNotNull,
              reason: 'Undo must invoke the production restore mutation',
            );
            expect(
              repository.restoredSnapshot,
              same(repository.deletedSnapshot),
              reason: 'Undo must reuse the snapshot decoded from delete',
            );

            // Send the actual production client's restore payload. Do not
            // reconstruct it in the test: that would hide mapping defects.
            await tester.runAsync(() async {
              fixture.stdin.writeln(jsonEncode(restoreRequest));
              expect(await replies.moveNext(), isTrue);
              restoreResponse.complete(
                http.Response(
                  replies.current,
                  200,
                  headers: {'content-type': 'application/json'},
                ),
              );
            });
            await tester.pumpAndSettle();
            expect(
              find.text(l10n.copyErrorDetails),
              findsNothing,
              reason: 'Restoring the delete snapshot must not show an error',
            );
            expect(find.text('Neighbours'), findsOneWidget);
            expect(peopleTags.tags.single.id, id);
            expect(peopleTags.peopleInTag(id), {repository.memberId});

            // Check persisted data independently of the local screen reads.
            final persisted = await tester.runAsync(() async {
              fixture.stdin.writeln(
                jsonEncode({
                  'query': '''
query {
  personTags { id name glyph color ord count countOffField }
  personTagMemberships { tagId personIds }
}
''',
                  'variables': <String, dynamic>{},
                }),
              );
              expect(await replies.moveNext(), isTrue);
              return jsonDecode(replies.current) as Map<String, dynamic>;
            });
            expect(persisted!['errors'], isNull);
            final data = persisted['data']! as Map<String, dynamic>;
            expect(data['personTags'], [
              {
                ...personTagToWire(repository.tag),
                'count': repository.tag.count,
                'countOffField': repository.tag.countOffField,
              },
            ]);
            expect(data['personTagMemberships'], [
              {
                'tagId': id,
                'personIds': [repository.memberId],
              },
            ]);
          } finally {
            await tester.pumpWidget(const SizedBox.shrink());
            await tester.runAsync(() async {
              await remote.close();
              await peopleTags.dispose();
              await realtime.port.dispose();
              await GetIt.I.reset();
              await fixture.stdin.close();
              expect(
                await fixture.exitCode.timeout(const Duration(seconds: 20)),
                0,
                reason: diagnostics.toString(),
              );
              await replies.cancel();
            });
          }
        },
        () => MockClient((request) async {
          if (request.url.path.endsWith('/session/access-token')) {
            return http.Response(
              jsonEncode({
                'subject': 'Udeleteowner001',
                'access_token': 'test-token',
                'expires_in': 3600,
              }),
              200,
              headers: {'content-type': 'application/json'},
            );
          }
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          if (preparingDelete) {
            expect(body['operationName'], 'PersonTagDelete');
            deleteDocument = body['query']! as String;
            fixture.stdin.writeln(request.body);
            expect(await replies.moveNext(), isTrue);
            deleteResponse = replies.current;
            return http.Response(
              deleteResponse,
              200,
              headers: {'content-type': 'application/json'},
            );
          }
          if (body['operationName'] == 'PersonTagRestore') {
            expect(restoreRequest, isNull, reason: 'Undo must restore once');
            restoreRequest = body;
            return restoreResponse.future;
          }
          expect(body['operationName'], 'PersonTagDelete');
          expect(
            body['query'],
            deleteDocument,
            reason: 'Replay the real server result only for the same selection',
          );
          expect((body['variables']! as Map)['id'], deleteId);
          return http.Response(
            deleteResponse,
            200,
            headers: {'content-type': 'application/json'},
          );
        }),
      );
    },
  );
}
