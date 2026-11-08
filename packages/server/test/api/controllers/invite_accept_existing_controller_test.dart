import 'dart:convert';

import 'package:injectable/injectable.dart' show Environment;
import 'package:logging/logging.dart';
import 'package:mockito/mockito.dart';
import 'package:shelf_plus/shelf_plus.dart';
import 'package:test/test.dart';

import 'package:tentura_server/api/controllers/invite_accept_existing_controller.dart';
import 'package:tentura_server/domain/entity/invitation_entity.dart';
import 'package:tentura_server/domain/entity/jwt_entity.dart';
import 'package:tentura_server/domain/entity/user_entity.dart';
import 'package:tentura_server/env.dart';

import '../../domain/use_case/invitation_case_mocks.mocks.dart';
import '../../support/build_test_invitation_case.dart';
import '../../support/log_capture.dart';

const _issuerId = 'Uissuer';

void main() {
  late MockInvitationRepositoryPort invitationRepo;
  late MockUserRepositoryPort userRepo;
  late MockVoteUserFriendshipLookupPort friendshipLookup;
  late InviteAcceptExistingController controller;

  setUp(() {
    invitationRepo = MockInvitationRepositoryPort();
    userRepo = MockUserRepositoryPort();
    friendshipLookup = MockVoteUserFriendshipLookupPort();
    final env = Env(environment: Environment.test);
    controller = InviteAcceptExistingController(
      env,
      buildTestInvitationCase(
        invitationRepo: invitationRepo,
        userRepo: userRepo,
        beaconRepo: MockBeaconRepositoryPort(),
        friendshipLookup: friendshipLookup,
        contactRepo: MockUserContactRepositoryPort(),
        env: env,
      ),
    );
    when(
      friendshipLookup.isReciprocalSubscribe(
        viewerId: anyNamed('viewerId'),
        peerId: anyNamed('peerId'),
      ),
    ).thenAnswer((_) async => false);
  });

  void stubInvitation(InvitationEntity? invitation) => when(
    invitationRepo.getById(invitationId: anyNamed('invitationId')),
  ).thenAnswer((_) async => invitation);

  InvitationEntity invitation() {
    final now = DateTime.now();
    return InvitationEntity(
      id: 'Iabc',
      issuer: const UserEntity(id: _issuerId, displayName: 'Alice'),
      createdAt: now,
      updatedAt: now,
    );
  }

  Request request({String code = 'Iabc', String? userId = 'Ujoiner'}) =>
      Request(
        'POST',
        Uri.parse('http://localhost/api/v2/invite/$code/accept-as-existing'),
        context: {
          'shelf_router/params': {'code': code},
          if (userId != null) kContextJwtKey: JwtEntity(sub: userId),
        },
      );

  test('400 without an invite code', () async {
    final r = await controller.handler(request(code: ''));
    expect(r.statusCode, 400);
    verifyZeroInteractions(invitationRepo);
  });

  for (final userId in [null, '']) {
    test('401 without a usable jwt sub ($userId)', () async {
      final r = await controller.handler(request(userId: userId));
      expect(r.statusCode, 401);
      verifyZeroInteractions(invitationRepo);
    });
  }

  test('404 with the exception body for an unknown code', () async {
    stubInvitation(null);
    final r = await controller.handler(request());
    expect(r.statusCode, 404);
    expect(r.headers['content-type'], 'application/json');
    expect(jsonDecode(await r.readAsString()), isA<Map<String, Object?>>());
  });

  test('400 with the exception body for a self-invite', () async {
    stubInvitation(invitation());
    final r = await controller.handler(request(userId: _issuerId));
    expect(r.statusCode, 400);
    expect(r.headers['content-type'], 'application/json');
    expect(
      await r.readAsString(),
      contains('Cannot accept your own invite'),
    );
  });

  test('200 {ok: true} when already friends (retry-safe)', () async {
    stubInvitation(invitation());
    when(
      friendshipLookup.isReciprocalSubscribe(
        viewerId: 'Ujoiner',
        peerId: _issuerId,
      ),
    ).thenAnswer((_) async => true);

    final r = await controller.handler(request());

    expect(r.statusCode, 200);
    expect(jsonDecode(await r.readAsString()), {'ok': true});
    verifyNever(
      userRepo.bindMutual(
        invitationId: anyNamed('invitationId'),
        userId: anyNamed('userId'),
      ),
    );
  });

  test('400 with the exception body is not logged', () async {
    stubInvitation(invitation());
    final log = LogCapture('InviteAcceptExistingController');
    addTearDown(log.cancel);

    final r = await controller.handler(request(userId: _issuerId));

    expect(r.statusCode, 400);
    expect(log.records, isEmpty);
  });

  test('500 on an unexpected error, logged first', () async {
    final error = StateError('db down');
    when(
      invitationRepo.getById(invitationId: anyNamed('invitationId')),
    ).thenThrow(error);
    final log = LogCapture('InviteAcceptExistingController');
    addTearDown(log.cancel);

    final r = await controller.handler(request());

    expect(r.statusCode, 500);
    expect(await r.readAsString(), 'Internal Server Error');
    expect(log.records, hasLength(1));
    final record = log.records.single;
    expect(record.level, Level.SEVERE);
    expect(record.message, 'invite.acceptExisting failed');
    expect(record.error, same(error));
    expect(record.stackTrace, isNotNull);
  });
}
