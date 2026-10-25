import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:logging/logging.dart';
import 'package:rxdart/rxdart.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/env.dart';
import 'package:tentura/features/constellation/domain/entity/constellation_anchor_projection.dart';
import 'package:tentura/features/constellation/domain/entity/constellation_field.dart';
import 'package:tentura/features/constellation/domain/port/constellation_account_port.dart';
import 'package:tentura/features/constellation/domain/port/constellation_repository_port.dart';
import 'package:tentura/features/constellation/domain/use_case/constellation_field_store_case.dart';
import 'package:tentura/features/people_tags/domain/entity/people_tags_entities.dart';
import 'package:tentura/features/people_tags/domain/port/people_tags_repository_port.dart';
import 'package:tentura/features/people_tags/domain/use_case/people_tags_case.dart';
import 'package:tentura/features/people_tags/ui/screen/people_tag_screen.dart';
import 'package:tentura/features/profile/domain/port/profile_repository_port.dart';
import 'package:tentura/ui/l10n/l10n.dart';

import '../../support/fake_clock_port.dart';
import '../../support/fake_wake_up_port.dart';
import '../../support/test_realtime_sync.dart';

const _tag = PersonTag(
  id: 'Ta',
  name: 'Neighbours',
  glyph: 'N',
  color: 0,
  ord: 1,
  count: 3,
);

const _profiles = {
  'Uann': Profile(id: 'Uann', displayName: 'Ann Archer'),
  'Ubob': Profile(id: 'Ubob', displayName: 'Bob Baker'),
  'Ucat': Profile(id: 'Ucat', displayName: 'Cat Cooper'),
  'Udan': Profile(id: 'Udan', displayName: 'Dan Dorsey'),
  'Ueve': Profile(id: 'Ueve', displayName: 'Eve Ellis'),
};

/// Everyone on the viewer's Field: the people the Add people picker offers.
final _fieldPeople = [
  for (final p in _profiles.values)
    ConstellationPerson(id: p.id, displayName: p.displayName),
];

const _count = Key('people-tag-count');
const _editButton = Key('people-tag-edit');
const _addPeopleButton = Key('people-tag-add-people');
const _searchField = Key('add-people-search');
const _nameField = Key('tag-editor-name');
const _saveButton = Key('tag-editor-save');

Key _person(String id) => Key('people-tag-person-$id');
Key _removePerson(String id) => Key('people-tag-person-remove-$id');

final class _FieldRepository implements ConstellationRepositoryPort {
  @override
  Future<ConstellationField> fetch({
    ConstellationFieldMembershipFilters membershipFilters =
        ConstellationFieldMembershipFilters.defaults,
    ConstellationProjection projection = ConstellationProjection.full,
  }) async => ConstellationField(
    loadedAt: DateTime.utc(2026, 10, 25),
    context: '',
    peers: _fieldPeople,
  );
}

final class _Account implements ConstellationAccountPort {
  _Account(this.currentAccountChanges);

  @override
  final Stream<String> currentAccountChanges;
}

final class _FakeProfileRepository extends Fake
    implements ProfileRepositoryPort {
  @override
  Future<List<Profile>> fetchProfilesByIds(Set<String> ids) async => [
    for (final id in ids)
      if (_profiles[id] != null) _profiles[id]!,
  ];
}

final class _FakePeopleTagsRepository implements PeopleTagsRepositoryPort {
  List<PersonTag> tagList = [_tag];
  List<PersonTagMembers> memberList = [
    const PersonTagMembers(tagId: 'Ta', personIds: ['Uann', 'Ubob', 'Ucat']),
  ];

  final appliedOps = <List<PersonTagMemberOp>>[];
  final updates = <({String id, String? name, String? glyph, int? color})>[];

  @override
  Future<List<PersonTag>> personTags() async => tagList;

  @override
  Future<List<PersonTagMembers>> personTagMemberships() async => memberList;

  @override
  Future<List<PersonAutoTag>> personAutoTags() async => const [];

  @override
  Future<void> personTagMembersApply({
    required List<PersonTagMemberOp> ops,
    required String clientOpId,
  }) async {
    appliedOps.add(ops);
  }

