import 'package:injectable/injectable.dart';

import 'package:tentura_server/domain/capability/capability_slug_validation.dart';
import 'package:tentura_server/domain/capability/capability_tag.dart';
import 'package:tentura_server/domain/exception.dart';
import 'package:tentura_server/domain/exception_codes.dart';
import 'package:tentura_server/domain/port/capability_evidence_port.dart';
import 'package:tentura_server/domain/port/routing_mute_port.dart';

import '_use_case_base.dart';

@Singleton(order: 2)
final class CapabilityRoutingCase extends UseCaseBase {
  CapabilityRoutingCase(
    this._capabilityEvidence,
    this._routingMute, {
    required super.env,
    required super.logger,
  });

  final CapabilityEvidencePort _capabilityEvidence;
  final RoutingMutePort _routingMute;

  /// Revokes the actor's own close-acknowledgement row. Survives blocks (§16.2).
  Future<void> revokeAcknowledgement({
    required String actorId,
    required String beaconId,
    required String subjectId,
    required String slug,
  }) async {
    validateCapabilitySlugPayload([slug]);
    await _capabilityEvidence.revokeOutcomeEvidence(
      beaconId: beaconId,
      observerId: actorId,
      subjectId: subjectId,
      slug: slug,
    );
  }

  Future<Set<String>> myRoutingTags({required String actorId}) =>
      _routingMute.mutedSlugsForUser(actorId);

  Future<void> setRoutingMute({
    required String actorId,
    required String slug,
    required bool muted,
  }) async {
    if (!kAllowedCapabilitySlugs.contains(slug)) {
      throw ExceptionBase(
        code: const CapabilityExceptionCodes(
          CapabilityExceptionCode.invalidSlug,
        ),
        description: 'Unknown capability slug: $slug',
      );
    }
    await _routingMute.setMute(
      userId: actorId,
      tagSlug: slug,
      muted: muted,
    );
  }
}
