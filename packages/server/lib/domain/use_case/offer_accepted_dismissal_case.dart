import 'package:injectable/injectable.dart';

import 'package:tentura_server/domain/exception.dart';
import 'package:tentura_server/domain/port/offer_accepted_dismissal_repository_port.dart';

import '_use_case_base.dart';

/// B077b — the helper dismisses the «Your help was accepted» sub-card once
/// for the whole account; every device reads the list back.
@Singleton(order: 2)
final class OfferAcceptedDismissalCase extends UseCaseBase {
  OfferAcceptedDismissalCase(
    this._dismissals, {
    required super.env,
    required super.logger,
  });

  final OfferAcceptedDismissalRepositoryPort _dismissals;

  Future<Map<String, Object?>> dismiss({
    required String beaconId,
    required String userId,
  }) async {
    final stored = await _dismissals.dismiss(
      userId: userId,
      beaconId: beaconId,
    );
    if (!stored) {
      throw const UnauthorizedException(
        description: 'Only a helper with an offer on this request',
      );
    }
    return list(userId: userId);
  }

  Future<Map<String, Object?>> list({required String userId}) async => {
    'userId': userId,
    'beaconIds': await _dismissals.dismissedBeaconIds(userId: userId),
  };
}
