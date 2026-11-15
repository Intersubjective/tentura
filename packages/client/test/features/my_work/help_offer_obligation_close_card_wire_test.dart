// The close-card action of a help-offer obligation, from the card on the
// desk through the real use case and repository to the GraphQL transport (only
// HTTP is faked), and back into what the card shows.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';
import 'package:mockito/mockito.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';

import 'package:tentura/data/repository/attention_repository.dart';
import 'package:tentura/data/service/remote_api_client/remote_request_client.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/attention/attention_case.dart';
import 'package:tentura/domain/attention/feed_session_registry.dart';
import 'package:tentura/domain/attention/port/attention_account_port.dart';
import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/commitment_stake_state.dart';
import 'package:tentura/domain/entity/coordination_response_type.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/my_work/ui/bloc/my_work_cubit.dart';
import 'package:tentura/features/my_work/ui/widget/my_work_cards.dart';
import 'package:tentura/features/my_work/ui/widget/my_work_obligation_block.dart';
import 'package:tentura/features/profile/ui/bloc/profile_cubit.dart';
import 'package:tentura/ui/bloc/screen_cubit.dart';
import 'package:tentura/ui/l10n/l10n.dart';

import '../../support/remote_wire_harness.dart';
import '../../support/test_realtime_sync.dart';
import '../block/support/controllable_block_case.dart';
import 'my_work_test_support.dart';

const _viewerId = 'author-1';
const _beaconId = 'beacon-1';

final _beacon = Beacon.empty.copyWith(
  id: _beaconId,
  title: 'Garden',
  status: BeaconStatus.open,
  author: const Profile(id: _viewerId, displayName: 'Me'),
);

final class _Accounts implements AttentionAccountPort {
  @override
  Stream<String> get currentAccountChanges => const Stream.empty();
}

final class _TestProfileCubit extends Mock implements ProfileCubit {
  @override
  ProfileState get state => const ProfileState(
    profile: Profile(id: _viewerId, displayName: 'Me'),
  );

  @override
  Stream<ProfileState> get stream =>
      Stream<ProfileState>.value(state).asBroadcastStream();
}

Map<String, dynamic> _receipt() => {
  '__typename': 'v2_AttentionReceipt',
  'id': 'offer-receipt',
  'category': 'coordination',
  'kind': 'helpOfferSubmitted',
  'priority': 'normal',
  'title': 'Anna',
  'body': 'I can sew',
  'actionUrl': '/#/',
  'createdAt': '2026-11-11T12:00:00Z',
  'collapsedCount': 1,
  'beaconId': _beaconId,
  'targetEntityId': 'offerer-1',
  'presentationKey': 'help_offer_submitted',
  'presentationPayloadJson': jsonEncode({'eventType': 'helpOfferSubmitted'}),
  'requiresAction': true,
  'surface': 'myWork',
  'itemKind': 'receipt',
};

final class _Server {
  bool settled = false;

  Future<Map<String, dynamic>> respond(WireSent request) async {
    switch (request.operationName) {
      case 'MyWorkAttention':
        return {
          '__typename': 'query_root',
          'myWorkAttention': [
            {
              '__typename': 'v2_MyWorkBeaconAttention',
              'beaconId': _beaconId,
              'unseenCount': settled ? 0 : 1,
              'needsYouAt': null,
              'firstEntryAt': null,
              'latestUnseen': null,
              'liveObligations': [if (!settled) _receipt()],
            },
          ],
        };
      case 'AttentionSettle':
        settled = true;
        return {'attentionSettle': 1};
      case 'AttentionLiveObligations':
        return {
          'liveObligationBeacons': settled ? <String>[] : [_beaconId],
        };
      case 'AttentionMarkers':
        return {
          'attentionMarkers': {'unreadBeaconIds': <String>[]},
        };
      default:
        return {};
    }
  }
}

