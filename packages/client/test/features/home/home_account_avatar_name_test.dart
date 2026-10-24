// #660: the account avatar at the top of a phone Home tab is named after the
// person as shown (Profile.shownName), not the raw stored display name; in
// Russian the server placeholder must not be read out in English.
//
// Profile.shownName differs from displayName for the server placeholder
// "New member" (shown in the app language) and for a contact name.

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/domain/util/display_name_prompt.dart';
import 'package:tentura/features/auth/ui/bloc/auth_cubit.dart';
import 'package:tentura/features/home/ui/widget/home_account_avatar_button.dart';
import 'package:tentura/features/profile/ui/bloc/profile_cubit.dart';
import 'package:tentura/ui/l10n/l10n.dart';

class _ProfileCubit extends Mock implements ProfileCubit {
  _ProfileCubit(this._profile);

  final Profile _profile;

  @override
  ProfileState get state => ProfileState(profile: _profile);

  @override
  Stream<ProfileState> get stream => const Stream.empty();

  @override
  bool get isClosed => false;

  @override
  Future<void> close() async {}
}

final class _Auth extends Fake implements AuthCubit {
  @override
  AuthState get state => AuthState(
    updatedAt: DateTime(2026),
    currentAccountId: 'U1',
  );

  @override
  Stream<AuthState> get stream => const Stream.empty();

  @override
  bool get isClosed => false;
}

Future<void> _pump(WidgetTester tester, Profile profile) async {
  final cubit = _ProfileCubit(profile);
  GetIt.I
    ..registerSingleton<ProfileCubit>(cubit)
    ..registerSingleton<AuthCubit>(_Auth());
  addTearDown(GetIt.I.reset);
  await tester.pumpWidget(
    MaterialApp(
      locale: const Locale('ru'),
      theme: TenturaTheme.light(),
      localizationsDelegates: L10n.localizationsDelegates,
      supportedLocales: L10n.supportedLocales,
      home: BlocProvider<ProfileCubit>.value(
        value: cubit,
        child: Scaffold(
          appBar: AppBar(actions: const [HomeAccountAvatarButton()]),
        ),
      ),
    ),
  );
  await tester.pump();
}

String? _tooltip(WidgetTester tester) => tester
    .widget<IconButton>(find.byKey(HomeAccountAvatarButton.buttonKey))
    .tooltip;

/// Everything a screen reader can say for the button: the tooltip, labels,
/// values and hints of its semantics node and every node under it (the web
/// engine reads them together: "New member\nПрофиль\nNM" in the QA report).
String _spoken(WidgetTester tester) {
  final parts = <String>[];
  void visit(SemanticsNode node) {
    final data = node.getSemanticsData();
    parts.addAll([data.tooltip, data.label, data.value, data.hint]);
    node.visitChildren((child) {
      visit(child);
      return true;
    });
  }

  visit(tester.getSemantics(find.byKey(HomeAccountAvatarButton.buttonKey)));
  return parts.where((p) => p.isNotEmpty).join('\n');
}

void main() {
  group('the New member placeholder in Russian', () {
    setUp(
      () => setNewMemberDisplayNameLabel(
        lookupL10n(const Locale('ru')).newMemberDisplayName,
      ),
    );
    tearDown(() => setNewMemberDisplayNameLabel(kNewMemberDisplayName));

    testWidgets('the phone avatar button says Новый участник', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      await _pump(tester, const Profile(id: 'U1', displayName: 'New member'));

      expect(_tooltip(tester), 'Новый участник');
      final label = _spoken(tester);
      expect(label, contains('Новый участник'));
      expect(label, isNot(contains('New member')));
      expect(find.text('NM'), findsNothing);
      expect(find.text('НУ'), findsOneWidget);
      semantics.dispose();
    });
  });

  testWidgets('the avatar button is named after the shown name', (
    tester,
  ) async {
    await _pump(
      tester,
      const Profile(id: 'U1', displayName: 'New member', contactName: 'Аня'),
    );

    expect(_tooltip(tester), 'Аня');
  });

  testWidgets('the screen reader does not hear the stored name', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await _pump(
      tester,
      const Profile(id: 'U1', displayName: 'New member', contactName: 'Аня'),
    );

    final label = _spoken(tester);
    expect(label, contains('Аня'));
    expect(label, isNot(contains('New member')));
    // Initials follow the shown name too ("NM" was read out in English).
    expect(find.text('NM'), findsNothing);
    expect(find.text('АН'), findsOneWidget);
    semantics.dispose();
  });

  testWidgets('guard: a chosen name is the tooltip as it is', (tester) async {
    await _pump(tester, const Profile(id: 'U1', displayName: 'Олег Петров'));

    expect(_tooltip(tester), 'Олег Петров');
    expect(find.text('ОП'), findsOneWidget);
  });

  testWidgets('guard: no name yet falls back to Профиль', (tester) async {
    await _pump(tester, const Profile(id: 'U1'));

    expect(_tooltip(tester), 'Профиль');
  });
}
