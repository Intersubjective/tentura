// Partner card through the real room screen (baton together plan C3): a
// recorded room GraphQL response goes through the repository and a real
// RoomCubit into BeaconRoomBody. Tapping Join / Can't / Can't after all on the
// card sends roomBatonPartnerRespond with the right variables and the card
// then shows the new state.

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
import 'package:tentura_root/domain/entity/beacon_status.dart';

import 'package:tentura/data/repository/clipboard_image_repository.dart';
import 'package:tentura/data/repository/image_repository.dart';
import 'package:tentura/data/service/remote_api_client/remote_api_client_web.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/domain/entity/room_baton_data.dart';
import 'package:tentura/domain/entity/room_message.dart';
import 'package:tentura/features/beacon_threads/data/repository/beacon_threads_repository.dart';
import 'package:tentura/features/beacon_threads/ui/bloc/room_cubit.dart';
import 'package:tentura/features/beacon_threads/ui/widget/beacon_room_body.dart';
import 'package:tentura/features/profile/ui/bloc/profile_cubit.dart';
import 'package:tentura/ui/bloc/presence_cubit.dart';
import 'package:tentura/ui/l10n/l10n.dart';

import '../../support/phone_surface.dart';
import '../../support/test_realtime_sync.dart';
import 'room_cubit_fakes.dart';
import 'support/room_body_harness.dart';

Map<String, dynamic> _partnerMessageRow({
  required String id,
  required String batonDataJson,
}) => {
  '__typename': 'v2_RoomMessageRow',
  'id': id,
  'beaconId': 'Bbeacon0000001',
  'authorId': 'Uauthor000001',
  'body': 'who can pick this up?',
  'createdAt': '2026-10-05T10:00:00.000Z',
  'editedAt': null,
  'semanticMarker': null,
  'systemMessageKind': null,
  'linkedBlockerId': null,
  'linkedFactCardId': null,
  'linkedPollingId': null,
  'linkedItemId': null,
  'linkedEventKind': null,
  'linkedItemKind': null,
  'linkedItemStatus': null,
  'linkedItemTitle': null,
  'linkedItemBody': null,
  'linkedItemCreatorId': null,
  'linkedItemTargetPersonId': null,
  'linkedItemCreatedAt': null,
  'linkedItemUpdatedAt': null,
  'linkedItemLinkedMessageId': null,
  'linkedItemResolvedAt': null,
  'pollDataJson': null,
  'batonDataJson': batonDataJson,
  'systemPayloadJson': null,
  'authorTitle': 'Alice',
  'authorHasPicture': false,
  'authorPicHeight': 0,
  'authorPicWidth': 0,
  'authorBlurHash': '',
  'authorImageId': '',
  'reactionsJson': null,
  'myReaction': null,
  'reactorsJson': null,
  'attachmentsJson': '[]',
  'mentions': <String>[],
  'mentionSpansJson': '[]',
  'replyToAuthorId': null,
  'replyToAuthorTitle': null,
  'replyToBodyExcerpt': null,
  'replyToHasAttachments': false,
  'replyToMessageId': null,
  'threadItemId': null,
  'quotedFact': null,
};

String _batonJson(List<(String id, String title, String status)> invites) =>
    '{"id":"Zbaton000001","status":"collecting","viewerRole":"partner",'
    '"partnerInvites":[${[for (final (id, title, status) in invites) '{"fromUserId":"$id","title":"$title","status":"$status"}'].join(',')}]}';

const _anna = 'Uaaaaaaaaaaa';
const _boris = 'Ubbbbbbbbbbb';

/// Plays the server: the room list serves [current], and a partner answer
/// replaces it with [afterAnswer] (what a refetch would then show).
class _ServerLink extends Link {
  _ServerLink({required this.current, required this.afterAnswer});

  String current;
  final String afterAnswer;
  final requests = <Request>[];

  List<Request> get answers => [
    for (final r in requests)
      if (r.operation.operationName == 'RoomBatonPartnerRespond') r,
  ];

