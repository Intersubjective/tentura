import 'package:injectable/injectable.dart' show Environment;
import 'package:logging/logging.dart';
import 'package:mockito/mockito.dart';
import 'package:test/test.dart';

import 'package:tentura_server/domain/exception.dart';
import 'package:tentura_server/domain/exception_codes.dart';
import 'package:tentura_server/domain/use_case/capability_routing_case.dart';
import 'package:tentura_server/env.dart';

import 'capability_routing_case_mocks.mocks.dart';

void main() {
  late MockCapabilityEvidencePort capabilityEvidence;
  late MockRoutingMutePort routingMute;
  late CapabilityRoutingCase case_;

  const actor = 'alice';
  const subject = 'carol';
  const beaconId = 'B_fixture';
  const slug = 'transport';

  CapabilityRoutingCase buildCase() => CapabilityRoutingCase(
        capabilityEvidence,
        routingMute,
        env: Env(environment: Environment.test),
        logger: Logger('CapabilityRoutingCaseTest'),
      );

  setUp(() {
    capabilityEvidence = MockCapabilityEvidencePort();
    routingMute = MockRoutingMutePort();
    case_ = buildCase();
  });

  group('revokeAcknowledgement', () {
    test('calls revoke with actor as observer', () async {
      await case_.revokeAcknowledgement(
        actorId: actor,
        beaconId: beaconId,
        subjectId: subject,
        slug: slug,
      );

      verify(
        capabilityEvidence.revokeOutcomeEvidence(
          beaconId: beaconId,
          observerId: actor,
          subjectId: subject,
          slug: slug,
        ),
      ).called(1);
    });

    test('is a safe no-op when actor was never the observer', () async {
      await case_.revokeAcknowledgement(
        actorId: 'eve',
        beaconId: beaconId,
        subjectId: subject,
        slug: slug,
      );

      verify(
        capabilityEvidence.revokeOutcomeEvidence(
          beaconId: beaconId,
          observerId: 'eve',
          subjectId: subject,
          slug: slug,
        ),
      ).called(1);
    });

    test('is not blocked when actor and subject have a block', () async {
      await case_.revokeAcknowledgement(
        actorId: actor,
        beaconId: beaconId,
        subjectId: subject,
        slug: slug,
      );

      verify(
        capabilityEvidence.revokeOutcomeEvidence(
          beaconId: beaconId,
          observerId: actor,
          subjectId: subject,
          slug: slug,
        ),
      ).called(1);
      verifyNever(
        routingMute.setMute(
          userId: anyNamed('userId'),
          tagSlug: anyNamed('tagSlug'),
          muted: anyNamed('muted'),
        ),
      );
    });
  });

  group('myRoutingTags', () {
    test('fetches mutes for the actor only', () async {
      when(routingMute.mutedSlugsForUser(actor)).thenAnswer(
        (_) async => {'transport'},
      );

      final muted = await case_.myRoutingTags(actorId: actor);

      expect(muted, {'transport'});
      verify(routingMute.mutedSlugsForUser(actor)).called(1);
      verifyNever(routingMute.mutedSlugsForUser('carol'));
    });
  });

  group('setRoutingMute', () {
    test('writes mute for the actor only', () async {
      await case_.setRoutingMute(
        actorId: actor,
        slug: slug,
        muted: true,
      );

      verify(
        routingMute.setMute(
          userId: actor,
          tagSlug: slug,
          muted: true,
        ),
      ).called(1);
    });

    test('rejects an unknown slug', () async {
      await expectLater(
        case_.setRoutingMute(
          actorId: actor,
          slug: 'not_a_real_slug',
          muted: true,
        ),
        throwsA(
          isA<ExceptionBase>().having(
            (e) => (e.code as CapabilityExceptionCodes).exceptionCode,
            'code',
            CapabilityExceptionCode.invalidSlug,
          ),
        ),
      );
      verifyNever(
        routingMute.setMute(
          userId: anyNamed('userId'),
          tagSlug: anyNamed('tagSlug'),
          muted: anyNamed('muted'),
        ),
      );
    });
  });
}
