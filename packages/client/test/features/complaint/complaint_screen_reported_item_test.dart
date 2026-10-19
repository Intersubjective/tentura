// SPDX-License-Identifier: AGPL-3.0-only
// Issue #488: the complaint form shows what is being reported, starts with no
// category chosen, and says in one line what the email is for. The reported
// item is fetched by id (owner review on PR #610), never read from the link.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tentura_root/domain/enums.dart';

import 'package:tentura/app/router/root_router.dart';
import 'package:tentura/consts.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/complaint/ui/bloc/complaint_cubit.dart';
import 'package:tentura/features/complaint/ui/screen/complaint_screen.dart';
import 'package:tentura/ui/l10n/l10n.dart';

import '../../ui/effect/fake_ui_effect_port.dart';
import 'recording_complaint_case.dart';

const _title = 'Fix my bike before Sunday';
const _author = 'Alice Moreau';

final _at = DateTime.utc(2026, 10, 19);

final _beacon = Beacon(
  id: 'B1',
  title: _title,
  createdAt: _at,
  updatedAt: _at,
  author: const Profile(id: 'Ualice', displayName: _author),
);

void main() {
  late RecordingComplaintCase complaintCase;

  Future<L10n> pumpComplaint(
    WidgetTester tester, {
    String id = 'B1',
    Beacon? beacon,
    Profile? profile,
    bool fetchFails = false,
    ComplaintType? fixedType,
    Locale locale = const Locale('en'),
  }) async {
    tester.view.physicalSize = const Size(1280, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    complaintCase = fetchFails
        ? RecordingComplaintCase()
        : RecordingComplaintCase(
            beacon: beacon ?? (profile == null ? _beacon : null),
            profile: profile,
          );
    final cubit = ComplaintCubit(
      id: id,
      fixedType: fixedType,
      complaintCase: complaintCase.useCase,
      effects: FakeUiEffectPort(),
    );
    addTearDown(cubit.close);
    final router = RootStackRouter.build(routes: []);
    addTearDown(router.dispose);
    await tester.pumpWidget(
      MaterialApp(
        locale: locale,
        theme: TenturaTheme.light(),
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        home: TenturaResponsiveScope(
          child: BlocProvider<ComplaintCubit>.value(
            value: cubit,
            child: RouterScope(
              controller: router,
              stateHash: 0,
              inheritableObserversBuilder: () => const [],
              child: StackRouterScope(
                controller: router,
                stateHash: 0,
                child: ComplaintScreen(id: id),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return lookupL10n(locale);
  }

  Finder typeDropdown() => find.byType(DropdownButton<ComplaintType>);

  Finder detailsField(L10n l10n) => find.widgetWithText(
    TextFormField,
    l10n.detailsRequired(kComplaintDetailsMinLength),
  );

  testWidgets('no category is preselected; the placeholder asks', (
    tester,
  ) async {
    final l10n = await pumpComplaint(tester);

    expect(typeDropdown(), findsOneWidget);
    expect(
      tester.widget<DropdownButton<ComplaintType>>(typeDropdown()).value,
      isNull,
    );
    expect(find.text(l10n.complaintTypeHint), findsOneWidget);
  });

  testWidgets('submitting without a category is blocked with a message', (
    tester,
  ) async {
    final l10n = await pumpComplaint(tester);

    await tester.enterText(
      detailsField(l10n),
      'Spam links everywhere',
    );
    await tester.tap(
      find.widgetWithText(FilledButton, l10n.buttonSubmitComplaint),
    );
    await tester.pumpAndSettle();

    expect(complaintCase.created, isEmpty);
    expect(find.text(l10n.complaintTypeRequired), findsOneWidget);
  });

  testWidgets('a picked category is submitted', (tester) async {
    final l10n = await pumpComplaint(tester);

    await tester.tap(typeDropdown());
    await tester.pumpAndSettle();
    await tester.tap(find.text(l10n.violatesPlatformRules).last);
    await tester.pumpAndSettle();
    await tester.enterText(
      detailsField(l10n),
      'Spam links everywhere',
    );
    await tester.tap(
      find.widgetWithText(FilledButton, l10n.buttonSubmitComplaint),
    );
    await tester.pumpAndSettle();

    expect(complaintCase.created, hasLength(1));
    expect(
      complaintCase.created.single.type,
      ComplaintType.violatesPlatformRules,
    );
  });

  testWidgets('the fetched beacon title and author are shown above the form', (
    tester,
  ) async {
    await pumpComplaint(tester);

    final title = find.textContaining(_title);
    final author = find.textContaining(_author);
    expect(title, findsWidgets);
    expect(author, findsWidgets);
    expect(
      tester.getTopLeft(title.first).dy,
      lessThan(tester.getTopLeft(typeDropdown()).dy),
    );
    expect(
      tester.getTopLeft(author.first).dy,
      lessThan(tester.getTopLeft(typeDropdown()).dy),
    );
  });

  testWidgets('a reported person shows the fetched name, no author line', (
    tester,
  ) async {
    await pumpComplaint(
      tester,
      id: 'U7',
      profile: const Profile(id: 'U7', displayName: 'Bob Stone'),
    );

    expect(find.textContaining('Bob Stone'), findsWidgets);
    expect(find.textContaining(_author), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a failed fetch shows no title line and the form still works', (
    tester,
  ) async {
    final l10n = await pumpComplaint(tester, fetchFails: true);

    expect(tester.takeException(), isNull);
    expect(find.textContaining(_title), findsNothing);
    expect(typeDropdown(), findsOneWidget);

    await tester.tap(typeDropdown());
    await tester.pumpAndSettle();
    await tester.tap(find.text(l10n.violatesPlatformRules).last);
    await tester.pumpAndSettle();
    await tester.enterText(detailsField(l10n), 'Spam links everywhere');
    await tester.tap(
      find.widgetWithText(FilledButton, l10n.buttonSubmitComplaint),
    );
    await tester.pumpAndSettle();

    expect(complaintCase.created, hasLength(1));
  });

  testWidgets('one line explains what the email is used for', (tester) async {
    final l10n = await pumpComplaint(tester);

    expect(l10n.complaintEmailUse.trim(), isNotEmpty);
    expect(l10n.complaintEmailUse, isNot(contains('\n')));
    expect(find.text(l10n.complaintEmailUse), findsOneWidget);
  });

  testWidgets('the new copy is shown in Russian too', (tester) async {
    final ru = await pumpComplaint(tester, locale: const Locale('ru'));
    final en = lookupL10n(const Locale('en'));

    expect(find.text(ru.complaintTypeHint), findsOneWidget);
    expect(find.text(ru.complaintEmailUse), findsOneWidget);
    expect(ru.complaintTypeHint, isNot(en.complaintTypeHint));
    expect(ru.complaintTypeRequired, isNot(en.complaintTypeRequired));
    expect(ru.complaintEmailUse, isNot(en.complaintEmailUse));
  });

  test('the route carries no title or author (spoofable, leaks titles)', () {
    final route = ComplaintRoute(id: 'B1');

    expect(route.rawPathParams['id'], 'B1');
    expect(route.rawQueryParams.containsKey('title'), isFalse);
    expect(route.rawQueryParams.containsKey('author'), isFalse);
  });

  test('the screen reads no title/author query parameter', () {
    final source = File(
      'lib/features/complaint/ui/screen/complaint_screen.dart',
    ).readAsStringSync();

    expect(source, isNot(contains("QueryParam('title')")));
    expect(source, isNot(contains("QueryParam('author')")));
  });
}
