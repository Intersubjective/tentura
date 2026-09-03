import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/consts.dart';

void main() {
  test('create-tab query values stay stable for web deep links', () {
    expect(kQueryBeaconCreateTab, 'tab');
    expect(kBeaconCreateTabRecipients, 'recipients');
    expect(kBeaconCreateTabImage, 'image');
    expect(kPathBeaconNew, '/beacon/new');
  });
}
