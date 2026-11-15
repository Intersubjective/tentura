// Closing the card of a helper who has several live help-offer receipts
// settles every one of them (the desk shows them as a single row), from both
// the inline row action and the Respond sheet.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';
import 'package:mockito/mockito.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';
import 'package:tentura_root/domain/enums.dart';

import 'package:tentura/data/repository/mock/client_repository_mocks.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/attention/entity/attention_feed.dart';
import 'package:tentura/domain/attention/entity/attention_receipt.dart';
import 'package:tentura/domain/attention/entity/my_work_beacon_attention.dart';
import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/commitment_stake_state.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/beacon_view/domain/use_case/beacon_view_case.dart';
import 'package:tentura/features/closure/data/repository/closure_repository.dart';
import 'package:tentura/features/my_work/domain/entity/my_work_card_view_model.dart';
import 'package:tentura/features/my_work/domain/entity/my_work_fetch_types.dart';
import 'package:tentura/features/my_work/ui/bloc/my_work_cubit.dart';
import 'package:tentura/features/my_work/ui/widget/my_work_cards.dart';
import 'package:tentura/features/my_work/ui/widget/my_work_obligation_block.dart';
import 'package:tentura/features/profile/ui/bloc/profile_cubit.dart';
import 'package:tentura/ui/bloc/presence_cubit.dart';
import 'package:tentura/ui/bloc/screen_cubit.dart';
import 'package:tentura/ui/effect/ui_effect_port.dart';
import 'package:tentura/ui/l10n/l10n.dart';

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

FakeHelpOfferCoordinationRow _row() {
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
    offerKind: 0,
    isDirectAuthorForward: false,
    authorSeenAt: null,
  );
}

/// The server reports live only the receipts that were not settled.
class _SettlingAttention extends StubAttentionRepository {
  _SettlingAttention(this._live);

  final List<AttentionReceipt> _live;

  /// Receipt ids whose settlement the server refuses.
  final failIds = <String>{};

  void _publish() => myWorkAttentionResult = [
    MyWorkBeaconAttention(
      beaconId: _beaconId,
      unseenCount: _live.length,
      liveObligations: List.of(_live),
    ),
  ];

  @override
  Future<int> settle({required String receiptId, required String kind}) async {
    if (failIds.contains(receiptId)) throw StateError('refused $receiptId');
    _live.removeWhere((r) => r.id == receiptId);
    _publish();
    return super.settle(receiptId: receiptId, kind: kind);
  }
}

AttentionReceipt _offer(String id, String offererId, DateTime createdAt) =>
    AttentionReceipt(
      id: id,
      category: 'coordination',
      kind: 'helpOfferSubmitted',
      priority: 'normal',
      title: 'Offerer',
      body: 'I can sew $id',
      actionUrl: '/#/',
      createdAt: createdAt,
      collapsedCount: 1,
      presentationKey: 'help_offer_submitted',
      presentationPayloadJson: '{}',
      surface: AttentionSurface.myWork,
      beaconId: _beaconId,
      requiresAction: true,
      targetEntityId: offererId,
    );

AttentionReceipt _r2() => _offer('r2', 'offerer-1', DateTime.utc(2026, 9, 2));
AttentionReceipt _r1() => _offer('r1', 'offerer-1', DateTime.utc(2026, 9));
AttentionReceipt _r3() => _offer('r3', 'offerer-2', DateTime.utc(2026, 9, 3));

/// [offerActive] false: the offer no longer counts, so the row itself carries
/// the close-card action; true: the row offers Respond and the sheet closes.
Future<({_SettlingAttention attention, MyWorkCubit cubit})> _pumpDesk(
  WidgetTester tester, {
  required List<AttentionReceipt> live,
  required bool offerActive,
}) async {
  await GetIt.I.reset();
  addTearDown(GetIt.I.reset);
  final beacon = Beacon.empty.copyWith(
    id: _beaconId,
    title: 'Garden',
    status: BeaconStatus.open,
    author: _viewer,
    helpOfferUsers: offerActive ? const [_offerer] : const [],
  );
  GetIt.I
    ..registerSingleton<Logger>(Logger('close-card-all-receipts'))
    ..registerSingleton<ClosureRepository>(ClosureRepositoryMock())
    ..registerSingleton<UiEffectPort>(FakeUiEffectPort())
    ..registerSingleton<BeaconViewCase>(
      buildTestBeaconViewCase(
        beaconRepo: TrackingBeaconRepository()
          ..fetchByIdHandler = (id) async => beacon,
        coordinationRepo: FakeBeaconViewCoordinationRepository(
          rows: [_row()],
        ),
      ),
    );
  final attention = _SettlingAttention(List.of(live))
    ..obligationBeaconIds = {_beaconId}
    .._publish();
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
  return (attention: attention, cubit: cubit);
}

Finder _rowClose(String id) =>
    find.byKey(ValueKey<String>('my-work-obligation-close:$id'));

/// Every inline close-card control of a row, whatever receipt it is keyed by.
final _anyRowClose = find.byWidgetPredicate((w) {
  final key = w.key;
  return key is ValueKey<String> &&
      key.value.startsWith('my-work-obligation-close:');
});

Finder _sheetClose() => find.text(
  lookupL10n(const Locale('en')).myWorkObligationCloseCard,
);

List<String> _liveIds(MyWorkCubit cubit) => [
  for (final r
      in cubit.state.attentionByBeacon[_beaconId]?.liveObligations ??
          const <AttentionReceipt>[])
    r.id,
];

