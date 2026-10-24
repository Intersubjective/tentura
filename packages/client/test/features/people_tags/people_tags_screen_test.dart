import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:logging/logging.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/env.dart';
import 'package:tentura/features/people_tags/domain/entity/people_tags_entities.dart';
import 'package:tentura/features/people_tags/domain/port/people_tags_repository_port.dart';
import 'package:tentura/features/people_tags/domain/use_case/people_tags_case.dart';
import 'package:tentura/features/people_tags/ui/screen/people_tags_screen.dart';
import 'package:tentura/ui/l10n/l10n.dart';

import '../../support/test_realtime_sync.dart';

const _tagA = PersonTag(
  id: 'Ta',
  name: 'Neighbours',
  glyph: 'N',
  color: 0,
  ord: 1,
  count: 3,
  countOffField: 1,
);
const _tagB = PersonTag(
  id: 'Tb',
  name: 'Climbers',
  glyph: 'C',
  color: 1,
  ord: 2,
  count: 2,
);
const _tagC = PersonTag(
  id: 'Tc',
  name: 'Cooks',
  glyph: 'K',
  color: 2,
  ord: 3,
  count: 5,
);

const _autoKind = 1;

Key _rowMenu(String tagId) => Key('people-tags-row-menu-$tagId');
Key _moveUp(String tagId) => Key('people-tags-move-up-$tagId');
Key _moveDown(String tagId) => Key('people-tags-move-down-$tagId');
Key _delete(String tagId) => Key('people-tags-delete-$tagId');
Key _autoSwitch(int kind) => Key('people-tags-auto-switch-$kind');

final class _FakePeopleTagsRepository implements PeopleTagsRepositoryPort {
  List<PersonTag> tagList = [_tagA, _tagB, _tagC];
  List<PersonAutoTag> autoList = const [
    PersonAutoTag(kind: _autoKind, count: 4, showInFilters: false),
  ];

  final updates = <({String id, int? ord})>[];
  final deletedIds = <String>[];
  final restoredTagIds = <String>[];
  final prefCalls = <({int kind, bool showInFilters})>[];

  @override
  Future<List<PersonTag>> personTags() async => tagList;

  @override
  Future<List<PersonTagMembers>> personTagMemberships() async => const [];

  @override
  Future<List<PersonAutoTag>> personAutoTags() async => autoList;

  @override
  Future<PersonTagSuggestionState> personTagSuggestionState() async =>
      const PersonTagSuggestionState(canSuggest: true, disabled: false);

  @override
  Future<PersonTag> personTagUpdate({
    required String id,
    required String clientOpId,
    String? name,
    String? glyph,
    int? color,
    int? ord,
  }) async {
    updates.add((id: id, ord: ord));
    final tag = tagList.firstWhere((t) => t.id == id);
    if (ord != null) {
      // Server semantics: the tag takes position `ord`, the rest close up.
      final others = [
        for (final t in tagList)
          if (t.id != id) t,
      ]..insert(ord.clamp(1, tagList.length) - 1, tag);
      tagList = [
        for (var i = 0; i < others.length; i++) others[i].copyWith(ord: i + 1),
      ];
    }
    return tagList.firstWhere((t) => t.id == id);
  }

  @override
  Future<PersonTagSnapshot> personTagDelete({
    required String id,
    required String clientOpId,
  }) async {
    deletedIds.add(id);
    final tag = tagList.firstWhere((t) => t.id == id);
    tagList = [
      for (final t in tagList)
        if (t.id != id) t,
    ];
    return PersonTagSnapshot(tag: tag, memberIds: const ['Uann'], sources: const [0]);
  }

  @override
  Future<PersonTag> personTagRestore({
    required PersonTagSnapshot snapshot,
    required String clientOpId,
  }) async {
    restoredTagIds.add(snapshot.tag.id);
    tagList = [...tagList, snapshot.tag]..sort((a, b) => a.ord.compareTo(b.ord));
    return snapshot.tag;
  }

