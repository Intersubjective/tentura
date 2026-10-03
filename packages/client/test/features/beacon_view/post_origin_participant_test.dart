import 'package:ferry/ferry.dart'
    show
        Client,
        FetchPolicy,
        Link,
        NextLink,
        OperationRequest,
        OperationResponse,
        OperationType;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gql_exec/gql_exec.dart' show Request, Response;
import 'package:mockito/mockito.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';

import 'package:tentura/data/service/remote_api_client/remote_api_client_web.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/beacon_participant.dart';
import 'package:tentura/domain/entity/beacon_room_consts.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/beacon_threads/data/repository/beacon_threads_repository.dart';
import 'package:tentura/features/beacon_view/ui/bloc/beacon_view_cubit.dart';
import 'package:tentura/features/beacon_view/ui/dialog/help_offer_message_dialog.dart';
import 'package:tentura/features/beacon_view/ui/widget/beacon_operational_header_card.dart';
import 'package:tentura/features/beacon_view/ui/widget/beacon_people_tab_body.dart';
import 'package:tentura/features/post_view/data/repository/post_membership_repository.dart';
import 'package:tentura/features/profile/ui/bloc/profile_cubit.dart';
import 'package:tentura/ui/bloc/screen_cubit.dart';
import 'package:tentura/ui/l10n/l10n.dart';

import '../../support/test_realtime_sync.dart';
import '../../ui/effect/fake_ui_effect_port.dart';
import 'beacon_view_case_test_support.dart';
import 'beacon_view_initial_load_test.dart' show pumpUntil;
import 'beacon_view_screen_harness.dart';

class _MockProfileCubit extends Mock implements ProfileCubit {
  _MockProfileCubit(this.profile);

  final Profile profile;

  @override
  ProfileState get state => ProfileState(profile: profile);

  @override
  Stream<ProfileState> get stream => Stream<ProfileState>.value(state);
}

class _MockBeaconViewCubit extends Mock implements BeaconViewCubit {
  _MockBeaconViewCubit(this._state);

  final BeaconViewState _state;

  @override
  BeaconViewState get state => _state;

  @override
  Stream<BeaconViewState> get stream => Stream<BeaconViewState>.value(_state);

  @override
  Future<void> loadForwards() async {}
}

/// Records `postLeave` / `postReturn`; any other member throws (no stub).
class _RecordingMembershipRepository implements PostMembershipRepository {
  final postLeaveCalls = <String>[];

