import 'dart:convert';

import 'package:injectable/injectable.dart' show Environment;
import 'package:logging/logging.dart';
import 'package:mockito/mockito.dart';
import 'package:shelf_plus/shelf_plus.dart';
import 'package:test/test.dart';

import 'package:tentura_server/api/controllers/invite_preview_controller.dart';
import 'package:tentura_server/env.dart';

import '../../domain/use_case/invitation_case_mocks.mocks.dart';
import '../../support/build_test_invitation_case.dart';
import '../../support/log_capture.dart';

void main() {
  late MockInvitationRepositoryPort invitationRepo;
  late InvitePreviewController controller;

  setUp(() {
    invitationRepo = MockInvitationRepositoryPort();
    final env = Env(environment: Environment.test);
    controller = InvitePreviewController(
      env,
      buildTestInvitationCase(
        invitationRepo: invitationRepo,
        userRepo: MockUserRepositoryPort(),
        beaconRepo: MockBeaconRepositoryPort(),
        friendshipLookup: MockVoteUserFriendshipLookupPort(),
        contactRepo: MockUserContactRepositoryPort(),
        env: env,
      ),
    );
  });

  Request request({String code = 'Iabc'}) => Request(
    'GET',
    Uri.parse('http://localhost/api/v2/invite/$code/preview'),
    context: {
      'shelf_router/params': {'code': code},
    },
  );

  test('400 without an invite code', () async {
    final r = await controller.handler(request(code: ''));
    expect(r.statusCode, 400);
    verifyZeroInteractions(invitationRepo);
  });

  test('200 with an invalid-code preview for an unknown code', () async {
    when(
      invitationRepo.getById(invitationId: anyNamed('invitationId')),
    ).thenAnswer((_) async => null);
    final log = LogCapture('InvitePreviewController');
    addTearDown(log.cancel);

    final r = await controller.handler(request());

    expect(r.statusCode, 200);
    expect(jsonDecode(await r.readAsString()), isA<Map<String, Object?>>());
    expect(log.records, isEmpty);
  });

  test('500 on an unexpected error, logged first', () async {
    final error = StateError('db down');
    when(
      invitationRepo.getById(invitationId: anyNamed('invitationId')),
    ).thenThrow(error);
    final log = LogCapture('InvitePreviewController');
    addTearDown(log.cancel);

    final r = await controller.handler(request());

    expect(r.statusCode, 500);
    expect(await r.readAsString(), 'Internal Server Error');
    expect(log.records, hasLength(1));
    final record = log.records.single;
    expect(record.level, Level.SEVERE);
    expect(record.message, 'invite.preview failed');
    expect(record.error, same(error));
    expect(record.stackTrace, isNotNull);
  });
}
