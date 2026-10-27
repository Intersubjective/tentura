import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:logging/logging.dart';

import 'package:tentura/design_system/tentura_theme.dart';
import 'package:tentura/env.dart';
import 'package:tentura/domain/entity/realtime/realtime_entity_change.dart';
import 'package:tentura/features/people_tags/domain/entity/people_tag_suggestion_event.dart';
import 'package:tentura/features/people_tags/domain/entity/people_tags_entities.dart';
import 'package:tentura/features/people_tags/domain/port/people_tags_repository_port.dart';
import 'package:tentura/features/people_tags/domain/use_case/people_tag_suggestion_case.dart';
import 'package:tentura/features/people_tags/domain/use_case/people_tags_case.dart';
import 'package:tentura/features/people_tags/ui/widget/tag_suggestion_card.dart';
import 'package:tentura/ui/l10n/l10n.dart';

import '../../support/test_realtime_sync.dart';

const _tagA = PersonTag(id: 'Ta', name: 'Crew', glyph: 'C', color: 0, ord: 0);
const _card = ValueKey('tag-suggestion-card');

/// The server side shared by both repositories: `disabled` turns suggestions
/// off, `enabled` back on.
final class _Server {
  bool disabled = false;
}

/// Each repository keeps its own log of recorded outcomes, so a test can tell
/// which one a caller went through.
final class _FakeRepository implements PeopleTagsRepositoryPort {
  _FakeRepository(this._server);

  final _Server _server;
  final recorded = <String>[];
  final applied = <PersonTagMemberOp>[];
  List<PersonTag> tags = const [_tagA];
  int tagsCalls = 0;
  int membershipCalls = 0;

  bool get disabled => _server.disabled;

  PersonTagSuggestionState get _state =>
      PersonTagSuggestionState(canSuggest: !disabled, disabled: disabled);

  @override
  Future<PersonTagSuggestionState> personTagSuggestionState() async => _state;

  @override
  Future<PersonTagSuggestionState> personTagSuggestionRecord({
    required String outcome,
    required String clientOpId,
  }) async {
    recorded.add(outcome);
    if (outcome == 'disabled') _server.disabled = true;
    if (outcome == 'enabled') _server.disabled = false;
    return _state;
  }

  @override
  Future<List<PersonTag>> personTags() async {
    tagsCalls++;
    return tags;
  }

  @override
  Future<List<PersonTagMembers>> personTagMemberships() async {
    membershipCalls++;
    return const [];
  }

  @override
  Future<void> personTagMembersApply({
    required List<PersonTagMemberOp> ops,
    required String clientOpId,
  }) async {
    applied.addAll(ops);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

void main() {
  // The use case gets [repository]; the tags case gets [tagsRepository]. An
  // outcome must reach the server through the use case only.
  late _FakeRepository repository;
  late _FakeRepository tagsRepository;
  late PeopleTagsCase peopleTags;
  late TestRealtimeSyncPort realtimePort;

  setUp(() async {
    final server = _Server();
    repository = _FakeRepository(server);
    tagsRepository = _FakeRepository(server);
    final realtime = buildTestRealtimeSync();
    realtimePort = realtime.port;
    peopleTags = PeopleTagsCase(
      tagsRepository,
      realtime.case_,
      env: const Env(),
      logger: Logger('test'),
    );
    GetIt.I
      ..registerSingleton<PeopleTagsCase>(peopleTags)
      ..registerSingleton<PeopleTagSuggestionCase>(
        PeopleTagSuggestionCase(
          repository,
          env: const Env(),
          logger: Logger('test'),
        ),
      );
  });

  tearDown(() async {
    await GetIt.I.reset();
    await peopleTags.dispose();
    await realtimePort.dispose();
  });

  Widget app(String id, {Locale locale = const Locale('en')}) => MaterialApp(
    theme: TenturaTheme.light(),
    locale: locale,
    localizationsDelegates: L10n.localizationsDelegates,
    supportedLocales: L10n.supportedLocales,
    home: Scaffold(
      body: TagSuggestionCard(
        event: PeopleTagSuggestionEvent.mutualTrust(id),
        personIds: [id],
        names: 'Ann',
      ),
    ),
  );

  testWidgets(
    'a cold suggestion offers own tags and enables Add when selected',
    (tester) async {
      await tester.pumpWidget(app('u1'));
      await tester.pumpAndSettle();
      expect(find.byKey(_card), findsOneWidget);
      expect(find.text('Crew'), findsOneWidget);
      await tester.tap(find.text('Crew'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<FilledButton>(
              find.byKey(const ValueKey('tag-suggestion-add')),
            )
            .onPressed,
        isNotNull,
      );
      await tester.tap(find.byKey(const ValueKey('tag-suggestion-add')));
      await tester.pumpAndSettle();
      expect(tagsRepository.applied.map((o) => (o.tagId, o.personId, o.add)), [
        ('Ta', 'u1', true),
      ]);
      expect(repository.recorded, ['accepted']);
      expect(find.byKey(_card), findsNothing);
    },
  );
  testWidgets('suggestions reuse loaded tags and display realtime changes', (
    tester,
  ) async {
    await tester.pumpWidget(app('u1'));
    await tester.pumpAndSettle();
    expect(tagsRepository.tagsCalls, 1);
    expect(tagsRepository.membershipCalls, 1);
    await tester.pumpWidget(app('u2'));
    await tester.pumpAndSettle();
    expect(tagsRepository.tagsCalls, 1);
    expect(tagsRepository.membershipCalls, 1);
    tagsRepository.tags = const [
      PersonTag(id: 'Tb', name: 'Runners', glyph: 'R', color: 1, ord: 0),
    ];
    realtimePort.emitChange(
      RealtimeEntityChange(
        kind: RealtimeEntityKind.personTag,
        aggregateId: 'owner',
        operation: RealtimeOperation.update,
        source: RealtimeChangeSource.serverInvalidation,
        revision: BigInt.one,
      ),
    );
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 600)),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    expect(tagsRepository.tagsCalls, 2);
    expect(tagsRepository.membershipCalls, 2);
    expect(find.text('Crew'), findsNothing);
    expect(find.text('Runners'), findsOneWidget);
  });
}