  @override
  Future<void> postLeave(String beaconId) async {
    postLeaveCalls.add(beaconId);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeLink extends Link {
  _FakeLink(this.response);

  final Response response;

  @override
  Stream<Response> request(Request request, [NextLink? forward]) =>
      Stream.value(response);
}

final class _StubRemoteApiClient extends RemoteApiClient {
  _StubRemoteApiClient(this._client)
    : super(
        apiEndpointUrl: 'http://test/graphql',
        apiEndpointUrlV2: 'http://test/api/v2/graphql',
        authJwtExpiresIn: const Duration(hours: 1),
        requestTimeout: const Duration(minutes: 1),
        userAgent: 'test',
      );

  final Client _client;

  @override
  Stream<OperationResponse<TData, TVars>> request<TData, TVars>(
    OperationRequest<TData, TVars> request, [
    Stream<OperationResponse<TData, TVars>> Function(
      OperationRequest<TData, TVars>,
    )?
    forward,
  ]) => _client.request(request);
}

final _t = DateTime.utc(2026, 10);
const _author = Profile(id: 'uAuthor', displayName: 'Author');
const _viewer = Profile(id: 'uViewer', displayName: 'Viewer');

// Russian copy is pinned verbatim from the Post mockups (M8).
const _cardTitle = 'Участник из поста';
const _leaveChat = 'Выйти из чата';
const _peopleSectionTitle = 'ИЗ ПОСТА';

BeaconParticipant _participant(
  String userId,
  String title, {
  int role = BeaconParticipantRoleBits.addressee,
  int roomAccess = RoomAccessBits.admitted,
}) => BeaconParticipant(
  id: 'p-$userId',
  beaconId: 'b1',
  userId: userId,
  role: role,
  status: 0,
  roomAccess: roomAccess,
  createdAt: _t,
  updatedAt: _t,
  userTitle: title,
);

BeaconViewState _state({
  required Profile me,
  List<BeaconParticipant> participants = const [],
}) => BeaconViewState(
  beacon: Beacon(
    id: 'b1',
    title: 'Saturday bike ride',
    author: _author,
    createdAt: _t,
    updatedAt: _t,
  ),
  myProfile: me,
  roomParticipants: participants,
  roomParticipantsLoaded: true,
  beaconContextLoaded: true,
);

Widget _wrap(Profile me, BeaconViewState state, Widget child) => MaterialApp(
  theme: TenturaTheme.light(),
  localizationsDelegates: L10n.localizationsDelegates,
  supportedLocales: L10n.supportedLocales,
  locale: const Locale('ru'),
  home: MultiBlocProvider(
    providers: [
      BlocProvider<ProfileCubit>.value(value: _MockProfileCubit(me)),
      BlocProvider<ScreenCubit>(create: (_) => ScreenCubit.local()),
      BlocProvider<BeaconViewCubit>.value(value: _MockBeaconViewCubit(state)),
    ],
    child: TenturaResponsiveScope(child: Scaffold(body: child)),
  ),
);

Future<void> _pumpHeader(
  WidgetTester tester,
  BeaconViewState state, {
  VoidCallback? onOfferHelp,
  VoidCallback? onLeavePostChat,
}) async {
  await tester.pumpWidget(
    _wrap(
      state.myProfile,
      state,
      SingleChildScrollView(
        child: BeaconOperationalHeaderCard(
          state: state,
          onAuthorTap: () {},
          onOfferHelp: onOfferHelp,
          onLeavePostChat: onLeavePostChat,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _pumpPeople(WidgetTester tester, BeaconViewState state) async {
  // The tab body is a plain Column; give it room so layout never overflows.
  await tester.binding.setSurfaceSize(const Size(800, 3000));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    _wrap(
      state.myProfile,
      state,
      BeaconPeopleTabBody(
        state: state,
        beaconViewCubit: _MockBeaconViewCubit(state),
        l10n: lookupL10n(const Locale('ru')),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Finder _textIgnoringCase(String text) => find.byWidgetPredicate(
  (w) => w is Text && (w.data ?? '').toUpperCase().contains(text.toUpperCase()),
);

void main() {
  final offerHelpLabel = lookupL10n(const Locale('ru')).labelOfferHelp;

  group('Post-origin participant on the Request header', () {
    testWidgets('an addressee in the chat sees the card with both actions', (
      tester,
    ) async {
      final state = _state(
        me: _viewer,
        participants: [_participant(_viewer.id, 'Viewer')],
      );

      await _pumpHeader(
        tester,
        state,
        onOfferHelp: () {},
        onLeavePostChat: () {},
      );

      expect(_textIgnoringCase(_cardTitle), findsOneWidget);
      expect(find.text(_leaveChat), findsOneWidget);
      expect(find.text(offerHelpLabel), findsWidgets);
    });

    testWidgets('the card offers help through the existing offer flow', (
      tester,
    ) async {
      var offerHelpTaps = 0;
      final state = _state(
        me: _viewer,
        participants: [_participant(_viewer.id, 'Viewer')],
      );

      await _pumpHeader(
        tester,
        state,
        onOfferHelp: () => offerHelpTaps++,
        onLeavePostChat: () {},
      );
      expect(_textIgnoringCase(_cardTitle), findsOneWidget);
      await tester.tap(find.text(offerHelpLabel));

      expect(offerHelpTaps, 1);
    });

    testWidgets('the card offers leaving the chat', (tester) async {
      var leaveTaps = 0;
      final state = _state(
        me: _viewer,
        participants: [_participant(_viewer.id, 'Viewer')],
      );

      await _pumpHeader(
        tester,
        state,
        onOfferHelp: () {},
        onLeavePostChat: () => leaveTaps++,
      );
      await tester.tap(find.text(_leaveChat));

      expect(leaveTaps, 1);
    });

    testWidgets('a helper does not see the participant card', (tester) async {
      final state = _state(
        me: _viewer,
        participants: [
          _participant(
            _viewer.id,
            'Viewer',
            role: BeaconParticipantRoleBits.helper,
          ),
        ],
      );

      await _pumpHeader(
        tester,
        state,
        onOfferHelp: () {},
        onLeavePostChat: () {},
      );

      expect(_textIgnoringCase(_cardTitle), findsNothing);
      expect(find.text(_leaveChat), findsNothing);
    });

    testWidgets('an addressee who already left the chat gets no card', (
      tester,
    ) async {
      final state = _state(
        me: _viewer,
        participants: [
          _participant(_viewer.id, 'Viewer', roomAccess: RoomAccessBits.left),
        ],
      );

      await _pumpHeader(
        tester,
        state,
        onOfferHelp: () {},
        onLeavePostChat: () {},
      );

      expect(_textIgnoringCase(_cardTitle), findsNothing);
      expect(find.text(_leaveChat), findsNothing);
    });

    testWidgets('the author does not see the participant card', (tester) async {
      final state = _state(
        me: _author,
        participants: [_participant('uMaria', 'Maria')],
      );

      await _pumpHeader(tester, state, onLeavePostChat: () {});

      expect(_textIgnoringCase(_cardTitle), findsNothing);
      expect(find.text(_leaveChat), findsNothing);
    });
  });

  group('Post-origin section of the author People tab', () {
    testWidgets('lists addressees in the chat under a from-post section', (
      tester,
    ) async {
      final state = _state(
        me: _author,
        participants: [
          _participant('uMaria', 'Maria'),
          _participant('uDima', 'Dima'),
        ],
      );

      await _pumpPeople(tester, state);

      expect(_textIgnoringCase('$_peopleSectionTitle · 2'), findsOneWidget);
      expect(find.text('Maria'), findsOneWidget);
      expect(find.text('Dima'), findsOneWidget);
    });

    testWidgets('counts only addressees when helpers and the author are in '
        'the room too', (tester) async {
      final state = _state(
        me: _author,
        participants: [
          _participant(
            _author.id,
            'Author',
            role: BeaconParticipantRoleBits.author,
          ),
          _participant(
            'uHelper',
            'Helper',
            role: BeaconParticipantRoleBits.helper,
          ),
          _participant('uMaria', 'Maria'),
          _participant('uDima', 'Dima'),
        ],
      );

      await _pumpPeople(tester, state);

      expect(_textIgnoringCase('$_peopleSectionTitle · 2'), findsOneWidget);
      expect(find.text('Maria'), findsOneWidget);
      expect(find.text('Dima'), findsOneWidget);
    });

    testWidgets('omits the section when nobody is an addressee', (
      tester,
    ) async {
      final state = _state(
        me: _author,
        participants: [
          _participant(
            'uHelper',
            'Helper',
            role: BeaconParticipantRoleBits.helper,
          ),
        ],
      );

      await _pumpPeople(tester, state);

      expect(_textIgnoringCase(_peopleSectionTitle), findsNothing);
    });

    testWidgets('leaves out addressees who left the chat', (tester) async {
      final state = _state(
        me: _author,
        participants: [
          _participant('uMaria', 'Maria'),
          _participant('uDima', 'Dima', roomAccess: RoomAccessBits.left),
        ],
      );

      await _pumpPeople(tester, state);

      expect(_textIgnoringCase('$_peopleSectionTitle · 1'), findsOneWidget);
      expect(find.text('Dima'), findsNothing);
    });
  });

  group('Post-origin participant on the Request screen', () {
    const beaconId = 'Bpostorigin01';
    const viewerId = 'Uviewer';

    BeaconViewCubit buildCubit({
      required List<BeaconParticipant> participants,
      required _RecordingMembershipRepository membership,
    }) {
      final beaconRepo = TrackingBeaconRepository()
        ..fetchByIdHandler = (_) async => Beacon(
          id: beaconId,
          title: 'Saturday bike ride',
          createdAt: _t,
          updatedAt: _t,
          status: BeaconStatus.open,
          canReadContent: true,
          author: _author,
        );
      final case_ = buildTestBeaconViewCase(
        beaconRepo: beaconRepo,
        roomRepo: FakeBeaconViewRoomRepository(participants: participants),
      );
      final cubit = BeaconViewCubit(
        id: beaconId,
        myProfile: _viewer.copyWith(id: viewerId),
        beaconViewCase: case_,
        effects: FakeUiEffectPort(),
        postMembershipRepository: membership,
      );
      addTearDown(cubit.close);
      return cubit;
    }

    Future<void> pumpScreen(
      WidgetTester tester,
      BeaconViewCubit cubit,
    ) async {
      final viewer = _viewer.copyWith(id: viewerId);
      await pumpBeaconViewHarness(
        tester,
        size: kBeaconViewHarnessCompact,
        beaconState: BeaconViewState(
          beacon: Beacon(
            id: beaconId,
            title: 'Saturday bike ride',
            author: _author,
            createdAt: _t,
            updatedAt: _t,
          ),
          myProfile: viewer,
        ),
        threadsState: beaconViewHarnessThreadsState(authorId: viewerId),
        beaconViewCubit: cubit,
        locale: const Locale('ru'),
      );
      for (var i = 0; i < 40 && !cubit.state.beaconContextLoaded; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      expect(cubit.state.beaconContextLoaded, isTrue);
      await tester.pumpAndSettle();
    }

    testWidgets(
      'a role-6 viewer loaded through the room API sees the card with both '
      'actions',
      (tester) async {
        final cubit = buildCubit(
          participants: [_participant(viewerId, 'Viewer')],
          membership: _RecordingMembershipRepository(),
        );

        await pumpScreen(tester, cubit);

        expect(
          cubit.state.roomParticipants.single.role,
          BeaconParticipantRoleBits.addressee,
        );
        expect(_textIgnoringCase(_cardTitle), findsOneWidget);
        expect(find.text(_leaveChat), findsOneWidget);
        expect(find.text(offerHelpLabel), findsWidgets);
      },
    );

    testWidgets('a helper viewer sees no card on the screen', (tester) async {
      final cubit = buildCubit(
        participants: [
          _participant(
            viewerId,
            'Viewer',
            role: BeaconParticipantRoleBits.helper,
          ),
        ],
        membership: _RecordingMembershipRepository(),
      );

      await pumpScreen(tester, cubit);

      expect(_textIgnoringCase(_cardTitle), findsNothing);
      expect(find.text(_leaveChat), findsNothing);
    });

    testWidgets('tapping leave chat sends postLeave for this Request', (
      tester,
    ) async {
      final membership = _RecordingMembershipRepository();
      final cubit = buildCubit(
        participants: [_participant(viewerId, 'Viewer')],
        membership: membership,
      );

      await pumpScreen(tester, cubit);
      await tester.tap(find.text(_leaveChat));
      await tester.pumpAndSettle();

      expect(membership.postLeaveCalls, [beaconId]);
    });

    testWidgets('tapping offer help opens the existing offer dialog', (
      tester,
    ) async {
      final cubit = buildCubit(
        participants: [_participant(viewerId, 'Viewer')],
        membership: _RecordingMembershipRepository(),
      );

      await pumpScreen(tester, cubit);
      expect(_textIgnoringCase(_cardTitle), findsOneWidget);
      await tester.tap(find.text(offerHelpLabel).first);
      await tester.pumpAndSettle();

      expect(find.byType(HelpOfferMessageDialog), findsOneWidget);
    });
  });

  group('BeaconViewCubit.leavePostChat', () {
    test('sends postLeave for its Request and nothing else', () async {
      const beaconId = 'Bpostorigin02';
      final membership = _RecordingMembershipRepository();
      final beaconRepo = TrackingBeaconRepository()
        ..fetchByIdHandler = (_) async => Beacon(
          id: beaconId,
          title: 'T',
          createdAt: _t,
          updatedAt: _t,
          status: BeaconStatus.open,
          canReadContent: true,
          author: _author,
        );
      final cubit = BeaconViewCubit(
        id: beaconId,
        myProfile: _viewer,
        beaconViewCase: buildTestBeaconViewCase(beaconRepo: beaconRepo),
        effects: FakeUiEffectPort(),
        postMembershipRepository: membership,
      );
      addTearDown(cubit.close);
      await pumpUntil(cubit.stream, () => cubit.state.beaconContextLoaded);

      await cubit.leavePostChat();

      expect(membership.postLeaveCalls, [beaconId]);
    });
  });

  group('Room participant mapping of the addressee role', () {
    test(
      'fetchParticipants keeps role 6 and room access from the wire',
      () async {
        const beaconId = 'Bpostorigin03';
        final client = Client(
          link: _FakeLink(
            const Response(
              data: {
                '__typename': 'query_root',
                'BeaconParticipantList': [
                  {
                    '__typename': 'v2_BeaconParticipantRow',
                    'id': 'p1',
                    'beaconId': beaconId,
                    'userId': 'Umaria',
                    'userTitle': 'Maria',
                    'userHandle': null,
                    'userHasPicture': false,
                    'userPicHeight': 0,
                    'userPicWidth': 0,
                    'userBlurHash': '',
                    'userImageId': '',
                    'role': 6,
                    'status': 0,
                    'roomAccess': 3,
                    'offerNote': null,
                    'nextMoveText': null,
                    'nextMoveStatus': null,
                    'nextMoveSource': null,
                    'linkedMessageId': null,
                    'lastSeenRoomAt': null,
                    'helpType': null,
                    'roleLabel': null,
                    'createdAt': '2026-10-01T10:00:00.000Z',
                    'updatedAt': '2026-10-01T10:00:00.000Z',
                  },
                ],
              },
              response: {},
            ),
          ),
          defaultFetchPolicies: const {
            OperationType.query: FetchPolicy.NoCache,
          },
        );
        final realtime = buildTestRealtimeSync();
        addTearDown(realtime.port.dispose);
        final repo = BeaconThreadsRepository(
          _StubRemoteApiClient(client),
          realtime.port,
        );

        final rows = await repo.fetchParticipants(beaconId);

        expect(rows.single.role, BeaconParticipantRoleBits.addressee);
        expect(rows.single.roomAccess, RoomAccessBits.admitted);
      },
    );
  });
}
