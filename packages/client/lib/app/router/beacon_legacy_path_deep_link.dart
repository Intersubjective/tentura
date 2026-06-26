import 'package:tentura/consts.dart';

/// `/beacon/B…` without `/view` → `/beacon/view/B…` (web hash deep links).
Uri transformLegacyBeaconPath(Uri uri) {
  final segments = uri.pathSegments;
  if (segments.length != 2 || segments.first != 'beacon') {
    return uri;
  }
  final id = segments[1];
  if (!id.startsWith('B') && !id.startsWith('C')) {
    return uri;
  }
  final qp = Map<String, String>.from(uri.queryParameters);
  qp.putIfAbsent(kQueryIsDeepLink, () => 'true');
  qp.putIfAbsent(kQueryBeaconEntry, () => kBeaconEntryDeepLink);
  return uri.replace(
    path: '$kPathBeaconView/$id',
    queryParameters: qp,
  );
}
