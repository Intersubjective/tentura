import 'package:tentura_server/domain/entity/constellation_field.dart';

// ignore: one_member_abstracts -- injectable port with a single repository entry point
abstract interface class BeaconMemberWebsRepositoryPort {
  /// Members of [beaconId] other than [viewerId]: the author and admitted
  /// participants as `inside`, and, only when [includeForwarded] is set,
  /// recipients of active forward edges as `forwarded`. Restricted to the
  /// viewer's visible peer set in [context].
  Future<List<ConstellationMemberWebRecord>> memberWebs({
    required String beaconId,
    required String viewerId,
    required String context,
    required bool includeForwarded,
  });
}
