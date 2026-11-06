import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/domain/entity/repository_event.dart';
import 'package:tentura/features/people_tags/domain/entity/people_tags_entities.dart';
import 'package:tentura/features/people_tags/domain/use_case/people_tags_case.dart';
import 'package:tentura/features/people_tags/ui/screen/people_tag_screen.dart';
import 'package:tentura/features/people_tags/ui/widget/person_tags_block.dart';
import 'package:tentura/features/profile/domain/port/profile_repository_port.dart';
import 'package:tentura/ui/l10n/l10n.dart';

import '../../support/fake_people_tags_repository.dart';
import '../../support/mock_stack_router_scope.dart';
import '../../support/phone_surface.dart';

const _carol = 'Ucarol00000001';
const _bob = 'Ubob0000000001';

const _workshop = PersonTag(
  id: 'Ta',
  name: 'Мастерская',
  glyph: 'М',
  color: 2,
  ord: 0,
);

const _manual = PersonTag(
  id: 'Tb',
  name: 'Соседи',
  glyph: 'С',
  color: 0,
  ord: 1,
);

final _inheritedSparkle = find.byWidgetPredicate(
  (widget) => widget is RichText && widget.text.toPlainText().contains('✦'),
);

final class _FakeProfileRepository implements ProfileRepositoryPort {
  _FakeProfileRepository({this.locale = const Locale('ru')});

  final Locale locale;
  final _changes = StreamController<RepositoryEvent<Profile>>.broadcast();

  @override
  Stream<RepositoryEvent<Profile>> get changes => _changes.stream;

  @override
  Future<List<Profile>> fetchProfilesByIds(Set<String> ids) async {
    final bobName = locale.languageCode == 'ru' ? 'Боб' : 'Bob';
    return [
      if (ids.contains(_bob)) Profile(id: _bob, displayName: bobName),
      if (ids.contains(_carol))
        Profile(
          id: _carol,
          displayName: locale.languageCode == 'ru' ? 'Карол' : 'Carol',
        ),
    ];
  }

  @override
  Future<void> dispose() => _changes.close();

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

FakePeopleTagsRepository _inheritedRepository() => FakePeopleTagsRepository(
  tagList: [_workshop, _manual],
  memberList: const [
    PersonTagMembers(
      tagId: 'Ta',
      personIds: [_carol],
      inherited: [PersonTagInherited(personId: _carol, inviterId: _bob)],
    ),
    PersonTagMembers(
      tagId: 'Tb',
      personIds: [_carol],
      inherited: [],
    ),
  ],
);

void main() {
  late PeopleTagsTestRig rig;
  late _FakeProfileRepository profiles;

  Future<void> setUpInherited(Locale locale) async {
    profiles = _FakeProfileRepository(locale: locale);
    GetIt.I.registerSingleton<ProfileRepositoryPort>(profiles);
    rig = await PeopleTagsTestRig.create(_inheritedRepository());
    GetIt.I.registerSingleton<PeopleTagsCase>(rig.peopleTags);
  }

  tearDown(() async {
    await GetIt.I.reset();
    await rig.dispose();
  });

  Future<void> pumpBlock(
    WidgetTester tester, {
    Locale locale = const Locale('ru'),
  }) async {
    await usePhoneSurface(tester);
    await tester.pumpWidget(
      MaterialApp(
        theme: TenturaTheme.light(),
        locale: locale,
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        home: const TenturaResponsiveScope(
          child: Scaffold(
            body: SingleChildScrollView(
              child: PersonTagsBlock(personId: _carol),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('inherited own-tag marker (#1019)', () {
    testWidgets('person panel RU: ✦ and Carol semantics name Bob', (
      tester,
    ) async {
      await setUpInherited(const Locale('ru'));
      final handle = tester.ensureSemantics();
      final l10n = lookupL10n(const Locale('ru'));

      await pumpBlock(tester);

      expect(_inheritedSparkle, findsOneWidget);
      expect(
        find.bySemanticsLabel(
          l10n.peopleTagsInheritedChipSemantics('Боб'),
        ),
        findsOneWidget,
      );
      expect(find.textContaining('Set automatically'), findsNothing);

      handle.dispose();
    });

    testWidgets('Keep calls keepInherited and ✦ disappears', (tester) async {
      await setUpInherited(const Locale('ru'));
      final l10n = lookupL10n(const Locale('ru'));

      await pumpBlock(tester);
      await tester.tap(find.text(l10n.peopleTagsInheritedKeep));
      await tester.pumpAndSettle();

      expect(_inheritedSparkle, findsNothing);
      expect(rig.repository.appliedOps.single.single.keep, isTrue);
      expect(find.text(_workshop.name), findsOneWidget);
    });

    testWidgets('manual tag has no ✦', (tester) async {
      await setUpInherited(const Locale('ru'));
      await pumpBlock(tester);

      expect(_inheritedSparkle, findsOneWidget);
      final chips = tester.widgetList<PersonTagChip>(
        find.byType(PersonTagChip),
      );
      expect(chips.where((c) => c.showInheritedMarker), hasLength(1));
      expect(chips.where((c) => !c.showInheritedMarker), hasLength(1));
    });

    testWidgets('× removes and Undo restores inherited marker', (tester) async {
      await setUpInherited(const Locale('ru'));
      final l10n = lookupL10n(const Locale('ru'));

      await pumpBlock(tester);
      await tester.tap(
        find.descendant(
          of: find.widgetWithText(PersonTagChip, _workshop.name),
          matching: find.byIcon(Icons.close),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.widgetWithText(PersonTagChip, _workshop.name), findsNothing);

      await tester.tap(find.text(l10n.peopleTagsUndo));
      await tester.pumpAndSettle();

      expect(
        find.widgetWithText(PersonTagChip, _workshop.name),
        findsOneWidget,
      );
      expect(_inheritedSparkle, findsOneWidget);
      expect(rig.repository.appliedOps.last.single.add, isTrue);
    });

    testWidgets('tag screen people list shows ✦ for Carol', (tester) async {
      await setUpInherited(const Locale('ru'));
      await usePhoneSurface(tester);
      final overflow = FlutterError.onError;
      FlutterError.onError = (details) {
        if (details.exceptionAsString().contains('overflowed')) return;
        overflow?.call(details);
      };
      addTearDown(() => FlutterError.onError = overflow);

      await tester.pumpWidget(
        MaterialApp(
          theme: TenturaTheme.light(),
          locale: const Locale('ru'),
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          home: wrapWithMockStackRouter(
            const TenturaResponsiveScope(
              child: PeopleTagScreen(tagId: 'Ta'),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(_inheritedSparkle, findsOneWidget);
      expect(find.text('Карол'), findsOneWidget);
    });

    testWidgets('profile block EN: semantics invited by Bob', (tester) async {
      await setUpInherited(const Locale('en'));
      final handle = tester.ensureSemantics();
      final l10n = lookupL10n(const Locale('en'));

      await pumpBlock(tester, locale: const Locale('en'));

      expect(
        find.bySemanticsLabel(
          l10n.peopleTagsInheritedChipSemantics('Bob'),
        ),
        findsOneWidget,
      );

      handle.dispose();
    });
  });
}
