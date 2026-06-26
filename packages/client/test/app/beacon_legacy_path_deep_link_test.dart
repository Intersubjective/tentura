import 'package:test/test.dart';
import 'package:tentura/app/router/beacon_legacy_path_deep_link.dart';
import 'package:tentura/consts.dart';

void main() {
  test('legacy /beacon/:id rewrites to /beacon/view/:id', () {
    final out = transformLegacyBeaconPath(
      Uri.parse('/beacon/B1acfdc5d02a6'),
    );
    expect(out.path, '$kPathBeaconView/B1acfdc5d02a6');
    expect(out.queryParameters[kQueryIsDeepLink], 'true');
    expect(out.queryParameters[kQueryBeaconEntry], kBeaconEntryDeepLink);
  });

  test('reserved /beacon segments are left unchanged', () {
    expect(
      transformLegacyBeaconPath(Uri.parse('/beacon/new')).path,
      '/beacon/new',
    );
    expect(
      transformLegacyBeaconPath(Uri.parse('/beacon/view/B123')).path,
      '/beacon/view/B123',
    );
  });
}
