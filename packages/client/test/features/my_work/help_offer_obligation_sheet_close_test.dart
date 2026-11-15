// The Respond sheet of a help-offer obligation, reached the way a user reaches
// it: from the card on the desk. Whatever the sheet shows, it can close the
// card, which settles the obligation, dismisses the sheet and clears the row.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';
import 'package:tentura_root/domain/enums.dart';

import 'package:tentura/data/repository/mock/client_repository_mocks.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/attention/entity/attention_feed.dart';
import 'package:tentura/domain/attention/entity/attention_receipt.dart';
import 'package:tentura/domain/attention/entity/my_work_beacon_attention.dart';
import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/beacon_view/domain/use_case/beacon_view_case.dart';
import 'package:tentura/features/closure/data/repository/closure_repository.dart';
import 'package:tentura/features/my_work/domain/entity/my_work_fetch_types.dart';
import 'package:tentura/features/my_work/ui/bloc/my_work_cubit.dart';
import 'package:tentura/features/my_work/ui/widget/my_work_cards.dart';
import 'package:tentura/features/profile/ui/bloc/profile_cubit.dart';
import 'package:tentura/ui/bloc/presence_cubit.dart';
import 'package:tentura/ui/bloc/screen_cubit.dart';
import 'package:tentura/ui/effect/ui_effect_port.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/test_ids.dart';

import '../../ui/effect/fake_ui_effect_port.dart';
import '../beacon_view/beacon_view_case_test_support.dart';
import 'my_work_test_support.dart';

const _viewer = Profile(id: 'author-1', displayName: 'Author');
const _offerer = Profile(id: 'offerer-1', displayName: 'Offerer');
const _beaconId = 'b1';

class _TestProfileCubit extends Mock implements ProfileCubit {
  @override
  ProfileState get state => const ProfileState(profile: _viewer);

  @override
  Stream<ProfileState> get stream =>
      Stream<ProfileState>.value(state).asBroadcastStream();
}

class _TestPresenceCubit extends Mock implements PresenceCubit {
  @override
  Map<String, UserPresenceStatus> get state => const {};

  @override
  Stream<Map<String, UserPresenceStatus>> get stream =>
      Stream<Map<String, UserPresenceStatus>>.value(state);
}

/// Settling a receipt removes it from what the server reports live.
class _SettlingAttention extends StubAttentionRepository {
  @override
  Future<int> settle({required String receiptId, required String kind}) async {
    myWorkAttentionResult = const [];
    return super.settle(receiptId: receiptId, kind: kind);
  }
}

AttentionReceipt _offer() => AttentionReceipt(
  id: 'r1',
  category: 'coordination',
  kind: 'helpOfferSubmitted',
  priority: 'normal',
  title: 'Offerer',
  body: 'I can sew',
  actionUrl: '/#/',
  createdAt: DateTime.utc(2026, 9),
  collapsedCount: 1,
  presentationKey: 'help_offer_submitted',
  presentationPayloadJson: '{}',
  surface: AttentionSurface.myWork,
  beaconId: _beaconId,
  requiresAction: true,
  targetEntityId: _offerer.id,
);

FakeHelpOfferCoordinationRow _row({int offerKind = 0}) {
  final now = DateTime.utc(2026, 9, 2);
  return (
    beaconId: _beaconId,
    userId: _offerer.id,
    user: _offerer,
    message: 'I can sew',
    helpType: null,
    roleLabel: '',
    status: 0,
    withdrawReason: null,
    createdAt: now,
    updatedAt: now,
    editedAt: null,
    responseType: null,
    responseUpdatedAt: null,
    responseAuthorUserId: null,
    roomAccess: null,
    admissionAction: null,
    lastDeclineReason: null,
    lastRemoveReason: null,
    stakeState: 1,
    offerKind: offerKind,
    isDirectAuthorForward: false,
    authorSeenAt: null,
  );
}