  @override
  Future<PersonTag> personTagUpdate({
    required String id,
    required String clientOpId,
    String? name,
    String? glyph,
    int? color,
    int? ord,
  }) async {
    updates.add((id: id, name: name, glyph: glyph, color: color));
    final updated = tagList
        .firstWhere((t) => t.id == id)
        .copyWith(
          name: name ?? _tag.name,
          glyph: glyph ?? _tag.glyph,
          color: color ?? _tag.color,
        );
    tagList = [
      for (final t in tagList)
        if (t.id == id) updated else t,
    ];
    return updated;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

void main() {
  late _FakePeopleTagsRepository repository;
  late TestRealtimeSyncPort realtimePort;
  late PeopleTagsCase peopleTags;
  late BehaviorSubject<String> account;
  late ConstellationFieldStoreCase fieldStore;

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
    account = BehaviorSubject<String>.seeded('account-a');
    fieldStore = ConstellationFieldStoreCase(
      _FieldRepository(),
      _Account(account.stream),
      FakeClockPort(DateTime.utc(2026, 10, 25)),
      FakeWakeUpPort(),
      realtime.case_,
      env: const Env(),
      logger: Logger('field'),
    );
    fieldStore.lease();
    unawaited(fieldStore.requestRefresh(ConstellationRefreshReason.load));
    for (var i = 0; i < 20; i++) {
      await Future<void>.delayed(Duration.zero);
    }
    GetIt.I
      ..registerSingleton<ConstellationFieldStoreCase>(fieldStore)
      ..registerSingleton<PeopleTagsRepositoryPort>(repository)
      ..registerSingleton<PeopleTagsCase>(peopleTags)
      ..registerSingleton<ProfileRepositoryPort>(_FakeProfileRepository());
  });

