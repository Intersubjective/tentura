import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';

import 'package:tentura/design_system/tentura_theme.dart';
import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/forward/domain/entity/forward_candidate.dart';
import 'package:tentura/features/forward/ui/bloc/forward_cubit.dart';
import 'package:tentura/features/forward/ui/screen/forward_beacon_screen.dart';
import 'package:tentura/features/forward/ui/widget/forward_invite_bar.dart';
import 'package:tentura/features/invitation/data/repository/invitation_repository.dart';
import 'package:tentura/features/profile/ui/bloc/profile_cubit.dart';
import 'package:tentura/ui/dialog/share_code_dialog.dart';
import 'package:tentura/ui/effect/ui_effect.dart';
import 'package:tentura/ui/effect/ui_effect_port.dart';
import 'package:tentura/ui/l10n/l10n.dart';

import '../../support/remote_wire_harness.dart';
import '../../ui/effect/fake_ui_effect_port.dart';

// #452: "Invite new person" on the Forward screen opened a dialog titled
// "Invitation code" that never said the invite is for this request, that
// the link works once, or how long it stays valid.

class _MockProfileCubit extends Mock implements ProfileCubit {
  @override
  ProfileState get state => const ProfileState();

  @override
  Stream<ProfileState> get stream => Stream<ProfileState>.value(state);
}

ForwardCubit _forwardCubitWithBeacon() {
  final cubit = ForwardCubit(
    beaconId: 'b1',
    debugSkipInitialLoad: true,
    effects: FakeUiEffectPort(),
  );
  final beacon = Beacon.empty.copyWith(
    id: 'aaaaaaaa-bbbb-cccc-dddd-1234567890ab',
    title: 'Test beacon',
    context: 'General',
    viewerCanForward: true,
    startAt: DateTime.utc(2025, 5, 12),
    endAt: DateTime.utc(2025, 5, 19),
  );
  cubit.emit(
    ForwardState(
      beaconId: 'b1',
      beacon: beacon,
      candidates: const [
        ForwardCandidate(
          profile: Profile(
            id: 'u1',
            displayName: 'Clara',
            rScore: 1,
            score: 70,
          ),
        ),
      ],
      candidatesLoad: const ForwardCandidatesReady(),
    ),
  );
  return cubit;
}

// The invite dialog's validity copy must follow the TTL the server serves, not
// the compiled default. Real `InvitationRepository` over the real wire stack
// (only HTTP is faked), phone-sized surface, both locales.

Map<String, dynamic> _createdInvitation() => {
  '__typename': 'mutation_root',
  'invitationCreate': {
    '__typename': 'invitation',
    'id': 'Iabc123def456',
    'beacon_id': 'aaaaaaaa-bbbb-cccc-dddd-1234567890ab',
    'invited_id': null,
    'addressee_name': '',
    'created_at': '2026-10-19T00:00:00+00:00',
    'updated_at': '2026-10-19T00:00:00+00:00',
  },
};

/// Opens the Forward page at 375x667 in [locale] against a server serving
/// [servedHours], taps "Invite new person" and returns the dialog's text.
Future<String> _inviteDialogText(
  WidgetTester tester,
  Locale locale, {
  int? servedHours,
}) async {
  tester.view
    ..physicalSize = const Size(750, 1334)
    ..devicePixelRatio = 2;
  addTearDown(tester.view.reset);

  late String text;
  await tester.runAsync(() async {
    await withRemoteWire(
      {
        if (servedHours != null)
          'InvitationTtl': {
            '__typename': 'query_root',
            'invitationTtlHours': servedHours,
          },
        'InvitationCreate': _createdInvitation(),
      },
      <WireSent>[],
      (remote) async {
        final effects = FakeUiEffectPort();
        GetIt.I
          ..registerSingleton<InvitationRepository>(
            InvitationRepository(remote),
          )
          ..registerSingleton<UiEffectPort>(effects);
        addTearDown(GetIt.I.reset);

        final cubit = _forwardCubitWithBeacon();
        addTearDown(cubit.close);

        await tester.pumpWidget(
          MaterialApp(
            locale: locale,
            localizationsDelegates: L10n.localizationsDelegates,
            supportedLocales: L10n.supportedLocales,
            theme: TenturaTheme.light(),
            home: MultiBlocProvider(
              providers: [
                BlocProvider<ForwardCubit>.value(value: cubit),
                BlocProvider<ProfileCubit>.value(value: _MockProfileCubit()),
              ],
              child: const ForwardBeaconPage(beaconId: 'b1'),
            ),
          ),
        );
        await tester.pumpAndSettle();

        tester
            .widget<ForwardInviteBar>(find.byType(ForwardInviteBar))
            .onInvite();

        final dialog = find.byType(ShareCodeDialog);
        for (var i = 0; i < 60 && dialog.evaluate().isEmpty; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 50));
          await tester.pump(const Duration(milliseconds: 50));
        }
        await tester.pumpAndSettle();
        expect(dialog, findsOneWidget, reason: _describe(effects));

        text = tester
            .widgetList<RichText>(
              find.descendant(of: dialog, matching: find.byType(RichText)),
            )
            .map((t) => t.text.toPlainText())
            .join('\n');
      },
    );
  });
  return text;
}

String _describe(FakeUiEffectPort effects) => effects.emitted
    .map((e) => e is ShowError ? 'ShowError(${e.error})' : '$e')
    .join(', ');

void main() {
  testWidgets('English invite dialog states the served lifetime in days', (
    tester,
  ) async {
    final text = await _inviteDialogText(
      tester,
      const Locale('en'),
      servedHours: 48,
    );
    expect(text, contains('expires in 2 days'));
    expect(tester.takeException(), isNull);
  });

  testWidgets('Russian invite dialog states the served lifetime in full', (
    tester,
  ) async {
    final text = await _inviteDialogText(
      tester,
      const Locale('ru'),
      servedHours: 72,
    );
    expect(text, contains('действует 3 дня.'));
    expect(tester.takeException(), isNull);
  });

  testWidgets('invite dialog falls back to the compiled lifetime when the '
      'server does not answer the TTL lookup', (tester) async {
    final text = await _inviteDialogText(tester, const Locale('en'));
    expect(text, contains('expires in 7 days'));
    expect(tester.takeException(), isNull);
  });
}
