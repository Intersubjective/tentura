import 'package:tentura/consts.dart';

/// Maps `/shared/view?id=…&dest=…` notification links to in-app routes.
Uri transformBeaconAppLink(Uri uri, String beaconId) {
  final dest = uri.queryParameters['dest'];
  final item = uri.queryParameters['item']?.trim();
  if (dest == 'review') {
    return Uri(
      path: '$kPathReviewContributions/$beaconId',
      queryParameters: {kQueryIsDeepLink: 'true'},
    );
  }
  final qp = <String, String>{kQueryIsDeepLink: 'true'};
  if (dest == 'room') {
    qp[kQueryBeaconViewTab] = 'room';
    qp[kQueryBeaconEntry] = kBeaconEntryDeepLink;
    if (item != null && item.isNotEmpty) {
      qp[kQueryCoordinationItemId] = item;
    }
  } else if (dest == 'people') {
    qp[kQueryBeaconViewTab] = 'people';
    qp[kQueryBeaconEntry] = kBeaconEntryDeepLink;
  } else if (item != null && item.isNotEmpty) {
    qp[kQueryCoordinationItemId] = item;
  }
  return uri.replace(
    path: '$kPathBeaconView/$beaconId',
    queryParameters: qp,
  );
}