Future<_SettlingAttention> _pumpDesk(
  WidgetTester tester, {
  required bool offerExists,
  int offerKind = 0,
}) async {
  await GetIt.I.reset();
  addTearDown(GetIt.I.reset);
  final beacon = Beacon.empty.copyWith(
    id: _beaconId,
    title: 'Garden',
    status: BeaconStatus.open,
    author: _viewer,
    helpOfferUsers: const [_offerer],
  );
  GetIt.I
    ..registerSingleton<ClosureRepository>(ClosureRepositoryMock())
    ..registerSingleton<UiEffectPort>(FakeUiEffectPort())
    ..registerSingleton<BeaconViewCase>(
      buildTestBeaconViewCase(
        beaconRepo: TrackingBeaconRepository()
          ..fetchByIdHandler = (id) async => beacon,
        coordinationRepo: FakeBeaconViewCoordinationRepository(
          rows: offerExists ? [_row(offerKind: offerKind)] : const [],
        ),
      ),
    );
  final attention = _SettlingAttention()
    ..obligationBeaconIds = {_beaconId}
    ..myWorkAttentionResult = [
      MyWorkBeaconAttention(
        beaconId: _beaconId,
        unseenCount: 1,
        liveObligations: [_offer()],
      ),
    ];
  final repo = FakeMyWorkRepository()
    ..initResult = (
      authoredNonArchived: [beacon],
      helpOfferedNonArchived: const <MyWorkHelpOfferedRow>[],
      obligationBeacons: const [],
      archivedCountHint: 0,
    );
  final cubit = MyWorkCubit(
    userId: _viewer.id,
    myWorkCase: buildTestMyWorkCase(repo: repo, attentionRepository: attention),
  );
  addTearDown(cubit.close);
  await cubit.stream.firstWhere((s) => s.isSuccess && s.attentionLoaded);
  tester.view
    ..physicalSize = const Size(400, 1600)
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MultiBlocProvider(
      providers: [
        BlocProvider<MyWorkCubit>.value(value: cubit),
        BlocProvider<ProfileCubit>.value(value: _TestProfileCubit()),
        BlocProvider<PresenceCubit>.value(value: _TestPresenceCubit()),
        BlocProvider<ScreenCubit>(create: (_) => ScreenCubit.local()),
      ],
      child: MaterialApp(
        locale: const Locale('en'),
        theme: TenturaTheme.light(),
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        home: TenturaResponsiveScope(
          child: Scaffold(
            body: BlocBuilder<MyWorkCubit, MyWorkState>(
              builder: (context, state) => ListView(
                children: [
                  for (final vm in state.nonArchivedCards)
                    MyWorkCardRouter(vm: vm),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return attention;
}

final _close = find.byKey(
  const ValueKey<String>('help-offer-close-card:offerer-1'),
);
final _accept = find.text('Accept');
final _decline = find.byKey(TestIds.key(TestIds.helpOfferDecline('offerer-1')));

Future<void> _openSheet(WidgetTester tester) async {
  final respond = lookupL10n(const Locale('en')).myWorkObligationRespond;
  await tester.tap(find.widgetWithText(FilledButton, respond));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('a pending offer opens Accept and Decline plus close-card', (
    tester,
  ) async {
    await _pumpDesk(tester, offerExists: true);

    await _openSheet(tester);

    expect(_accept, findsOneWidget);
    expect(_decline, findsOneWidget);
    expect(_close, findsOneWidget);
  });

  testWidgets('close-card in the sheet settles the receipt, dismisses the '
      'sheet and clears the row', (tester) async {
    final attention = await _pumpDesk(tester, offerExists: true);
    await _openSheet(tester);

    await tester.tap(_close);
    await tester.pumpAndSettle();

    expect(attention.settleCalls, ['r1']);
    expect(_close, findsNothing);
    expect(_accept, findsNothing);
    expect(find.textContaining('I can sew'), findsNothing);
  });

  testWidgets('a missing offer still has close-card, which settles and '
      'dismisses the sheet', (tester) async {
    final attention = await _pumpDesk(tester, offerExists: false);
    await _openSheet(tester);

    expect(
      find.text(lookupL10n(const Locale('en')).myWorkObligationOfferMissing),
      findsOneWidget,
    );
    await tester.tap(_close);
    await tester.pumpAndSettle();

    expect(attention.settleCalls, ['r1']);
    expect(_close, findsNothing);
    expect(find.textContaining('I can sew'), findsNothing);
  });

  testWidgets('a backup offer opens Keep as standby and Decline plus '
      'close-card', (tester) async {
    await _pumpDesk(tester, offerExists: true, offerKind: 1);

    await _openSheet(tester);

    expect(
      find.byKey(TestIds.key(TestIds.helpOfferKeepStandby('offerer-1'))),
      findsOneWidget,
    );
    expect(_decline, findsOneWidget);
    expect(_close, findsOneWidget);
  });
}