/// The inline row as the block renders it for an admitted offer (no desk).
Future<StubAttentionRepository> _pumpBlock(WidgetTester tester) async {
  final attention = StubAttentionRepository();
  final cubit = MyWorkCubit(
    userId: 'user-1',
    myWorkCase: buildTestMyWorkCase(attentionRepository: attention),
  );
  addTearDown(cubit.close);
  final vm = MyWorkCardViewModel(
    beaconId: _beaconId,
    role: MyWorkCardRole.authored,
    kind: MyWorkCardKind.authoredActive,
    beacon: Beacon.empty.copyWith(
      id: _beaconId,
      title: 'Garden',
      status: BeaconStatus.open,
      helpOfferUsers: const [_offerer],
    ),
    stakeState: CommitmentStakeState.acknowledged,
  );
  await tester.pumpWidget(
    MaterialApp(
      locale: const Locale('en'),
      theme: TenturaTheme.light(),
      localizationsDelegates: L10n.localizationsDelegates,
      supportedLocales: L10n.supportedLocales,
      home: TenturaResponsiveScope(
        child: Scaffold(
          body: BlocProvider<MyWorkCubit>.value(
            value: cubit,
            child: MyWorkObligationBlock(
              vm: vm,
              obligations: [_r2(), _r1()],
              onRespondHelpOffer: (_) {},
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return attention;
}

void main() {
  // The block is handed a fixed list, so row removal is not observable here;
  // the desk tests below prove the row leaves.
  testWidgets('an admitted offer with two live receipts shows one close-card '
      'control whose tap settles both receipts', (tester) async {
    final attention = await _pumpBlock(tester);
    expect(_anyRowClose, findsOneWidget);
    expect(_rowClose('r2'), findsOneWidget);

    await tester.tap(_rowClose('r2'));
    await tester.pumpAndSettle();

    expect(attention.settleCalls.toSet(), {'r2', 'r1'});
    expect(attention.settleCalls, hasLength(2));
  });

  testWidgets('closing a helper row with two live receipts settles both and '
      'removes the row with one tap', (tester) async {
    final (:attention, :cubit) = await _pumpDesk(
      tester,
      live: [_r2(), _r1()],
      offerActive: false,
    );
    expect(_rowClose('r2'), findsOneWidget);

    await tester.tap(_rowClose('r2'));
    await tester.pumpAndSettle();

    expect(attention.settleCalls.toSet(), {'r2', 'r1'});
    expect(attention.settleCalls, hasLength(2));
    expect(_rowClose('r2'), findsNothing);
    expect(_rowClose('r1'), findsNothing);
    expect(find.textContaining('I can sew'), findsNothing);
    expect(_liveIds(cubit), isEmpty);
  });

  testWidgets('the helper row leaves in one update: no state keeps only one '
      'of the two receipts', (tester) async {
    final (:attention, :cubit) = await _pumpDesk(
      tester,
      live: [_r2(), _r1()],
      offerActive: false,
    );
    final seen = <List<String>>[];
    final sub = cubit.stream.listen((_) => seen.add(_liveIds(cubit)));
    addTearDown(sub.cancel);

    await tester.tap(_rowClose('r2'));
    await tester.pumpAndSettle();

    expect(attention.settleCalls, isNotEmpty);
    expect(_liveIds(cubit), isEmpty);
    for (final ids in seen) {
      expect(ids.contains('r1') == ids.contains('r2'), isTrue, reason: '$ids');
    }
  });

  testWidgets('closing one helper leaves another helper row and its receipt '
      'alone', (tester) async {
    final (:attention, :cubit) = await _pumpDesk(
      tester,
      live: [_r3(), _r2(), _r1()],
      offerActive: false,
    );
    // Two helpers, two rows: u2's row exists before anything is closed.
    expect(_rowClose('r3'), findsOneWidget);
    expect(_rowClose('r2'), findsOneWidget);

    await tester.tap(_rowClose('r2'));
    await tester.pumpAndSettle();

    expect(attention.settleCalls.toSet(), {'r2', 'r1'});
    expect(attention.settleCalls, hasLength(2));
    expect(attention.settleCalls, isNot(contains('r3')));
    expect(_rowClose('r3'), findsOneWidget);
    expect(_liveIds(cubit), ['r3']);
  });

  testWidgets('close-card in the Respond sheet settles every live receipt of '
      'the helper and clears the row', (tester) async {
    final (:attention, :cubit) = await _pumpDesk(
      tester,
      live: [_r2(), _r1()],
      offerActive: true,
    );
    final respond = lookupL10n(const Locale('en')).myWorkObligationRespond;
    await tester.tap(find.text(respond));
    await tester.pumpAndSettle();

    await tester.tap(_sheetClose());
    await tester.pumpAndSettle();

    expect(attention.settleCalls.toSet(), {'r2', 'r1'});
    expect(attention.settleCalls, hasLength(2));
    // The sheet pops only when onCloseCard resolved to true, so a closed
    // sheet is the observable proof that the close succeeded.
    expect(_sheetClose(), findsNothing);
    expect(find.textContaining('I can sew'), findsNothing);
    expect(_liveIds(cubit), isEmpty);
  });

  testWidgets('the Respond sheet stays open when the server refuses one of the '
      "helper's receipts", (tester) async {
    final (:attention, :cubit) = await _pumpDesk(
      tester,
      live: [_r2(), _r1()],
      offerActive: true,
    );
    attention.failIds.add('r1');
    final respond = lookupL10n(const Locale('en')).myWorkObligationRespond;
    await tester.tap(find.text(respond));
    await tester.pumpAndSettle();

    await tester.tap(_sheetClose());
    await tester.pumpAndSettle();

    // Both receipts were attempted; the close did not succeed, so the sheet
    // (which pops only on a true result) is still there.
    expect(attention.settleCalls, contains('r2'));
    expect(_liveIds(cubit), contains('r1'));
    expect(_sheetClose(), findsOneWidget);
  });
}
