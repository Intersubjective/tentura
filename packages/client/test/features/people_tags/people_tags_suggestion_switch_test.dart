import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:logging/logging.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/env.dart';
import 'package:tentura/features/people_tags/domain/entity/people_tags_entities.dart';
import 'package:tentura/features/people_tags/domain/port/people_tags_repository_port.dart';
import 'package:tentura/features/people_tags/domain/use_case/people_tag_suggestion_case.dart';
import 'package:tentura/features/people_tags/domain/use_case/people_tags_case.dart';
import 'package:tentura/features/people_tags/ui/screen/people_tags_screen.dart';
import 'package:tentura/ui/l10n/l10n.dart';

import '../../support/test_realtime_sync.dart';

const _switch = Key('people-tags-suggestions-switch');

/// The server side shared by both repositories: `disabled` turns suggestions
/// off, `enabled` back on.
final class _Server {
  _Server({required this.disabled});

  bool disabled;

  /// When set, the state read waits for it (a cold screen).
  Completer<void>? gate;
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
  Future<PersonTagSuggestionState> personTagSuggestionState() async {
    await _server.gate?.future;
    return _state;
  }

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
  Future<List<PersonTag>> personTags() async => const [];

  @override
  Future<List<PersonTagMembers>> personTagMemberships() async => const [];

  @override
  Future<List<PersonAutoTag>> personAutoTags() async => const [];

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

void main() {
  late PeopleTagsCase peopleTags;
  late TestRealtimeSyncPort realtimePort;

  // The use case gets the returned repository; the tags case gets
  // [tagsRepository]. An outcome must reach the server through the use case
  // only.
  late _FakeRepository tagsRepository;

  late _Server server;

  Future<_FakeRepository> register({required bool disabled}) async {
    server = _Server(disabled: disabled);
    final repository = _FakeRepository(server);
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
    return repository;
  }

  tearDown(() async {
    await GetIt.I.reset();
    await peopleTags.dispose();
    await realtimePort.dispose();
  });

  Future<void> pumpScreen(
    WidgetTester tester, {
    Locale locale = const Locale('en'),
  }) async {
    await tester.binding.setSurfaceSize(const Size(900, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        locale: locale,
        theme: TenturaTheme.light(),
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        home: const TenturaResponsiveScope(child: PeopleTagsScreen()),
      ),
    );
    await tester.pumpAndSettle();
  }

  bool switchValue(WidgetTester tester) =>
      tester.widget<Switch>(find.byKey(_switch)).value;

  group('people tags screen suggestions switch', () {
    testWidgets(
      'is labelled "Suggest tags" and is on while suggestions are on',
      (
        tester,
      ) async {
        await register(disabled: false);
        await pumpScreen(tester);

        expect(find.text('Suggest tags'), findsOneWidget);
        expect(switchValue(tester), isTrue);
      },
    );

    testWidgets('is labelled «Предлагать теги» in Russian', (tester) async {
      await register(disabled: false);
      await pumpScreen(tester, locale: const Locale('ru'));

      expect(find.text('Предлагать теги'), findsOneWidget);
    });

    testWidgets(
      'reflects the server state: off when suggestions are disabled',
      (
        tester,
      ) async {
        await register(disabled: true);
        await pumpScreen(tester);

        expect(switchValue(tester), isFalse);
      },
    );

    testWidgets(
      'shows a spinner, never a wrong OFF, until the state is known',
      (
        tester,
      ) async {
        await register(disabled: false);
        server.gate = Completer<void>();
        await tester.binding.setSurfaceSize(const Size(900, 1400));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        await tester.pumpWidget(
          MaterialApp(
            theme: TenturaTheme.light(),
            localizationsDelegates: L10n.localizationsDelegates,
            supportedLocales: L10n.supportedLocales,
            home: const TenturaResponsiveScope(child: PeopleTagsScreen()),
          ),
        );
        await tester.pump();

        // Cold: the value is unknown, so no switch (and no wrong OFF) yet.
        expect(find.byKey(_switch), findsNothing);
        expect(
          find.byKey(const Key('people-tags-suggestions-loading')),
          findsOneWidget,
        );

        server.gate!.complete();
        await tester.pumpAndSettle();

        expect(tester.widget<Switch>(find.byKey(_switch)).onChanged, isNotNull);
        expect(switchValue(tester), isTrue);
      },
    );

    testWidgets('turning it on calls the use case enable and shows it on', (
      tester,
    ) async {
      final repository = await register(disabled: true);
      await pumpScreen(tester);

      await tester.tap(find.byKey(_switch));
      await tester.pumpAndSettle();

      expect(repository.recorded, ['enabled']);
      expect(tagsRepository.recorded, isEmpty);
      expect(switchValue(tester), isTrue);
    });

    testWidgets('turning it off calls the use case disable and shows it off', (
      tester,
    ) async {
      final repository = await register(disabled: false);
      await pumpScreen(tester);

      await tester.tap(find.byKey(_switch));
      await tester.pumpAndSettle();

      expect(repository.recorded, ['disabled']);
      expect(tagsRepository.recorded, isEmpty);
      expect(switchValue(tester), isFalse);
    });
  });
}
