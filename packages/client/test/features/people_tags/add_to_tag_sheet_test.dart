import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:logging/logging.dart';

import 'package:tentura/design_system/tentura_theme.dart';
import 'package:tentura/env.dart';
import 'package:tentura/features/people_tags/domain/entity/people_tags_entities.dart';
import 'package:tentura/features/people_tags/domain/people_tags_exception.dart';
import 'package:tentura/features/people_tags/domain/port/people_tags_repository_port.dart';
import 'package:tentura/features/people_tags/domain/use_case/people_tags_case.dart';
import 'package:tentura/features/people_tags/ui/widget/add_to_tag_sheet.dart';
import 'package:tentura/ui/l10n/l10n.dart';

import '../../support/test_realtime_sync.dart';

const _person = 'Uzed';

const _tagA = PersonTag(
  id: 'Ta',
  name: 'Neighbours',
  glyph: 'N',
  color: 0,
  ord: 0,
);
const _tagB = PersonTag(
  id: 'Tb',
  name: 'Climbers',
  glyph: 'C',
  color: 1,
  ord: 1,
);
const _tagC = PersonTag(
  id: 'Tc',
  name: 'Cooks',
  glyph: 'K',
  color: 2,
  ord: 2,
);

/// The sheet's editor controls (the editor is a dialog opened from the sheet).
const _nameField = ValueKey('tag-editor-name');
const _saveButton = ValueKey('tag-editor-save');

final class _FakePeopleTagsRepository implements PeopleTagsRepositoryPort {
  List<PersonTag> tagList = [_tagA, _tagB, _tagC];
  List<PersonTagMembers> memberList = [
    const PersonTagMembers(tagId: 'Tb', personIds: ['Uann']),
  ];

  final appliedOps = <List<PersonTagMemberOp>>[];
  final createdNames = <String>[];

  /// Called for every create; throw to simulate a refusal.
  FutureOr<void> Function(String name)? onCreate;

  @override
  Future<List<PersonTag>> personTags() async => tagList;

  @override
  Future<List<PersonTagMembers>> personTagMemberships() async => memberList;

  @override
  Future<PersonTag> personTagCreate({
    required String name,
    required String clientOpId,
    String? glyph,
    int? color,
    int? fromAutoKind,
    String? fromBeaconId,
  }) async {
    await onCreate?.call(name);
    createdNames.add(name);
    return PersonTag(
      id: 'Tnew',
      name: name,
      glyph: glyph ?? name.substring(0, 1),
      color: color ?? 0,
      ord: tagList.length,
    );
  }

  @override
  Future<void> personTagMembersApply({
    required List<PersonTagMemberOp> ops,
    required String clientOpId,
  }) async {
    appliedOps.add(ops);
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
    GetIt.I.registerSingleton<PeopleTagsCase>(peopleTags);
  });

  tearDown(() async {
    await GetIt.I.reset();
    await peopleTags.dispose();
    await realtimePort.dispose();
  });

  group('add-to-tag sheet', () {
    testWidgets(
      'lists own tags in order, checked where the person is in them',
      (
        tester,
      ) async {
        repository.memberList = [
          const PersonTagMembers(tagId: 'Tb', personIds: [_person]),
        ];
        await peopleTags.load();
        await _openSheet(tester);

        expect(_tagRowsInOrder(tester), ['Neighbours', 'Climbers', 'Cooks']);
        expect(_checked(tester), [false, true, false]);
      },
    );

    for (final way in _CloseWay.values) {
      testWidgets(
        'toggling two tags then closing by ${way.name} sends one batch of two ops',
        (
          tester,
        ) async {
          await _openSheet(tester);

          await tester.tap(find.text('Neighbours'));
          await tester.pump();
          await tester.tap(find.text('Cooks'));
          await tester.pump();
          // Nothing is sent while the sheet is open.
          expect(repository.appliedOps, isEmpty);

          await _closeSheet(tester, way);

          expect(repository.appliedOps, hasLength(1));
          expect(
            repository.appliedOps.single.map(
              (o) => (o.tagId, o.personId, o.add),
            ),
            unorderedEquals([
              ('Ta', _person, true),
              ('Tc', _person, true),
            ]),
          );
        },
      );
    }

    testWidgets('unchecking a tag the person is in sends a remove op', (
      tester,
    ) async {
      repository.memberList = [
        const PersonTagMembers(tagId: 'Tb', personIds: [_person]),
      ];
      await peopleTags.load();
      await _openSheet(tester);

      await tester.tap(find.text('Climbers'));
      await tester.pump();
      await tester.tap(find.text('Neighbours'));
      await tester.pump();
      await _closeSheet(tester);

      expect(repository.appliedOps, hasLength(1));
      expect(
        repository.appliedOps.single.map((o) => (o.tagId, o.personId, o.add)),
        unorderedEquals([
          ('Tb', _person, false),
          ('Ta', _person, true),
        ]),
      );
    });

    testWidgets('toggling a tag back to where it started sends nothing', (
      tester,
    ) async {
      await _openSheet(tester);

      await tester.tap(find.text('Neighbours'));
      await tester.pump();
      await tester.tap(find.text('Neighbours'));
      await tester.pump();
      await _closeSheet(tester);

      expect(repository.appliedOps, isEmpty);
    });

    testWidgets('tells the person that only they see their tags', (
      tester,
    ) async {
      await _openSheet(tester);

      expect(find.textContaining('Only you see'), findsOneWidget);
    });
  });

  group('creating a tag from the add-to-tag sheet', () {
    testWidgets('creates the tag and shows it already checked', (
      tester,
    ) async {
      await _openSheet(tester);

      await _createTag(tester, 'Hikers');

      expect(repository.createdNames, ['Hikers']);
      // The editor is gone and the new tag sits last, checked.
      expect(find.byKey(_nameField), findsNothing);
      expect(_tagRowsInOrder(tester), [
        'Neighbours',
        'Climbers',
        'Cooks',
        'Hikers',
      ]);
      expect(_checked(tester), [false, false, false, true]);
    });

    for (final way in _CloseWay.values) {
      testWidgets('closing by ${way.name} adds the person to the new tag', (
        tester,
      ) async {
        await _openSheet(tester);

        await _createTag(tester, 'Hikers');
        await _closeSheet(tester, way);

        expect(repository.appliedOps, hasLength(1));
        expect(
          repository.appliedOps.single.map((o) => (o.tagId, o.personId, o.add)),
          [('Tnew', _person, true)],
        );
      });
    }

    testWidgets('keeps the choices made before the new tag was created', (
      tester,
    ) async {
      await _openSheet(tester);

      await tester.tap(find.text('Neighbours'));
      await tester.pump();
      await _createTag(tester, 'Hikers');
      await _closeSheet(tester);

      expect(repository.appliedOps, hasLength(1));
      expect(
        repository.appliedOps.single.map((o) => (o.tagId, o.personId, o.add)),
        unorderedEquals([
          ('Ta', _person, true),
          ('Tnew', _person, true),
        ]),
      );
    });

    testWidgets('a taken name is shown inline and the editor stays open', (
      tester,
    ) async {
      repository.onCreate = (_) => throw const PeopleTagsNameTakenException();
      await _openSheet(tester);

      await _createTag(tester, 'Cooks');

      expect(
        find.descendant(
          of: find.byKey(_nameField),
          matching: find.text('You already have this tag'),
        ),
        findsOneWidget,
      );
      expect(find.byKey(_saveButton), findsOneWidget);
      expect(find.byType(SnackBar), findsNothing);
      expect(_tagRowsInOrder(tester), ['Neighbours', 'Climbers', 'Cooks']);
    });

    testWidgets('after a taken name another name can still be saved', (
      tester,
    ) async {
      repository.onCreate = (name) {
        if (name == 'Cooks') throw const PeopleTagsNameTakenException();
      };
      await _openSheet(tester);

      await _createTag(tester, 'Cooks');
      await tester.enterText(find.byKey(_nameField), 'Chefs');
      await tester.pump();
      await tester.tap(find.byKey(_saveButton));
      await tester.pumpAndSettle();

      expect(repository.createdNames, ['Chefs']);
      expect(find.byKey(_nameField), findsNothing);
      expect(_checked(tester), [false, false, false, true]);
    });
  });
}

