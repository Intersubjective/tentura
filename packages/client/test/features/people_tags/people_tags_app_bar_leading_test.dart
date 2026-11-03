// #966: People tags screens expose a back/close control via
// AutoLeadingWithFallback (pop when stacked, fallback path after refresh).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:logging/logging.dart';

import 'package:tentura/app/router/root_router.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/env.dart';
import 'package:tentura/features/people_tags/domain/entity/people_tags_entities.dart';
import 'package:tentura/features/people_tags/domain/port/people_tags_repository_port.dart';
import 'package:tentura/features/people_tags/domain/use_case/people_tags_case.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/profile/domain/port/profile_repository_port.dart';
import 'package:tentura/features/people_tags/ui/screen/people_auto_tag_screen.dart';
import 'package:tentura/features/people_tags/ui/screen/people_tag_screen.dart';
import 'package:tentura/features/people_tags/ui/screen/people_tags_screen.dart';
import 'package:tentura/ui/l10n/l10n.dart';

import '../../support/phone_surface.dart';
import '../../support/test_realtime_sync.dart';

const _tag = PersonTag(
  id: 'Ta',
  name: 'Neighbours',
  glyph: 'N',
  color: 0,
  ord: 1,
  count: 1,
);

/// `PersonAutoTagKind.helpedMe`.
const _autoKind = 3;

final class _FakePeopleTagsRepository implements PeopleTagsRepositoryPort {
  @override
  Future<List<PersonTag>> personTags() async => [_tag];

  @override
  Future<List<PersonTagMembers>> personTagMemberships() async => const [
    PersonTagMembers(tagId: 'Ta', personIds: ['U1']),
  ];

  @override
  Future<List<PersonAutoTag>> personAutoTags() async => const [
    PersonAutoTag(kind: _autoKind, count: 1, showInFilters: false),
  ];

  @override
  Future<PersonTagSuggestionState> personTagSuggestionState() async =>
      const PersonTagSuggestionState(canSuggest: false, disabled: false);

  @override
  Future<List<String>> personAutoTagMembers(int kind) async =>
      kind == _autoKind ? const ['U1'] : const [];

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

final class _FakeProfileRepository extends Fake
    implements ProfileRepositoryPort {
  @override
  Future<List<Profile>> fetchProfilesByIds(Set<String> ids) async => [
    for (final id in ids) Profile(id: id, displayName: 'User $id'),
  ];
}

class _TestRouter extends RootStackRouter {
  _TestRouter({required this.initial, this.onNavigatePath});

  final List<PageRouteInfo<Object?>> initial;
  final void Function(String path)? onNavigatePath;

  @override
  List<AutoRoute> get routes => [
    AutoRoute(page: PeopleTagsRoute.page, path: kPathPeopleTags),
    AutoRoute(page: PeopleTagRoute.page, path: kPathPeopleTag),
    AutoRoute(page: PeopleAutoTagRoute.page, path: kPathPeopleAutoTag),
  ];

