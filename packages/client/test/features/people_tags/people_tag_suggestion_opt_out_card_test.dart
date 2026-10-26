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
  Future<List<PersonTag>> personTags() async => const [_tagA];

  @override
  Future<List<PersonTagMembers>> personTagMemberships() async => const [];

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
    await peopleTags.load();
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
      ),
    ),
  );

  /// Reveals the opt-out action: it may sit on the card itself or in the
  /// card's overflow menu, so open that menu when the label is not showing.
  Future<void> revealOptOut(WidgetTester tester, String label) async {
    if (find.text(label).evaluate().isNotEmpty) return;
    final menu = find.descendant(
      of: find.byKey(_card),
      matching: find.byType(PopupMenuButton<void>),
    );
    expect(
      menu,
      findsOneWidget,
      reason: '"$label" is neither on the card nor in a card menu',
    );
    await tester.tap(menu);
    await tester.pumpAndSettle();
  }

  group('tag suggestion card opt-out', () {
    testWidgets('offers "Don\'t suggest again" on the card or its menu and keeps Not now and Add', (
      tester,
    ) async {
      await tester.pumpWidget(app('u1'));
      await tester.pumpAndSettle();

      expect(find.byKey(_card), findsOneWidget);
      await revealOptOut(tester, "Don't suggest again");
      expect(find.text("Don't suggest again"), findsOneWidget);
      expect(find.text('Not now'), findsOneWidget);
      expect(find.text('Add'), findsOneWidget);
      expect(find.byKey(const ValueKey('tag-suggestion-not-now')), findsOneWidget);
      expect(find.byKey(const ValueKey('tag-suggestion-add')), findsOneWidget);
    });

    testWidgets('offers «Больше не предлагать» in Russian', (tester) async {
      await tester.pumpWidget(app('u1', locale: const Locale('ru')));
      await tester.pumpAndSettle();

      await revealOptOut(tester, 'Больше не предлагать');
      expect(find.text('Больше не предлагать'), findsOneWidget);
    });

    testWidgets('tapping it calls the use case disable and removes the card', (
      tester,
    ) async {
      await tester.pumpWidget(app('u1'));
      await tester.pumpAndSettle();

      await revealOptOut(tester, "Don't suggest again");
      await tester.tap(find.text("Don't suggest again"));
      await tester.pumpAndSettle();

      expect(repository.recorded, ['disabled']);
      expect(tagsRepository.recorded, isEmpty);
      expect(find.byKey(_card), findsNothing);
    });

    testWidgets('no card shows for a later event once suggestions are off', (
      tester,
    ) async {
      await tester.pumpWidget(app('u1'));
      await tester.pumpAndSettle();
      await revealOptOut(tester, "Don't suggest again");
      await tester.tap(find.text("Don't suggest again"));
      await tester.pumpAndSettle();

      await tester.pumpWidget(app('u2'));
      await tester.pumpAndSettle();

      expect(find.byKey(_card), findsNothing);
      expect(repository.recorded, ['disabled']);
    });
  });
}
