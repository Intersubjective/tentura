// #268: accepting a helper from My Desk (the help-offer sheet) explains the
// shared-discussion model in one line, as the People tab does; a viewer who
// cannot accept does not see it.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';
import 'package:tentura_root/domain/enums.dart';

import 'package:tentura/design_system/tentura_responsive_scope.dart';
import 'package:tentura/design_system/tentura_theme.dart';
import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/beacon_view/ui/sheet/help_offer_tile_sheet.dart';
import 'package:tentura/features/profile/ui/bloc/profile_cubit.dart';
import 'package:tentura/ui/bloc/presence_cubit.dart';
import 'package:tentura/ui/bloc/screen_cubit.dart';
import 'package:tentura/ui/l10n/l10n.dart';

import '../../ui/effect/fake_ui_effect_port.dart';
import 'beacon_view_case_test_support.dart';

const _author = Profile(id: 'author-1', displayName: 'Author');
const _offerer = Profile(id: 'offerer-1', displayName: 'Offerer');
const _hint =
    "Helpers you accept join this Request's shared discussion. "
    'There are no private chats.';

class _MockProfileCubit extends Mock implements ProfileCubit {
  _MockProfileCubit(this.viewer);

  final Profile viewer;

  @override
  ProfileState get state => ProfileState(profile: viewer);

  @override
  Stream<ProfileState> get stream => Stream<ProfileState>.value(state);
}

class _MockPresenceCubit extends Mock implements PresenceCubit {
  @override
  Map<String, UserPresenceStatus> get state => const {};

  @override
  Stream<Map<String, UserPresenceStatus>> get stream =>
      Stream<Map<String, UserPresenceStatus>>.value(state);
}

FakeHelpOfferCoordinationRow _row() {
  final now = DateTime.utc(2026, 9, 2);
  return (
    beaconId: 'b1',
    userId: _offerer.id,
    user: _offerer,
    message: 'I can help',
    helpType: null,
    roleLabel: '',
    status: 0,
    withdrawReason: null,
    createdAt: now,
    updatedAt: now,
    responseType: null,
    responseUpdatedAt: null,
    responseAuthorUserId: null,
    roomAccess: null,
    admissionAction: null,
    lastDeclineReason: null,
    lastRemoveReason: null,
    stakeState: 0,
    offerKind: 0,
    isDirectAuthorForward: false,
    authorSeenAt: null,
  );
}

Future<void> _open(WidgetTester tester, Profile viewer) async {
  final beaconRepo = TrackingBeaconRepository()
    ..fetchByIdHandler = (id) async => Beacon.empty.copyWith(
      id: id,
      status: BeaconStatus.open,
      author: _author,
    );
  final beaconViewCase = buildTestBeaconViewCase(
    beaconRepo: beaconRepo,
    coordinationRepo: FakeBeaconViewCoordinationRepository(rows: [_row()]),
  );
  await tester.pumpWidget(
    MultiBlocProvider(
      providers: [
        BlocProvider<ProfileCubit>.value(value: _MockProfileCubit(viewer)),
        BlocProvider<PresenceCubit>.value(value: _MockPresenceCubit()),
        BlocProvider<ScreenCubit>(create: (_) => ScreenCubit.local()),
      ],
      child: MaterialApp(
        theme: TenturaTheme.light(),
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        locale: const Locale('en'),
        home: TenturaResponsiveScope(
          child: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showHelpOfferTileSheet(
                  context: context,
                  beaconId: 'b1',
                  offerUserId: _offerer.id,
                  myProfile: viewer,
                  beaconViewCase: beaconViewCase,
                  effects: FakeUiEffectPort(),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('the author accepting from My Desk sees the one line', (
    tester,
  ) async {
    await _open(tester, _author);

    expect(find.text(_hint), findsOneWidget);
  });

  testWidgets('someone who cannot accept does not', (tester) async {
    await _open(tester, const Profile(id: 'other-1', displayName: 'Other'));

    expect(find.text(_hint), findsNothing);
  });
}