  @override
  Stream<Response> request(Request request, [NextLink? forward]) {
    requests.add(request);
    if (request.operation.operationName == 'RoomBatonPartnerRespond') {
      current = afterAnswer;
      return Stream.value(
        Response(
          data: {
            '__typename': 'mutation_root',
            'roomBatonPartnerRespond': afterAnswer,
          },
          response: const {},
        ),
      );
    }
    return Stream.value(
      Response(
        data: {
          '__typename': 'query_root',
          'RoomMessageList': [
            _partnerMessageRow(id: 'Mbaton0000001', batonDataJson: current),
          ],
        },
        response: const {},
      ),
    );
  }
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

BeaconThreadsRepository _repositoryFor(Link link) {
  final realtime = buildTestRealtimeSync();
  addTearDown(realtime.port.dispose);
  return BeaconThreadsRepository(
    _StubRemoteApiClient(
      Client(
        link: link,
        defaultFetchPolicies: const {
          OperationType.query: FetchPolicy.NoCache,
          OperationType.mutation: FetchPolicy.NoCache,
        },
      ),
    ),
    realtime.port,
  );
}

/// Room reads and partner answers go over the recorded wire; the rest is the
/// usual fake.
class _WireBackedRoomFake extends FakeBeaconThreadsRepository {
  _WireBackedRoomFake({required super.userId, required this.wireRepo});

  final BeaconThreadsRepository wireRepo;

  @override
  Future<List<RoomMessage>> fetchMessages({
    required String beaconId,
    String? beforeIso,
    String? threadItemId,
  }) => wireRepo.fetchMessages(
    beaconId: beaconId,
    beforeIso: beforeIso,
    threadItemId: threadItemId,
  );