Future<MyWorkCubit> _cubit(RemoteRequestClient remote) async {
  final attention = AttentionCase(
    AttentionRepository(remote),
    _Accounts(),
    buildTestRealtimeSync().case_,
    noopBlockCase(),
    FeedSessionRegistry(),
    Logger('close-card-wire'),
  );
  final repo = FakeMyWorkRepository()
    ..initResult = (
      authoredNonArchived: const <Beacon>[],
      helpOfferedNonArchived: [
        (
          beacon: _beacon,
          offerHelpMessage: 'I can sew',
          helpType: null,
          authorResponseType: CoordinationResponseType.useful,
          stakeState: CommitmentStakeState.acknowledged,
          forwarderSenders: const <Profile>[],
          helpOfferRowUpdatedAt: DateTime(2026, 9, 4),
          authorCoordinationUpdatedAt: DateTime(2026, 9, 5),
          coordinationAuthor: null,
        ),
      ],
      obligationBeacons: [(beacon: _beacon, viewerArchived: false)],
      archivedCountHint: 0,
    );
  final cubit = MyWorkCubit(
    userId: _viewerId,
    myWorkCase: buildTestMyWorkCase(repo: repo, attentionCase: attention),
  );
  addTearDown(cubit.close);
  await cubit.stream.firstWhere((s) => s.isSuccess && s.attentionLoaded);
  return cubit;
}

Future<void> _pumpDesk(WidgetTester tester, MyWorkCubit cubit) async {
  tester.view
    ..physicalSize = const Size(400, 1600)
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      locale: const Locale('en'),
      theme: TenturaTheme.light(),
      localizationsDelegates: L10n.localizationsDelegates,
      supportedLocales: L10n.supportedLocales,
      home: TenturaResponsiveScope(
        child: MultiBlocProvider(
          providers: [
            BlocProvider<MyWorkCubit>.value(value: cubit),
            BlocProvider<ProfileCubit>.value(value: _TestProfileCubit()),
            BlocProvider<ScreenCubit>(create: (_) => ScreenCubit.local()),
          ],
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
}

final _close = find.byKey(
  const ValueKey<String>('my-work-obligation-close:offer-receipt'),
);

Future<void> _tapClose(WidgetTester tester) async {
  await tester.tap(_close);
  // Already inside runAsync: this wait is real time for the HTTP fake.
  await Future<void>.delayed(const Duration(milliseconds: 200));
  await tester.pumpAndSettle();
}

void main() {
  setUp(() {
    if (!GetIt.I.isRegistered<Logger>()) {
      GetIt.I.registerSingleton<Logger>(Logger('close-card-wire'));
    }
  });

  tearDown(GetIt.I.reset);

  testWidgets('closing an admitted offer card settles it on the server and '
      'removes the row', (tester) async {
    final server = _Server();
    final sent = <WireSent>[];
    await tester.runAsync(
      () => withRemoteWire({}, sent, (remote) async {
        final cubit = await _cubit(remote);
        await _pumpDesk(tester, cubit);
        expect(find.textContaining('I can sew'), findsOneWidget);

        await _tapClose(tester);

        expect(
          sent.where((r) => r.variables['receiptId'] == 'offer-receipt'),
          hasLength(1),
        );
        expect(find.textContaining('I can sew'), findsNothing);
        expect(
          cubit.state.attentionByBeacon[_beaconId]?.liveObligations ?? const [],
          isEmpty,
        );
      }, responseFor: server.respond),
    );
  });

  testWidgets('a transport error keeps the obligation on the card and says '
      'so', (tester) async {
    final server = _Server();
    final sent = <WireSent>[];
    await tester.runAsync(
      () => withRemoteWire(
        {},
        sent,
        (remote) async {
          final cubit = await _cubit(remote);
          await _pumpDesk(tester, cubit);

          await _tapClose(tester);

          expect(
            sent.where((r) => r.variables['receiptId'] == 'offer-receipt'),
            isNotEmpty,
          );
          expect(find.byType(SnackBar), findsOneWidget);
          expect(find.textContaining('I can sew'), findsOneWidget);
          expect(
            cubit.state.attentionByBeacon[_beaconId]?.liveObligations,
            hasLength(1),
          );
        },
        responseFor: server.respond,
        errors: {'AttentionSettle': wireCodeError(1001)},
      ),
    );
  });

  testWidgets('the block renders nothing once its only obligation is closed', (
    tester,
  ) async {
    final server = _Server();
    final sent = <WireSent>[];
    await tester.runAsync(
      () => withRemoteWire({}, sent, (remote) async {
        final cubit = await _cubit(remote);
        await _pumpDesk(tester, cubit);

        await _tapClose(tester);

        final block = find.byType(MyWorkObligationBlock);
        expect(
          block.evaluate().isEmpty || tester.getSize(block) == Size.zero,
          isTrue,
        );
        expect(find.textContaining('I can sew'), findsNothing);
        expect(_close, findsNothing);
      }, responseFor: server.respond),
    );
  });
}
