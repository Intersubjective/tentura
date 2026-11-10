import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:logging/logging.dart';

import 'package:tentura/design_system/tentura_theme.dart';
import 'package:tentura/env.dart';
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
const _loggerName = 'tag-suggestion-write-failure-test';

/// Suggestions are allowed, but every outcome write fails.
final class _FailingWriteRepository implements PeopleTagsRepositoryPort {
  int writes = 0;

  @override
  Future<PersonTagSuggestionState> personTagSuggestionState() async =>
      const PersonTagSuggestionState(canSuggest: true, disabled: false);

  @override
  Future<PersonTagSuggestionState> personTagSuggestionRecord({
    required String outcome,
    required String clientOpId,
  }) async {
    writes++;
    throw StateError('write failed: $outcome');
  }

  @override
  Future<List<PersonTag>> personTags() async => const [_tagA];

  @override
  Future<List<PersonTagMembers>> personTagMemberships() async => const [];

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

void main() {
  late _FailingWriteRepository repository;
  late PeopleTagsCase peopleTags;
  late TestRealtimeSyncPort realtimePort;
  late List<LogRecord> records;
  late StreamSubscription<LogRecord> logSub;

  setUp(() async {
    records = [];
    logSub = Logger.root.onRecord
        .where((r) => r.loggerName == _loggerName)
        .listen(records.add);
    repository = _FailingWriteRepository();
    final realtime = buildTestRealtimeSync();
    realtimePort = realtime.port;
    peopleTags = PeopleTagsCase(
      _FailingWriteRepository(),
      realtime.case_,
      env: const Env(),
      logger: Logger('test'),
    );
    await peopleTags.load();
    GetIt.I
      ..registerSingleton<PeopleTagsCase>(peopleTags)
      ..registerSingleton<PeopleTagSuggestionCase>(
        PeopleTagSuggestionCase(
          repository,
          env: const Env(),
          logger: Logger(_loggerName),
        ),
      );
  });

  tearDown(() async {
    await logSub.cancel();
    await GetIt.I.reset();
    await peopleTags.dispose();
    await realtimePort.dispose();
  });

  Widget app() => MaterialApp(
    theme: TenturaTheme.light(),
    localizationsDelegates: L10n.localizationsDelegates,
    supportedLocales: L10n.supportedLocales,
    home: Scaffold(
      body: TagSuggestionCard(
        event: PeopleTagSuggestionEvent.mutualTrust('u1'),
        personIds: const ['u1'],
        names: 'Ann',
      ),
    ),
  );

  Future<void> revealOptOut(WidgetTester tester, String label) async {
    if (find.text(label).evaluate().isNotEmpty) return;
    await tester.tap(
      find.descendant(
        of: find.byKey(_card),
        matching: find.byType(PopupMenuButton<void>),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('tag suggestion card write failures', () {
    testWidgets('a failing Not now still hides the card and logs a warning', (
      tester,
    ) async {
      await tester.pumpWidget(app());
      await tester.pumpAndSettle();
      expect(find.byKey(_card), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('tag-suggestion-not-now')));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(repository.writes, 1);
      expect(find.byKey(_card), findsNothing);
      expect(records, hasLength(1));
      expect(records.single.level, Level.WARNING);
      expect(records.single.error, isA<StateError>());
    });

    testWidgets(
      "a failing Don't suggest again still hides the card and logs a warning",
      (tester) async {
        await tester.pumpWidget(app());
        await tester.pumpAndSettle();
        await revealOptOut(tester, "Don't suggest again");

        await tester.tap(find.text("Don't suggest again"));
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        expect(repository.writes, 1);
        expect(find.byKey(_card), findsNothing);
        expect(records, hasLength(1));
        expect(records.single.level, Level.WARNING);
        expect(records.single.error, isA<StateError>());
      },
    );
  });
}