Future<void> _openSheet(WidgetTester tester) async {
  tester.view
    ..physicalSize = const Size(390, 844)
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: TenturaTheme.light(),
      localizationsDelegates: L10n.localizationsDelegates,
      supportedLocales: L10n.supportedLocales,
      locale: const Locale('en'),
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () => showAddToTagSheet(context, personId: _person),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open'));
  await tester.pumpAndSettle();
}

/// Ways a person can close the sheet without choosing anything else.
enum _CloseWay {
  /// Tap on the dimmed area outside the sheet.
  barrierTap,

  /// The system back gesture / button.
  systemBack,
}

/// Closes the sheet [way], then lets the batch that the sheet sends on close
/// finish.
Future<void> _closeSheet(
  WidgetTester tester, [
  _CloseWay way = _CloseWay.barrierTap,
]) async {
  switch (way) {
    case _CloseWay.barrierTap:
      await tester.tapAt(const Offset(5, 5));
    case _CloseWay.systemBack:
      await tester.binding.handlePopRoute();
  }
  await tester.pumpAndSettle();
  expect(find.text('Open'), findsOneWidget);
  expect(find.text('Neighbours'), findsNothing);
}

/// "+ Tag" → type [name] → save.
Future<void> _createTag(WidgetTester tester, String name) async {
  await tester.tap(find.text('+ Tag'));
  await tester.pumpAndSettle();
  await tester.enterText(find.byKey(_nameField), name);
  await tester.pump();
  await tester.tap(find.byKey(_saveButton));
  await tester.pumpAndSettle();
}

/// Tag names in the sheet, top to bottom, one per checkbox row.
List<String> _tagRowsInOrder(WidgetTester tester) {
  final names = ['Neighbours', 'Climbers', 'Cooks', 'Hikers', 'Chefs'];
  final found = <(double, String)>[
    for (final n in names)
      if (find.text(n).evaluate().isNotEmpty)
        (tester.getTopLeft(find.text(n).first).dy, n),
  ]..sort((a, b) => a.$1.compareTo(b.$1));
  return [for (final f in found) f.$2];
}

/// The checkbox values of the sheet, top to bottom.
List<bool?> _checked(WidgetTester tester) {
  final boxes = find.byType(Checkbox).evaluate().toList()
    ..sort((a, b) {
      final ay = tester.getTopLeft(find.byWidget(a.widget)).dy;
      final by = tester.getTopLeft(find.byWidget(b.widget)).dy;
      return ay.compareTo(by);
    });
  return [for (final e in boxes) (e.widget as Checkbox).value];
}