  @override
  Future<PersonAutoTag> personAutoTagPrefSet({
    required int kind,
    required bool showInFilters,
  }) async {
    prefCalls.add((kind: kind, showInFilters: showInFilters));
    return PersonAutoTag(kind: kind, count: 4, showInFilters: showInFilters);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
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
      ..registerSingleton<PeopleTagsCase>(peopleTags);
  });

  tearDown(() async {
    await GetIt.I.reset();
    await peopleTags.dispose();
    await realtimePort.dispose();
  });

  Future<void> pumpScreen(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(900, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        theme: TenturaTheme.light(),
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        home: TenturaResponsiveScope(child: const PeopleTagsScreen()),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> pickRowAction(
    WidgetTester tester,
    String tagId,
    Key action,
  ) async {
    await tester.tap(find.byKey(_rowMenu(tagId)));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(action));
    await tester.pumpAndSettle();
  }

  List<String> tagNamesInOrder(WidgetTester tester) {
    const names = ['Neighbours', 'Climbers', 'Cooks'];
    final shown = [
      for (final n in names)
        if (find.text(n).evaluate().isNotEmpty) n,
    ];
    shown.sort(
      (a, b) => tester
          .getTopLeft(find.text(a))
          .dy
          .compareTo(tester.getTopLeft(find.text(b)).dy),
    );
    return shown;
  }

  group('people tags screen', () {
    testWidgets('lists own tags in order with their counts', (tester) async {
      await pumpScreen(tester);

      expect(tagNamesInOrder(tester), ['Neighbours', 'Climbers', 'Cooks']);
      expect(find.text('3'), findsWidgets);
      expect(find.textContaining('1 off the field'), findsOneWidget);
    });

    testWidgets('moving a tag up by menu sends one update with its new ord', (
      tester,
    ) async {
      await pumpScreen(tester);

      await pickRowAction(tester, 'Tb', _moveUp('Tb'));

      expect(repository.updates, hasLength(1));
      expect(repository.updates.single.id, 'Tb');
      expect(repository.updates.single.ord, 1);
      expect(tagNamesInOrder(tester), ['Climbers', 'Neighbours', 'Cooks']);
    });

    testWidgets('moving a tag down by menu sends one update with its new ord', (
      tester,
    ) async {
      await pumpScreen(tester);

      await pickRowAction(tester, 'Tb', _moveDown('Tb'));

      expect(repository.updates, hasLength(1));
      expect(repository.updates.single.id, 'Tb');
      expect(repository.updates.single.ord, 3);
      expect(tagNamesInOrder(tester), ['Neighbours', 'Cooks', 'Climbers']);
    });

    testWidgets('the first tag cannot move up and the last cannot move down', (
      tester,
    ) async {
      await pumpScreen(tester);

      await tester.tap(find.byKey(_rowMenu('Ta')));
      await tester.pumpAndSettle();
      expect(find.byKey(_moveUp('Ta')), findsNothing);
      expect(find.byKey(_moveDown('Ta')), findsOneWidget);
      await tester.tapAt(const Offset(1, 1));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(_rowMenu('Tc')));
      await tester.pumpAndSettle();
      expect(find.byKey(_moveDown('Tc')), findsNothing);
      expect(find.byKey(_moveUp('Tc')), findsOneWidget);
    });

    testWidgets('deleting a tag shows Undo, and Undo restores the same id', (
      tester,
    ) async {
      await pumpScreen(tester);

      await pickRowAction(tester, 'Tb', _delete('Tb'));

      expect(repository.deletedIds, ['Tb']);
      expect(find.text('Climbers'), findsNothing);
      final undo = find.byType(SnackBarAction);
      expect(undo, findsOneWidget);

      await tester.tap(undo);
      await tester.pumpAndSettle();

      expect(repository.restoredTagIds, ['Tb']);
      expect(find.text('Climbers'), findsOneWidget);
      expect(tagNamesInOrder(tester), ['Neighbours', 'Climbers', 'Cooks']);
    });

    testWidgets('lists automatic tags with a Show in filters switch', (
      tester,
    ) async {
      await pumpScreen(tester);

      final tile = tester.widget<Switch>(find.byKey(_autoSwitch(_autoKind)));
      expect(tile.value, isFalse);
    });

    testWidgets('toggling Show in filters calls the pref setter', (
      tester,
    ) async {
      await pumpScreen(tester);

      await tester.tap(find.byKey(_autoSwitch(_autoKind)));
      await tester.pumpAndSettle();

      expect(repository.prefCalls, [(kind: _autoKind, showInFilters: true)]);
    });

    testWidgets('shows no untagged counter, only the counts of listed tags', (
      tester,
    ) async {
      await pumpScreen(tester);

      final untaggedWording = RegExp(
        r'untagged|not tagged|no tags?\b|without (a )?tags?|unsorted',
        caseSensitive: false,
      );
      expect(find.textContaining(untaggedWording), findsNothing);

      // Every bare number on the screen is the count of a listed tag.
      final listed = {'3', '2', '5', '4'};
      final numbers = [
        for (final t in tester.widgetList<Text>(find.byType(Text)))
          if (RegExp(r'^\d+$').hasMatch(t.data ?? '')) t.data!,
      ];
      expect(numbers, isNotEmpty);
      expect(numbers.toSet().difference(listed), isEmpty);
    });
  });
}