  @override
  Future<void> navigatePath(
    String path, {
    bool includePrefixMatches = false,
    OnNavigationFailure? onFailure,
  }) async {
    onNavigatePath?.call(path);
    if (onNavigatePath == null) {
      await super.navigatePath(
        path,
        includePrefixMatches: includePrefixMatches,
        onFailure: onFailure,
      );
    }
  }
}

Future<void> _registerPeopleTags() async {
  final repository = _FakePeopleTagsRepository();
  final realtime = buildTestRealtimeSync();
  final peopleTags = PeopleTagsCase(
    repository,
    realtime.case_,
    env: const Env(),
    logger: Logger('test'),
  );
  await peopleTags.load();
  GetIt.I
    ..registerSingleton<PeopleTagsRepositoryPort>(repository)
    ..registerSingleton<PeopleTagsCase>(peopleTags)
    ..registerSingleton<ProfileRepositoryPort>(_FakeProfileRepository());
  addTearDown(() async {
    await GetIt.I.reset();
    await peopleTags.dispose();
    await realtime.port.dispose();
  });
}

Future<_TestRouter> _pumpRouterApp(
  WidgetTester tester, {
  required List<PageRouteInfo<Object?>> initial,
  Locale locale = const Locale('en'),
  void Function(String path)? onNavigatePath,
}) async {
  await _registerPeopleTags();
  final router = _TestRouter(
    initial: initial,
    onNavigatePath: onNavigatePath,
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(
    MaterialApp.router(
      locale: locale,
      theme: TenturaTheme.light(),
      localizationsDelegates: L10n.localizationsDelegates,
      supportedLocales: L10n.supportedLocales,
      builder: (context, child) =>
          TenturaResponsiveScope(child: child ?? const SizedBox.shrink()),
      routerConfig: router.config(deepLinkBuilder: (_) => DeepLink(initial)),
    ),
  );
  await tester.pumpAndSettle();
  return router;
}

Future<void> _tapAppBarBack(WidgetTester tester) async {
  final back = find.descendant(
    of: find.byType(TenturaTopBar),
    matching: find.byIcon(Icons.arrow_back),
  );
  expect(back, findsOneWidget);
  await tester.tap(back);
  await tester.pumpAndSettle();
}

void main() {
  group('People tags list screen leading', () {
    testWidgets('pops when stacked above another route', (tester) async {
      await _pumpRouterApp(
        tester,
        initial: [
          const PeopleTagsRoute(),
          PeopleTagRoute(tagId: 'Ta'),
        ],
      );

      expect(find.byType(PeopleTagScreen), findsOneWidget);
      await _tapAppBarBack(tester);
      expect(find.byType(PeopleTagsScreen), findsOneWidget);
      expect(find.byType(PeopleTagScreen), findsNothing);
    });

    testWidgets('falls back to the People tab when the stack cannot pop', (
      tester,
    ) async {
      final paths = <String>[];
      await _pumpRouterApp(
        tester,
        initial: const [PeopleTagsRoute()],
        onNavigatePath: paths.add,
      );

      expect(find.byType(PeopleTagsScreen), findsOneWidget);
      await _tapAppBarBack(tester);
      expect(paths, [kPathNetwork]);
    });

    testWidgets('375×667 RU shows the title without overflow', (tester) async {
      await usePhoneSurface(tester);
      await _pumpRouterApp(
        tester,
        initial: const [PeopleTagsRoute()],
        locale: const Locale('ru'),
      );

      expect(find.text('Теги людей'), findsWidgets);
      expect(
        find.descendant(
          of: find.byType(TenturaTopBar),
          matching: find.byIcon(Icons.arrow_back),
        ),
        findsOneWidget,
      );
    });
  });

  group('People tag screen leading', () {
    testWidgets('pops to the tags list when stacked', (tester) async {
      await _pumpRouterApp(
        tester,
        initial: [
          const PeopleTagsRoute(),
          PeopleTagRoute(tagId: 'Ta'),
        ],
      );

      expect(find.text('Neighbours'), findsWidgets);
      await _tapAppBarBack(tester);
      expect(find.byType(PeopleTagsScreen), findsOneWidget);
    });

    testWidgets('falls back to the tags list path when alone on the stack', (
      tester,
    ) async {
      final paths = <String>[];
      await _pumpRouterApp(
        tester,
        initial: [PeopleTagRoute(tagId: 'Ta')],
        onNavigatePath: paths.add,
      );

      await _tapAppBarBack(tester);
      expect(paths, [kPathPeopleTags]);
    });

    testWidgets('375×667 RU shows the tag title and back control', (
      tester,
    ) async {
      await usePhoneSurface(tester);
      await _pumpRouterApp(
        tester,
        initial: [PeopleTagRoute(tagId: 'Ta')],
        locale: const Locale('ru'),
      );

      expect(find.text('Neighbours'), findsWidgets);
      await _tapAppBarBack(tester);
    });
  });

  group('People automatic tag screen leading', () {
    testWidgets('pops to the tags list when stacked', (tester) async {
      await _pumpRouterApp(
        tester,
        initial: [
          const PeopleTagsRoute(),
          PeopleAutoTagRoute(kind: _autoKind),
        ],
      );

      expect(find.byType(PeopleAutoTagScreen), findsOneWidget);
      await _tapAppBarBack(tester);
      expect(find.byType(PeopleTagsScreen), findsOneWidget);
    });

    testWidgets('falls back to the tags list path when alone on the stack', (
      tester,
    ) async {
      final paths = <String>[];
      await _pumpRouterApp(
        tester,
        initial: [PeopleAutoTagRoute(kind: _autoKind)],
        onNavigatePath: paths.add,
      );

      await _tapAppBarBack(tester);
      expect(paths, [kPathPeopleTags]);
    });

    testWidgets('375×667 RU shows the automatic tag title and back control', (
      tester,
    ) async {
      await usePhoneSurface(tester);
      await _pumpRouterApp(
        tester,
        initial: [PeopleAutoTagRoute(kind: _autoKind)],
        locale: const Locale('ru'),
      );

      expect(find.text('Помогали мне'), findsWidgets);
      await _tapAppBarBack(tester);
    });
  });
}