  @override
  Future<RoomBatonData?> batonPartnerRespond({
    required String batonId,
    required String inviterUserId,
    required bool accept,
  }) => wireRepo.batonPartnerRespond(
    batonId: batonId,
    inviterUserId: inviterUserId,
    accept: accept,
  );
}

const _viewer = Profile(id: kRoomCubitFakeMyUserId, displayName: 'Viewer');

/// Pumps the real room screen over the recorded wire; returns the link.
Future<_ServerLink> _pumpRoom(
  WidgetTester tester, {
  required String current,
  required String afterAnswer,
}) async {
  await usePhoneSurface(tester);
  await GetIt.I.reset();
  addTearDown(GetIt.I.reset);
  registerRoomCubitProfileCubit(kRoomCubitFakeMyUserId);
  GetIt.I
    ..registerSingleton<ImageRepository>(ImageRepository())
    ..registerSingleton<ClipboardImageRepository>(ClipboardImageRepository());
  final link = _ServerLink(current: current, afterAnswer: afterAnswer);
  final fake = _WireBackedRoomFake(
    userId: kRoomCubitFakeMyUserId,
    wireRepo: _repositoryFor(link),
  );
  late RoomCubit cubit;
  await tester.runAsync(() async {
    cubit = roomCubitForTest(fake);
    await awaitRoomCubitLoad(cubit).timeout(const Duration(seconds: 5));
    cubit.syncBeaconStatus(BeaconStatus.open);
  });
  addTearDown(() => tester.runAsync(cubit.close));
  await tester.pumpWidget(
    MultiBlocProvider(
      providers: [
        BlocProvider<RoomCubit>.value(value: cubit),
        BlocProvider<ProfileCubit>.value(
          value: RoomBodyHarnessProfileCubit(_viewer),
        ),
        BlocProvider<PresenceCubit>.value(
          value: RoomBodyHarnessPresenceCubit(),
        ),
      ],
      child: MaterialApp(
        locale: const Locale('en'),
        theme: TenturaTheme.light(),
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        home: const TenturaResponsiveScope(
          child: Scaffold(body: BeaconRoomBody()),
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
  return link;
}

Future<void> _tapAndSettle(WidgetTester tester, Finder target) async {
  await tester.tap(target);
  // The bubble's gesture arena resolves a tap after the double-tap window.
  await tester.pump(const Duration(milliseconds: 400));
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 200)),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
}

String _prompt(String name) => '$name wants to take this on together with you.';

/// The «Join» that sits in the same card block as [prompt]: the nearest
/// ancestor of the prompt that holds a Join holds exactly one.
Finder _joinOwnedBy(WidgetTester tester, String prompt) {
  Finder? owner;
  tester.element(find.text(prompt)).visitAncestorElements((e) {
    final scope = find.byElementPredicate((x) => identical(x, e));
    if (find
        .descendant(of: scope, matching: find.text('Join'))
        .evaluate()
        .isNotEmpty) {
      owner = find.descendant(of: scope, matching: find.text('Join'));
      return false;
    }
    return true;
  });
  final join = owner;
  expect(join, isNotNull, reason: 'no Join near "$prompt"');
  expect(join, findsOneWidget, reason: 'Join shared between prompts');
  return join!;
}

void main() {
  group('Partner card on the room screen', () {
    testWidgets('shows the prompt from the recorded response', (tester) async {
      await _pumpRoom(
        tester,
        current: _batonJson([(_anna, 'Anna', 'pending')]),
        afterAnswer: _batonJson([(_anna, 'Anna', 'accepted')]),
      );
      expect(find.text(_prompt('Anna')), findsOneWidget);
    });

    testWidgets('Join sends the answer and shows the joined copy', (
      tester,
    ) async {
      final link = await _pumpRoom(
        tester,
        current: _batonJson([(_anna, 'Anna', 'pending')]),
        afterAnswer: _batonJson([(_anna, 'Anna', 'accepted')]),
      );
      expect(find.text(_prompt('Anna')), findsOneWidget);

      await _tapAndSettle(tester, find.text('Join'));

      expect(link.answers, hasLength(1));
      final vars = link.answers.single.variables;
      expect(vars['batonId'], 'Zbaton000001');
      expect(vars['inviterUserId'], _anna);
      expect(vars['accept'], isTrue);
      expect(
        find.text(
          "You'll take it together with Anna. "
          "You can change your mind while it's open.",
        ),
        findsOneWidget,
      );
      expect(find.text('Join'), findsNothing);
    });

    testWidgets("Can't sends a decline", (tester) async {
      final link = await _pumpRoom(
        tester,
        current: _batonJson([(_anna, 'Anna', 'pending')]),
        afterAnswer: _batonJson([(_anna, 'Anna', 'pending')]),
      );
      expect(find.text(_prompt('Anna')), findsOneWidget);

      await _tapAndSettle(tester, find.text("Can't"));

      expect(link.answers, hasLength(1));
      final vars = link.answers.single.variables;
      expect(vars['batonId'], 'Zbaton000001');
      expect(vars['inviterUserId'], _anna);
      expect(vars['accept'], isFalse);
    });

    testWidgets("Can't after all withdraws a joined answer", (tester) async {
      final link = await _pumpRoom(
        tester,
        current: _batonJson([(_anna, 'Anna', 'accepted')]),
        afterAnswer: _batonJson([(_anna, 'Anna', 'pending')]),
      );
      expect(find.text("Can't after all"), findsOneWidget);

      await _tapAndSettle(tester, find.text("Can't after all"));

      expect(link.answers, hasLength(1));
      final vars = link.answers.single.variables;
      expect(vars['inviterUserId'], _anna);
      expect(vars['accept'], isFalse);
    });

    testWidgets('Join under the second invite answers that inviter', (
      tester,
    ) async {
      final link = await _pumpRoom(
        tester,
        current: _batonJson([
          (_anna, 'Anna', 'pending'),
          (_boris, 'Boris', 'pending'),
        ]),
        afterAnswer: _batonJson([
          (_anna, 'Anna', 'pending'),
          (_boris, 'Boris', 'accepted'),
        ]),
      );
      expect(find.text(_prompt('Anna')), findsOneWidget);
      expect(find.text(_prompt('Boris')), findsOneWidget);

      await _tapAndSettle(tester, _joinOwnedBy(tester, _prompt('Boris')));

      expect(link.answers, hasLength(1));
      final vars = link.answers.single.variables;
      expect(vars['inviterUserId'], _boris);
      expect(vars['accept'], isTrue);
    });
  });
}
