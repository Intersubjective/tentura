import 'package:flutter_test/flutter_test.dart';
import 'package:tentura/beacon_detail_path.dart';
import 'package:tentura/consts.dart';

void main() {
  test('posts use /post/view prefix', () {
    expect(
      beaconDetailPathFor('B1', isPost: true),
      '$kPathPostView/B1',
    );
    expect(
      beaconDetailPathFor(
        'B1',
        isPost: true,
        queryParameters: {kQueryBeaconEntry: 'inbox'},
      ),
      '$kPathPostView/B1?${kQueryBeaconEntry}=inbox',
    );
  });

  test('requests keep /beacon/view prefix', () {
    expect(
      beaconDetailPathFor('B1', isPost: false),
      '$kPathBeaconView/B1',
    );
  });
}
