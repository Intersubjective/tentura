// SPDX-License-Identifier: AGPL-3.0-only
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/invitation_entity.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/auth/ui/bloc/auth_cubit.dart';
import 'package:tentura/features/connect/ui/widget/connect_bottom_sheet.dart';
import 'package:tentura/features/invitation/data/repository/invitation_repository.dart';
import 'package:tentura/features/invitation/ui/dialog/invitation_accept_dialog.dart';
import 'package:tentura/ui/l10n/l10n.dart';

const _me = 'U325f01f7d5b8';
const _code = 'I0fbceade7077';

class _FakeAuth extends Fake implements AuthCubit {
  @override
  AuthState get state =>
      AuthState(updatedAt: DateTime.utc(2026), currentAccountId: _me);
}

class _FakeInvitations extends Fake implements InvitationRepository {
  _FakeInvitations(this.issuerId, {this.acceptError});

  final String issuerId;

  final Exception? acceptError;

  final accepted = <String>[];

  @override
  Future<InvitationFetchByIdResult?> fetchById(String id) async => (
    invitation: InvitationEntity(
      id: id,
      createdAt: DateTime.utc(2026),
      updatedAt: DateTime.utc(2026),
    ),
    issuer: Profile(id: issuerId, displayName: 'Tab QA'),
  );

  @override
  Future<void> accept(String id) async {
    final error = acceptError;
    if (error != null) throw error;
    accepted.add(id);
  }
}

void main() {
  tearDown(GetIt.I.reset);

  Future<_FakeInvitations> pumpAndSearch(
    WidgetTester tester, {
    required String issuerId,
    Exception? acceptError,
  }) async {
    final invitations = _FakeInvitations(issuerId, acceptError: acceptError);
    GetIt.I
      ..registerSingleton<InvitationRepository>(invitations)
      ..registerSingleton<AuthCubit>(_FakeAuth())
      ..registerSingleton<Logger>(Logger('test'));
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        theme: TenturaTheme.light(),
        home: const Scaffold(body: ConnectBottomSheet()),
      ),
    );
    await tester.enterText(find.byType(TextFormField), _code);
    await tester.tap(find.byType(FilledButton));
    await tester.pumpAndSettle();
    return invitations;
  }

  testWidgets('own invite code is refused without the accept dialog', (
    tester,
  ) async {
    final invitations = await pumpAndSearch(tester, issuerId: _me);

    expect(
      find.text('This is your own invite link.', findRichText: true),
      findsOneWidget,
    );
    expect(find.byType(InvitationAcceptDialog), findsNothing);
    expect(invitations.accepted, isEmpty);
  });

  testWidgets("someone else's invite still asks to accept", (tester) async {
    await pumpAndSearch(tester, issuerId: 'U96e2e7582017');

    expect(find.byType(InvitationAcceptDialog), findsOneWidget);
    expect(
      find.text('This is your own invite link.', findRichText: true),
      findsNothing,
    );
  });

  testWidgets('a refused accept shows an error instead of failing silently', (
    tester,
  ) async {
    // Without the try/catch the server's refusal escapes the tap handler
    // and nothing is shown (review of #371, Should fix 2).
    await pumpAndSearch(
      tester,
      issuerId: 'U96e2e7582017',
      acceptError: Exception('Wrong invitation'),
    );
    await tester.tap(find.widgetWithText(TextButton, 'Yes'));
    await tester.pumpAndSettle();

    expect(
      find.textContaining('Something went wrong', findRichText: true),
      findsOneWidget,
    );
    expect(find.text('Invitation accepted!'), findsNothing);
  });
}
