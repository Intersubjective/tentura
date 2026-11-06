import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/people_tags/domain/entity/people_tags_entities.dart';
import 'package:tentura/features/people_tags/domain/use_case/people_tags_case.dart';
import 'package:tentura/features/people_tags/ui/widget/person_tags_block.dart';
import 'package:tentura/features/profile/domain/port/profile_repository_port.dart';
import 'package:tentura/ui/l10n/l10n.dart';

import '../../support/fake_people_tags_repository.dart';
import '../../support/phone_surface.dart';

final _inheritedSparkle = find.byWidgetPredicate(
  (widget) =>
      widget is RichText && widget.text.toPlainText().contains('✦'),
);

const _carol = 'Ucarol00000001';
const _bob = 'Ubob0000000001';

const _workshop = PersonTag(
  id: 'Ta',
  name: 'Мастерская',
  glyph: 'М',
  color: 2,
  ord: 0,
);

const _bobProfile = Profile(
  id: _bob,
  displayName: 'Боб с длинным именем пригласившего',
);

final class _FakeProfileRepository implements ProfileRepositoryPort {
  @override
  Future<List<Profile>> fetchProfilesByIds(Iterable<String> ids) async => [
    if (ids.contains(_bob)) _bobProfile,
  ];

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

void main() {
  late PeopleTagsTestRig rig;

  setUp(() async {
    GetIt.I.registerSingleton<ProfileRepositoryPort>(_FakeProfileRepository());
    rig = await PeopleTagsTestRig.create(
      FakePeopleTagsRepository(
        tagList: [_workshop],
        memberList: const [
          PersonTagMembers(
            tagId: 'Ta',
            personIds: [_carol],
            inherited: [
              PersonTagInherited(personId: _carol, inviterId: _bob),
            ],
          ),
        ],
      ),
    );
    GetIt.I.registerSingleton<PeopleTagsCase>(rig.peopleTags);
  });

  tearDown(() async {
    await GetIt.I.reset();
    await rig.dispose();
  });

  testWidgets(
    'inherited own tag shows ✦, RU Keep and remove, and sends keep on Keep',
    (tester) async {
      await usePhoneSurface(tester);
      final handle = tester.ensureSemantics();
      final l10n = lookupL10n(const Locale('ru'));

      await tester.pumpWidget(
        MaterialApp(
          theme: TenturaTheme.light(),
          locale: const Locale('ru'),
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

      expect(_inheritedSparkle, findsOneWidget);
      expect(find.text(_workshop.name), findsOneWidget);
      expect(find.text(l10n.peopleTagsInheritedKeep), findsOneWidget);
      expect(tester.takeException(), isNull);

      final chipSemantics = l10n.peopleTagsInheritedChipSemantics(
        _bobProfile.shownName,
      );
      expect(find.bySemanticsLabel(chipSemantics), findsOneWidget);

      await tester.tap(find.text(l10n.peopleTagsInheritedKeep));
      await tester.pumpAndSettle();

      expect(rig.peopleTags.isInheritedMember('Ta', _carol), isFalse);
      expect(rig.repository.appliedOps.single.single.keep, isTrue);

      await tester.tap(
        find.descendant(
          of: find.byType(PersonTagChip),
          matching: find.byIcon(Icons.close),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(PersonTagChip), findsNothing);
      expect(rig.repository.appliedOps, hasLength(2));

      handle.dispose();
    },
  );
}
