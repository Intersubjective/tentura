import 'package:test/test.dart';
import 'package:tentura/app/router/notification_deep_link.dart';
import 'package:tentura/consts.dart';
import 'package:tentura/features/beacon_threads/domain/entity/request_thread.dart';

void main() {
  test('dest=review maps to review contributions path', () {
    final out = transformBeaconAppLink(
      Uri.parse('/shared/view?id=B12345678901&dest=review'),
      'B12345678901',
    );
    expect(out.path, '$kPathReviewContributions/B12345678901');
    expect(out.queryParameters[kQueryIsDeepLink], 'true');
  });

  test('dest=room with item opens threads tab on that thread', () {
    final out = transformBeaconAppLink(
      Uri.parse('/shared/view?id=B12345678901&dest=room&item=Iabc'),
      'B12345678901',
    );
    expect(out.path, '$kPathBeaconView/B12345678901');
    expect(out.queryParameters[kQueryBeaconViewTab], kBeaconViewTabThreads);
    expect(out.queryParameters[kQueryThreadId], 'Iabc');
    expect(out.queryParameters[kQueryBeaconEntry], kBeaconEntryDeepLink);
    expect(out.queryParameters[kQueryIsDeepLink], 'true');
  });

  test('dest=room without item opens General', () {
    final out = transformBeaconAppLink(
      Uri.parse('/shared/view?id=B12345678901&dest=room'),
      'B12345678901',
    );
    expect(out.queryParameters[kQueryThreadId], RequestThread.generalId);
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
