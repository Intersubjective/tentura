import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:logging/logging.dart';

import 'package:tentura/app/router/root_router.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/env.dart';
import 'package:tentura/features/people_tags/domain/entity/people_tags_entities.dart';
import 'package:tentura/features/people_tags/domain/port/people_tags_repository_port.dart';
import 'package:tentura/features/people_tags/domain/use_case/people_tags_case.dart';
import 'package:tentura/features/profile/domain/port/profile_repository_port.dart';
import 'package:tentura/ui/l10n/l10n.dart';

import '../../support/test_realtime_sync.dart';

/// `PersonAutoTagKind.helpedMe`, shown as "Helped me".
const _kind = 3;

const _profiles = {
  'Uann': Profile(id: 'Uann', displayName: 'Ann Archer'),
  'Ucat': Profile(id: 'Ucat', displayName: 'Cat Cooper'),
  'Uold': Profile(id: 'Uold', displayName: 'Old Timer'),
};

Key _person(String id) => Key('people-tag-person-$id');

final class _FakeProfileRepository extends Fake
    implements ProfileRepositoryPort {
  @override
  Future<List<Profile>> fetchProfilesByIds(Set<String> ids) async => [
    for (final id in ids)
      if (_profiles[id] != null) _profiles[id]!,
  ];
}

final class _FakePeopleTagsRepository implements PeopleTagsRepositoryPort {
  /// The people of the automatic tag right now.
  List<String> autoMembers = ['Uann', 'Ucat'];

  final created = <({String name, int? fromAutoKind})>[];
  final _createdMembers = <String, List<String>>{};
  var _tags = <PersonTag>[
    const PersonTag(id: 'Told', name: 'Old tag', glyph: 'O', color: 0, ord: 1),
  ];

  @override
  Future<List<PersonTag>> personTags() async => _tags;

  @override
  Future<List<PersonTagMembers>> personTagMemberships() async => [
    const PersonTagMembers(tagId: 'Told', personIds: ['Uold']),
    for (final e in _createdMembers.entries)
      PersonTagMembers(tagId: e.key, personIds: e.value),
  ];

  @override
  Future<List<PersonAutoTag>> personAutoTags() async => [
    PersonAutoTag(
      kind: _kind,
      count: autoMembers.length,
      showInFilters: true,
    ),
  ];

  @override
  Future<List<String>> personAutoTagMembers(int kind) async =>
      kind == _kind ? autoMembers : const [];

  // The server snapshot: a tag made from an automatic tag holds its people.
  @override
  Future<PersonTag> personTagCreate({
    required String name,
    required String clientOpId,
    String? glyph,
    int? color,
    int? fromAutoKind,
  }) async {
    created.add((name: name, fromAutoKind: fromAutoKind));
    final tag = PersonTag(
      id: 'Tnew',
      name: name,
      glyph: glyph ?? name.characters.first,
      color: color ?? 1,
      ord: _tags.length + 1,
      count: autoMembers.length,
    );
    _tags = [..._tags, tag];
    // The server snapshots the automatic tag's people only when told which.
    _createdMembers[tag.id] = fromAutoKind == _kind ? [...autoMembers] : [];
    return tag;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

class _TestRouter extends RootStackRouter {
  @override
  List<AutoRoute> get routes => [
    AutoRoute(page: PeopleAutoTagRoute.page, path: '/people-tags/auto/:kind'),
    AutoRoute(page: PeopleTagRoute.page, path: '/people-tags/:tagId'),
  ];
}

void main() {
  late _FakePeopleTagsRepository repository;
  late TestRealtimeSyncPort realtimePort;
  late PeopleTagsCase peopleTags;

  setUp(() async {
    repository = _FakePeopleTagsRepository();
    final realtime = buildTestRealtimeSync();
    realtimePort = realtime.port;
    peopleTags = PeopleTagsCase(
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
  });

  tearDown(() async {
    await GetIt.I.reset();
    await peopleTags.dispose();
    await realtimePort.dispose();
  });

  Future<void> pumpAutoTagScreen(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(900, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final router = _TestRouter();
    addTearDown(router.dispose);
    await tester.pumpWidget(
      MaterialApp.router(
        locale: const Locale('en'),
        theme: TenturaTheme.light(),
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        builder: (context, child) =>
            TenturaResponsiveScope(child: child ?? const SizedBox.shrink()),
        routerConfig: router.config(
          deepLinkBuilder: (_) => DeepLink([PeopleAutoTagRoute(kind: _kind)]),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('automatic tag screen', () {
    testWidgets('shows the automatic tag name and the people in it', (
      tester,
    ) async {
      await pumpAutoTagScreen(tester);

      expect(find.text('Helped me'), findsWidgets);
      expect(find.byKey(_person('Uann')), findsOneWidget);
      expect(find.byKey(_person('Ucat')), findsOneWidget);
      expect(find.text('Ann Archer'), findsOneWidget);
      expect(find.text('Cat Cooper'), findsOneWidget);
      expect(find.byKey(_person('Uold')), findsNothing);
    });

    testWidgets('Make it my tag creates a tag from that automatic tag kind', (
      tester,
    ) async {
      await pumpAutoTagScreen(tester);

      await tester.tap(find.text('Make it my tag'));
      await tester.pumpAndSettle();

      expect(repository.created, hasLength(1));
      expect(repository.created.single.fromAutoKind, _kind);
      expect(repository.created.single.name, isNotEmpty);
      expect(peopleTags.tags.map((t) => t.id), contains('Tnew'));
    });

    testWidgets('Make it my tag opens the new tag with those people in it', (
      tester,
    ) async {
      await pumpAutoTagScreen(tester);

      await tester.tap(find.text('Make it my tag'));
      await tester.pumpAndSettle();

      // The tag screen of the new tag, not the automatic tag any more.
      expect(find.text('Make it my tag'), findsNothing);
      expect(find.byKey(const Key('people-tag-edit')), findsOneWidget);
      expect(find.byKey(_person('Uann')), findsOneWidget);
      expect(find.byKey(_person('Ucat')), findsOneWidget);
      expect(find.byKey(_person('Uold')), findsNothing);
      expect(
        tester.widget<Text>(find.byKey(const Key('people-tag-count'))).data,
        '2',
      );
    });
  });
}
