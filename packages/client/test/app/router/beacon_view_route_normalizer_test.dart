import 'package:flutter_test/flutter_test.dart';
import 'package:tentura/app/router/beacon_view_route_normalizer.dart';
import 'package:tentura/app/router/root_router.dart';
import 'package:tentura/consts.dart';
import 'package:tentura/features/beacon_threads/domain/entity/request_thread.dart';

void main() {
  group('normalizeBeaconViewRouteQuery (plan §6 / §6.1)', () {
    test('bare request path → NOW (no tab key)', () {
      final q = normalizeBeaconViewRouteQuery(incomingQuery: const {}).queryParameters;
      expect(q.containsKey(kQueryBeaconViewTab), isFalse);
    });

    test('tab=now', () {
      final q = normalizeBeaconViewRouteQuery(
        incomingQuery: {kQueryBeaconViewTab: kBeaconViewTabNow},
      ).queryParameters;
      expect(q[kQueryBeaconViewTab], kBeaconViewTabNow);
    });

    test('tab=threads → ROOM', () {
      final q = normalizeBeaconViewRouteQuery(
        incomingQuery: {kQueryBeaconViewTab: kBeaconViewTabThreads},
      ).queryParameters;
      expect(q[kQueryBeaconViewTab], kBeaconViewTabThreads);
    });

    test('tab=threads&thread=general', () {
      final q = normalizeBeaconViewRouteQuery(
        incomingQuery: {
          kQueryBeaconViewTab: kBeaconViewTabThreads,
          kQueryThreadId: RequestThread.generalId,
        },
      ).queryParameters;
      expect(q[kQueryBeaconViewTab], kBeaconViewTabThreads);
      expect(q[kQueryThreadId], RequestThread.generalId);
    });

    test('tab=threads&message=id scroll target', () {
      final q = normalizeBeaconViewRouteQuery(
        incomingQuery: {
          kQueryBeaconViewTab: kBeaconViewTabThreads,
          kQueryMessageId: 'M1',
        },
      ).queryParameters;
      expect(q[kQueryBeaconViewTab], kBeaconViewTabThreads);
      expect(q[kQueryMessageId], 'M1');
      expect(q.containsKey(kQueryThreadId), isFalse);
    });

    test('tab=people&people_tab_attention=1', () {
      final q = normalizeBeaconViewRouteQuery(
        incomingQuery: {
          kQueryBeaconViewTab: 'people',
          kQueryBeaconPeopleTabAttention: '1',
        },
      ).queryParameters;
      expect(q[kQueryBeaconViewTab], 'people');
      expect(q[kQueryBeaconPeopleTabAttention], '1');
    });

    test('tab=log legacy compat', () {
      final q = normalizeBeaconViewRouteQuery(
        incomingQuery: {kQueryBeaconViewTab: 'log'},
      ).queryParameters;
      expect(q[kQueryBeaconViewTab], 'log');
    });

    test('unknown tab → NOW', () {
      final q = normalizeBeaconViewRouteQuery(
        incomingQuery: {kQueryBeaconViewTab: 'discussion'},
      ).queryParameters;
      expect(q.containsKey(kQueryBeaconViewTab), isFalse);
    });

    test('path thread/general wins over conflicting query', () {
      final q = normalizeBeaconViewRouteQuery(
        pathThreadId: RequestThread.generalId,
        incomingQuery: {
          kQueryBeaconViewTab: 'people',
          kQueryThreadId: 'legacy-item',
          kQueryMessageId: 'M9',
        },
      ).queryParameters;
      expect(q[kQueryBeaconViewTab], kBeaconViewTabThreads);
      expect(q[kQueryThreadId], RequestThread.generalId);
      expect(q[kQueryMessageId], 'M9');
    });

    test('path legacy thread → ROOM without message even when message present', () {
      final q = normalizeBeaconViewRouteQuery(
        pathThreadId: 'legacy-item',
        incomingQuery: {
          kQueryMessageId: 'M9',
          kQueryBeaconViewTab: 'people',
        },
      ).queryParameters;
      expect(q[kQueryBeaconViewTab], kBeaconViewTabThreads);
      expect(q[kQueryThreadId], 'legacy-item');
      expect(q.containsKey(kQueryMessageId), isFalse);
    });

    test('preserves entry= and is_deep_link=', () {
      final q = normalizeBeaconViewRouteQuery(
        incomingQuery: {
          kQueryBeaconEntry: kBeaconEntryRoomNotification,
          kQueryIsDeepLink: '1',
          kQueryBeaconViewTab: 'people',
        },
      ).queryParameters;
      expect(q[kQueryBeaconEntry], kBeaconEntryRoomNotification);
      expect(q[kQueryIsDeepLink], '1');
    });

    test('message= without thread kept for host canonicalizer', () {
      final q = normalizeBeaconViewRouteQuery(
        incomingQuery: {kQueryMessageId: 'M-only'},
      ).queryParameters;
      expect(q[kQueryMessageId], 'M-only');
      expect(q.containsKey(kQueryBeaconViewTab), isFalse);
    });
  });

  group('normalizeBeaconViewThreadDeepLink', () {
    test('rewrites /thread/general to query form', () {
      final out = normalizeBeaconViewThreadDeepLink(
        Uri.parse(
          '/beacon/view/B1/thread/${RequestThread.generalId}?entry=notification',
        ),
      );
      expect(out.path, '/beacon/view/B1');
      expect(out.queryParameters[kQueryBeaconViewTab], kBeaconViewTabThreads);
      expect(out.queryParameters[kQueryThreadId], RequestThread.generalId);
      expect(out.queryParameters[kQueryBeaconEntry], 'notification');
    });

    test('rewrites legacy thread path', () {
      final out = normalizeBeaconViewThreadDeepLink(
        Uri.parse('/beacon/view/B1/thread/legacy-item?message=M1'),
      );
      expect(out.path, '/beacon/view/B1');
      expect(out.queryParameters[kQueryThreadId], 'legacy-item');
      expect(out.queryParameters.containsKey(kQueryMessageId), isFalse);
    });
  });
}