  tearDown(() async {
    await GetIt.I.reset();
    await peopleTags.dispose();
    await fieldStore.dispose();
    await account.close();
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
        home: const TenturaResponsiveScope(
          child: PeopleTagScreen(tagId: 'Ta'),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  String countShown(WidgetTester tester) =>
      tester.widget<Text>(find.byKey(_count)).data!;

  group('people tag screen', () {
    testWidgets('shows the tag name, its people and how many they are', (
      tester,
    ) async {
      await pumpScreen(tester);

      expect(find.text('Neighbours'), findsWidgets);
      for (final id in const ['Uann', 'Ubob', 'Ucat']) {
        expect(find.byKey(_person(id)), findsOneWidget);
      }
      // People on the Field who are not in the tag are not listed.
      for (final id in const ['Udan', 'Ueve']) {
        expect(find.byKey(_person(id)), findsNothing);
      }
      expect(find.text('Ann Archer'), findsOneWidget);
      expect(find.text('Cat Cooper'), findsOneWidget);
      expect(countShown(tester), '3');
    });

    testWidgets('removing a person sends one remove op and lowers the count', (
      tester,
    ) async {
      await pumpScreen(tester);

      await tester.tap(find.byKey(_removePerson('Ubob')));
      await tester.pumpAndSettle();

      expect(repository.appliedOps, hasLength(1));
      expect(
        repository.appliedOps.single.map((o) => (o.tagId, o.personId, o.add)),
        [('Ta', 'Ubob', false)],
      );
      expect(find.byKey(_person('Ubob')), findsNothing);
      expect(find.byKey(_person('Uann')), findsOneWidget);
      expect(countShown(tester), '2');
    });

    testWidgets('the editor opens filled with the current name', (
      tester,
    ) async {
      await pumpScreen(tester);

      await tester.tap(find.byKey(_editButton));
      await tester.pumpAndSettle();

      final name = tester.widget<TextField>(find.byKey(_nameField));
      expect(name.controller!.text, 'Neighbours');
    });

    testWidgets('renaming and recolouring saves one update and shows it', (
      tester,
    ) async {
      await pumpScreen(tester);

      await tester.tap(find.byKey(_editButton));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(_nameField), 'Locals');
      await tester.pump();
      await tester.tap(find.bySemanticsLabel('Blue'));
      await tester.pump();
      await tester.tap(find.byKey(_saveButton));
      await tester.pumpAndSettle();

      expect(repository.updates, hasLength(1));
      expect(repository.updates.single.id, 'Ta');
      expect(repository.updates.single.name, 'Locals');
      expect(repository.updates.single.color, 5);
      expect(find.byKey(_nameField), findsNothing);
      expect(find.text('Locals'), findsWidgets);
      expect(find.text('Neighbours'), findsNothing);
      expect(peopleTags.tags.single.color, 5);
    });
  });

  group('people tag screen Add people', () {
    Future<void> openPicker(WidgetTester tester) async {
      await pumpScreen(tester);
      await tester.tap(find.byKey(_addPeopleButton));
      await tester.pumpAndSettle();
    }

    Future<void> closePicker(WidgetTester tester) async {
      await tester.tapAt(const Offset(5, 5));
      await tester.pumpAndSettle();
    }

    testWidgets(
      'offers the people on the Field, ticked where already in the tag',
      (
        tester,
      ) async {
        await openPicker(tester);

        expect(
          find.widgetWithText(CheckboxListTile, 'Dan Dorsey'),
          findsOneWidget,
        );
        expect(
          tester
              .widget<CheckboxListTile>(
                find.widgetWithText(CheckboxListTile, 'Ann Archer'),
              )
              .value,
          isTrue,
        );
        expect(
          tester
              .widget<CheckboxListTile>(
                find.widgetWithText(CheckboxListTile, 'Dan Dorsey'),
              )
              .value,
          isFalse,
        );
      },
    );

    testWidgets(
      'adds everyone picked in one batch and shows them with the new count',
      (
        tester,
      ) async {
        await openPicker(tester);

        await tester.tap(find.widgetWithText(CheckboxListTile, 'Dan Dorsey'));
        await tester.pump();
        await tester.tap(find.widgetWithText(CheckboxListTile, 'Eve Ellis'));
        await tester.pump();
        expect(repository.appliedOps, isEmpty);
        await closePicker(tester);

        expect(repository.appliedOps, hasLength(1));
        expect(
          repository.appliedOps.single.map((o) => (o.tagId, o.personId, o.add)),
          unorderedEquals([
            ('Ta', 'Udan', true),
            ('Ta', 'Ueve', true),
          ]),
        );
        expect(find.byKey(_person('Udan')), findsOneWidget);
        expect(find.byKey(_person('Ueve')), findsOneWidget);
        expect(countShown(tester), '5');
      },
    );

    testWidgets('sends nothing when nobody new was picked', (tester) async {
      await openPicker(tester);

      await tester.tap(find.widgetWithText(CheckboxListTile, 'Dan Dorsey'));
      await tester.pump();
      await tester.tap(find.widgetWithText(CheckboxListTile, 'Dan Dorsey'));
      await tester.pump();
      await closePicker(tester);

      expect(repository.appliedOps, isEmpty);
      expect(countShown(tester), '3');
    });

    testWidgets('searching by name narrows the list and keeps earlier picks', (
      tester,
    ) async {
      await openPicker(tester);

      await tester.tap(find.widgetWithText(CheckboxListTile, 'Eve Ellis'));
      await tester.pump();
      await tester.enterText(find.byKey(_searchField), 'dorsey');
      await tester.pumpAndSettle();

      expect(
        find.widgetWithText(CheckboxListTile, 'Dan Dorsey'),
        findsOneWidget,
      );
      expect(find.widgetWithText(CheckboxListTile, 'Eve Ellis'), findsNothing);
      expect(find.widgetWithText(CheckboxListTile, 'Cat Cooper'), findsNothing);

      await tester.tap(find.widgetWithText(CheckboxListTile, 'Dan Dorsey'));
      await tester.pump();
      await closePicker(tester);

      expect(repository.appliedOps, hasLength(1));
      expect(
        repository.appliedOps.single.map((o) => (o.tagId, o.personId, o.add)),
        unorderedEquals([
          ('Ta', 'Udan', true),
          ('Ta', 'Ueve', true),
        ]),
      );
    });
  });
}
