import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:logging/logging.dart';
import 'package:tentura/app/router/root_router.dart';
import 'package:tentura/design_system/tentura_theme.dart';
import 'package:tentura/env.dart';
import 'package:tentura/features/forward/ui/message/forward_messages.dart';
import 'package:tentura/features/people_tags/domain/entity/people_tags_entities.dart';
import 'package:tentura/features/people_tags/domain/port/people_tags_repository_port.dart';
import 'package:tentura/features/people_tags/domain/use_case/people_tag_suggestion_case.dart';
import 'package:tentura/features/people_tags/domain/use_case/people_tags_case.dart';
import 'package:tentura/ui/l10n/l10n.dart';

import '../../support/test_realtime_sync.dart';

class _Router extends Fake implements RootRouter {
  @override
  final navigatorKey = GlobalKey<NavigatorState>();
}

class _RouteObserver extends NavigatorObserver {
  final pushedDialogs = <Route<dynamic>>[];

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (route is DialogRoute<dynamic>) pushedDialogs.add(route);
  }
}

class _Repository implements PeopleTagsRepositoryPort {
  bool disabled = false;
  final outcomes = <String>[];

  @override
  Future<PersonTagSuggestionState> personTagSuggestionState() async =>
      PersonTagSuggestionState(canSuggest: !disabled, disabled: disabled);

  @override
  Future<PersonTagSuggestionState> personTagSuggestionRecord({
    required String outcome,
    required String clientOpId,
  }) async {
    outcomes.add(outcome);
    if (outcome == 'disabled') disabled = true;
    return personTagSuggestionState();
  }

  @override
  Future<List<PersonTag>> personTags() async => const [];

  @override
  Future<List<PersonTagMembers>> personTagMemberships() async => const [];

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

void main() {
  late _Repository repository;
  late _Router router;
  late _RouteObserver observer;
  late PeopleTagsCase tags;
  late TestRealtimeSyncPort realtimePort;
  late int initialBarrierCount;

  setUp(() async {
    repository = _Repository();
    router = _Router();
    observer = _RouteObserver();
    final realtime = buildTestRealtimeSync();
    realtimePort = realtime.port;
    tags = PeopleTagsCase(
      repository,
      realtime.case_,
      env: const Env(),
      logger: Logger('test'),
    );
    await tags.load();
    GetIt.I
      ..registerSingleton<RootRouter>(router)
      ..registerSingleton<PeopleTagsCase>(tags)
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
    await tags.dispose();
    await realtimePort.dispose();
  });

  Future<void> openAction(WidgetTester tester) async {
    const message = ForwardLocationMyWorkAddToTagMessage(
      beaconId: 'B1',
      recipientIds: ['Uann', 'Ubob'],
      recipientNames: 'Ann, Bob',
    );
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: router.navigatorKey,
        navigatorObservers: [observer],
        theme: TenturaTheme.light(),
        locale: const Locale('en'),
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        home: Scaffold(
          body: TextButton(
            onPressed: message.onPressed,
            child: const Text('Add to tag…'),
          ),
        ),
      ),
    );
    initialBarrierCount = find.byType(ModalBarrier).evaluate().length;
    await tester.tap(find.text('Add to tag…'));
    await tester.pumpAndSettle();
  }

  void expectNoDialog() {
    expect(find.byType(Dialog), findsNothing);
    expect(find.byType(ModalBarrier), findsNWidgets(initialBarrierCount));
    expect(
      find.semantics.byPredicate(
        (node) =>
            node.getSemanticsData().role == SemanticsRole.dialog ||
            node.getSemanticsData().role == SemanticsRole.alertDialog,
      ),
      findsNothing,
    );
  }

  for (final (action, outcome) in [
    ('Not now', 'skipped'),
    ("Don't suggest again", 'disabled'),
  ]) {
    testWidgets('$action closes the forward tag suggestion dialog', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      await openAction(tester);
      expect(find.byType(Dialog), findsOneWidget);
      expect(find.byKey(const ValueKey('tag-suggestion-card')), findsOneWidget);
      if (action == "Don't suggest again") {
        await tester.tap(find.byKey(const ValueKey('tag-suggestion-menu')));
        await tester.pumpAndSettle();
      }
      await tester.tap(
        find.byKey(
          ValueKey(
            action == 'Not now'
                ? 'tag-suggestion-not-now'
                : 'tag-suggestion-dont-suggest',
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(repository.outcomes, [outcome]);
      expectNoDialog();
      semantics.dispose();
    });
  }

  testWidgets('Add to tag opens no dialog when suggestions are disabled', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    repository.disabled = true;
    await openAction(tester);
    expect(observer.pushedDialogs, isEmpty);
    expect(find.byKey(const ValueKey('tag-suggestion-card')), findsNothing);
    expectNoDialog();
    semantics.dispose();
  });
}
