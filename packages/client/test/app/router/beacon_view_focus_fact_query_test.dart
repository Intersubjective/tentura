// `focus_fact` on a Request detail link (arrival at the source of a copied
// fact, plan §6.1) survives route normalization and reaches the operational
// route, whether the viewer lands in the room or on the NOW tab.

import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/app/router/beacon_view_route_normalizer.dart';
import 'package:tentura/consts.dart';
import 'package:tentura/features/beacon_threads/domain/entity/request_thread.dart';

const _focus = 'Fsource-focus-1';

void main() {
  group('focus_fact on Request detail links', () {
    test('kept with tab=threads', () {
      final q = normalizeBeaconViewRouteQuery(
        incomingQuery: {
          kQueryBeaconViewTab: kBeaconViewTabThreads,
          'focus_fact': _focus,
        },
      ).queryParameters;
      expect(q[kQueryBeaconViewTab], kBeaconViewTabThreads);
      expect(q['focus_fact'], _focus);
    });

    test('kept when the General thread is resolved', () {
      final q = normalizeBeaconViewRouteQuery(
        incomingQuery: {
          kQueryThreadId: RequestThread.generalId,
          'focus_fact': _focus,
        },
      ).queryParameters;
      expect(q[kQueryThreadId], RequestThread.generalId);
      expect(q['focus_fact'], _focus);
    });

    test('kept without a tab (a non-member lands on the facts sheet)', () {
      final q = normalizeBeaconViewRouteQuery(
        incomingQuery: const {'focus_fact': _focus},
      ).queryParameters;
      expect(q['focus_fact'], _focus);
    });

    test('blank focus_fact is dropped', () {
      final q = normalizeBeaconViewRouteQuery(
        incomingQuery: const {'focus_fact': '  '},
      ).queryParameters;
      expect(q.containsKey('focus_fact'), isFalse);
    });

    test('reaches the operational route', () {
      final route = beaconViewOperationalFromNormalized(
        normalizeBeaconViewRouteQuery(
          incomingQuery: {
            kQueryBeaconViewTab: kBeaconViewTabThreads,
            'focus_fact': _focus,
          },
        ),
      );
      expect(route.rawQueryParams['focus_fact'], _focus);
    });
  });
}
