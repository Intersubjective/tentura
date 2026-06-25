import 'package:injectable/injectable.dart' show Environment;
import 'package:logging/logging.dart';
import 'package:mockito/mockito.dart';
import 'package:test/test.dart';

import 'package:tentura_server/domain/entity/forward_edge_entity.dart';
import 'package:tentura_server/domain/entity/help_offer_entity.dart';
import 'package:tentura_server/domain/exception.dart';
import 'package:tentura_server/domain/use_case/beacon_involvement_case.dart';
import 'package:tentura_server/env.dart';

import 'forward_case_mocks.mocks.dart';
import '../../support/fake_beacon_access_guard.dart';

void main() {
  late MockForwardEdgeRepositoryPort forwardEdgeRepo;
  late MockHelpOfferRepositoryPort helpOfferRepo;
  late MockInboxRepositoryPort inboxRepo;
  late FakeBeaconAccessGuard guard;
  late BeaconInvolvementCase case_;

  const beaconId = 'Bbeacon';
  const authorId = 'Uauthor';
  const viewerId = 'Uviewer';
  final now = DateTime.utc(2025, 6, 1);

  ForwardEdgeEntity edge({
    required String id,
    required String senderId,
    required String recipientId,
    String note = '',
    DateTime? recipientReadAt,
  }) =>
      ForwardEdgeEntity(
        id: id,
        beaconId: beaconId,
        senderId: senderId,
        recipientId: recipientId,
        createdAt: now,
        note: note,
        recipientReadAt: recipientReadAt,
      );

  HelpOfferEntity helpOffer({
    required String userId,
    int status = 0,
  }) =>
      HelpOfferEntity(
        beaconId: beaconId,
        userId: userId,
        createdAt: now,
        updatedAt: now,
        status: status,
      );

  void stubRepos({
    List<ForwardEdgeEntity> edges = const [],
    List<HelpOfferEntity> helpOffers = const [],
    List<String> rejectedIds = const [],
    List<String> watchingIds = const [],
    List<String> onwardForwarderIds = const [],
  }) {
    when(forwardEdgeRepo.fetchByBeaconId(beaconId))
        .thenAnswer((_) async => edges);
    when(helpOfferRepo.fetchAllByBeaconId(beaconId))
        .thenAnswer((_) async => helpOffers);
    when(inboxRepo.fetchRejectedUserIdsByBeacon(beaconId))
        .thenAnswer((_) async => rejectedIds);
    when(inboxRepo.fetchWatchingUserIdsByBeacon(beaconId))
        .thenAnswer((_) async => watchingIds);
    when(forwardEdgeRepo.fetchDistinctSenderIdsByBeaconId(beaconId))
        .thenAnswer((_) async => onwardForwarderIds);
    when(
      forwardEdgeRepo.markAsRead(any, any),
    ).thenAnswer((_) async {});
  }

  setUp(() {
    forwardEdgeRepo = MockForwardEdgeRepositoryPort();
    helpOfferRepo = MockHelpOfferRepositoryPort();
    inboxRepo = MockInboxRepositoryPort();
    guard = FakeBeaconAccessGuard();
    case_ = BeaconInvolvementCase(
      forwardEdgeRepo,
      helpOfferRepo,
      inboxRepo,
      guard,
      env: Env(environment: Environment.test),
      logger: Logger('BeaconInvolvementCaseTest'),
    );
    stubRepos();
  });

  group('BeaconInvolvementCase.asMap', () {
    test('guard deny -> UnauthorizedException', () async {
      guard.involvementAllowed = false;
      await expectLater(
        case_.asMap(beaconId: beaconId, currentUserId: viewerId),
        throwsA(isA<UnauthorizedException>()),
      );
      verifyNever(forwardEdgeRepo.fetchByBeaconId(any));
    });

    test('empty graph -> all id lists empty', () async {
      final r = await case_.asMap(beaconId: beaconId, currentUserId: viewerId);
      expect(r.forwardedToIds, isEmpty);
      expect(r.helpOfferedIds, isEmpty);
      expect(r.withdrawnIds, isEmpty);
      expect(r.rejectedIds, isEmpty);
      expect(r.watchingIds, isEmpty);
      expect(r.onwardForwarderIds, isEmpty);
      expect(r.myForwardedRecipients, isEmpty);
    });

    test('aggregates forwarded, help, rejected, watching, onward senders',
        () async {
      stubRepos(
        edges: [
          edge(id: 'F1', senderId: authorId, recipientId: 'Ur1'),
          edge(id: 'F2', senderId: 'Usender', recipientId: 'Ur2'),
        ],
        helpOffers: [
          helpOffer(userId: 'Uh1', status: 0),
          helpOffer(userId: 'Uh2', status: 1),
        ],
        rejectedIds: ['Urej1', 'Urej2'],
        watchingIds: ['Uwatch'],
        onwardForwarderIds: ['Usender', authorId],
      );

      final r = await case_.asMap(beaconId: beaconId, currentUserId: viewerId);

      expect(r.forwardedToIds.toSet(), {'Ur1', 'Ur2'});
      expect(r.helpOfferedIds, ['Uh1']);
      expect(r.withdrawnIds, ['Uh2']);
      expect(r.rejectedIds, ['Urej1', 'Urej2']);
      expect(r.watchingIds, ['Uwatch']);
      expect(r.onwardForwarderIds, ['Usender', authorId]);
      expect(r.myForwardedRecipients, isEmpty);
    });

    test('myForwardedRecipients includes only edges sent by current user',
        () async {
      final readAt = DateTime.utc(2025, 6, 2);
      stubRepos(
        edges: [
          edge(
            id: 'Fmine1',
            senderId: viewerId,
            recipientId: 'Ur1',
            note: 'note-a',
          ),
          edge(
            id: 'Fmine2',
            senderId: viewerId,
            recipientId: 'Ur2',
            note: 'note-b',
            recipientReadAt: readAt,
          ),
          edge(id: 'Fother', senderId: authorId, recipientId: 'Ur3'),
        ],
      );

      final r = await case_.asMap(beaconId: beaconId, currentUserId: viewerId);

      expect(r.myForwardedRecipients, hasLength(2));
      expect(r.myForwardedRecipients[0].edgeId, 'Fmine1');
      expect(r.myForwardedRecipients[0].recipientId, 'Ur1');
      expect(r.myForwardedRecipients[0].note, 'note-a');
      expect(r.myForwardedRecipients[0].readAt, isNull);
      expect(r.myForwardedRecipients[1].edgeId, 'Fmine2');
      expect(r.myForwardedRecipients[1].recipientId, 'Ur2');
      expect(r.myForwardedRecipients[1].readAt, readAt);
    });

    test('recipient view marks unread inbound edges as read', () async {
      stubRepos(
        edges: [
          edge(
            id: 'Funread',
            senderId: authorId,
            recipientId: viewerId,
          ),
          edge(
            id: 'Fread',
            senderId: authorId,
            recipientId: viewerId,
            recipientReadAt: now,
          ),
          edge(
            id: 'Fother',
            senderId: authorId,
            recipientId: 'Uother',
          ),
        ],
      );

      await case_.asMap(beaconId: beaconId, currentUserId: viewerId);

      verify(forwardEdgeRepo.markAsRead('Funread', viewerId)).called(1);
      verifyNever(forwardEdgeRepo.markAsRead('Fread', viewerId));
      verifyNever(forwardEdgeRepo.markAsRead('Fother', viewerId));
    });

    test('author view does not mark edges as read', () async {
      stubRepos(
        edges: [
          edge(
            id: 'Fout',
            senderId: 'Uhelper',
            recipientId: 'Ur1',
          ),
        ],
      );

      final r = await case_.asMap(beaconId: beaconId, currentUserId: authorId);

      verifyNever(forwardEdgeRepo.markAsRead(any, any));
      expect(r.myForwardedRecipients, isEmpty);
      expect(r.forwardedToIds, ['Ur1']);
    });
  });
}
