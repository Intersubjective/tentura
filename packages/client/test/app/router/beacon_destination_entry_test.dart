import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/app/router/root_router.dart';
import 'package:tentura/consts.dart';

void main() {
  test('adds the source list to a Request link without one', () {
    final uri = beaconDestinationWithEntry(
      Uri(path: '$kPathBeaconView/B1', queryParameters: {'tab': 'threads'}),
      entry: kBeaconEntryInbox,
    );
    expect(uri.queryParameters[kQueryBeaconEntry], kBeaconEntryInbox);
    expect(uri.queryParameters['tab'], 'threads');
  });

  test('keeps an explicit entry', () {
    final uri = beaconDestinationWithEntry(
      Uri(
        path: '$kPathBeaconView/B1',
        queryParameters: {kQueryBeaconEntry: kBeaconEntryForward},
      ),
      entry: kBeaconEntryInbox,
    );
    expect(uri.queryParameters[kQueryBeaconEntry], kBeaconEntryForward);
  });

  test('leaves other destinations alone', () {
    final uri = beaconDestinationWithEntry(
      Uri(path: '$kPathProfileView/U1'),
      entry: kBeaconEntryInbox,
    );
    expect(uri.queryParameters, isEmpty);
  });
}
