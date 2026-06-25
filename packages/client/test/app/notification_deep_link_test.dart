import 'package:test/test.dart';
import 'package:tentura/app/router/notification_deep_link.dart';
import 'package:tentura/consts.dart';

void main() {
  test('dest=review maps to review contributions path', () {
    final out = transformBeaconAppLink(
      Uri.parse('/shared/view?id=B12345678901&dest=review'),
      'B12345678901',
    );
    expect(out.path, '$kPathReviewContributions/B12345678901');
    expect(out.queryParameters[kQueryIsDeepLink], 'true');
  });

  test('dest=room with item preserves coordination item query', () {
    final out = transformBeaconAppLink(
      Uri.parse('/shared/view?id=B12345678901&dest=room&item=Iabc'),
      'B12345678901',
    );
    expect(out.path, '$kPathBeaconView/B12345678901');
    expect(out.queryParameters[kQueryBeaconViewTab], 'room');
    expect(out.queryParameters[kQueryCoordinationItemId], 'Iabc');
    expect(out.queryParameters[kQueryBeaconEntry], kBeaconEntryDeepLink);
    expect(out.queryParameters[kQueryIsDeepLink], 'true');
  });

  test('dest=people opens people tab', () {
    final out = transformBeaconAppLink(
      Uri.parse('/shared/view?id=B12345678901&dest=people'),
      'B12345678901',
    );
    expect(out.path, '$kPathBeaconView/B12345678901');
    expect(out.queryParameters[kQueryBeaconViewTab], 'people');
    expect(out.queryParameters[kQueryBeaconEntry], kBeaconEntryDeepLink);
    expect(out.queryParameters[kQueryIsDeepLink], 'true');
  });
}
