import 'package:injectable/injectable.dart';

import 'package:tentura/data/service/remote_api_service.dart';
import 'package:tentura/domain/attention/offer_accepted_dismissals.dart';
import 'package:tentura/domain/exception/generic_exception.dart';
import 'package:tentura/features/attention/data/gql/_g/dismiss_offer_accepted.req.gql.dart';
import 'package:tentura/features/attention/data/gql/_g/offer_accepted_dismissals.req.gql.dart';

/// B077b — the dismissed «offer accepted» sub-cards, kept on the server per
/// account (`offerAcceptedDismissals` / `DismissOfferAccepted`), so every
/// device of the account hides the same ones.
@Singleton(
  as: OfferAcceptedDismissalPort,
  env: [Environment.dev, Environment.prod],
)
class OfferAcceptedDismissalRepository implements OfferAcceptedDismissalPort {
  OfferAcceptedDismissalRepository(this._remoteApiService);

  final RemoteApiService _remoteApiService;

  static const _label = 'OfferAcceptedDismissals';

  @override
  Future<Set<String>> load({required String viewerId}) async {
    final row = await _remoteApiService
        .request(GOfferAcceptedDismissalsReq())
        .firstWhere((e) => e.dataSource == DataSource.Link)
        .then((r) => r.dataOrThrow(label: _label).offerAcceptedDismissals);
    return _forViewer(viewerId, row.userId, row.beaconIds);
  }

  @override
  Future<Set<String>> dismiss({
    required String viewerId,
    required String beaconId,
  }) async {
    try {
      final row = await _remoteApiService
          .request(GDismissOfferAcceptedReq((b) => b.vars.beaconId = beaconId))
          .firstWhere((e) => e.dataSource == DataSource.Link)
          .then((r) => r.dataOrThrow(label: _label).DismissOfferAccepted);
      return _forViewer(viewerId, row.userId, row.beaconIds);
    } on RemoteApiException {
      // The server answered with a refusal (e.g. no offer on the Request any
      // more): sending it again cannot help.
      throw const OfferAcceptedDismissalRefusedException();
    }
  }

  /// The server answers for the signed-in account; an answer for another
  /// account (switched meanwhile) must not be filed under [viewerId].
  static Set<String> _forViewer(
    String viewerId,
    String userId,
    Iterable<String> beaconIds,
  ) {
    if (userId != viewerId) {
      throw StateError(
        'offer-accepted dismissals answered for another account',
      );
    }
    return {...beaconIds};
  }
}
