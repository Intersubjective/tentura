import 'package:auto_route/auto_route.dart';
import 'package:tentura/consts.dart';
import 'package:tentura/features/beacon_threads/domain/entity/request_thread.dart';

import 'root_router.gr.dart';

/// Normalized query contract for request detail deep links (plan §6 / §6.1).
final class NormalizedBeaconViewQuery {
  const NormalizedBeaconViewQuery({required this.queryParameters});

  final Map<String, String> queryParameters;
}

Map<String, String> _incomingQueryFromParameters(Parameters qp) {
  final raw = qp.rawMap;
  if (raw.isEmpty) return const {};
  return raw.map((key, value) => MapEntry(key, value?.toString() ?? ''));
}

/// Single precedence policy for cold deep links and warm `/thread/:id` redirects.
///
/// 1. path [pathThreadId] wins over query `thread=`;
/// 2. a resolved thread id implies `tab=threads`, overriding incoming `tab=`;
/// 3. non-`general` thread id keeps `thread=` for legacy-unavailable ROOM (no `message=`);
/// 4. `entry=` / `is_deep_link=` are always preserved;
/// 5. unrecognized `tab` falls through to NOW (tab omitted).
NormalizedBeaconViewQuery normalizeBeaconViewRouteQuery({
  String? pathThreadId,
  Map<String, String> incomingQuery = const {},
}) {
  final preserved = <String, String>{};
  for (final key in [kQueryIsDeepLink, kQueryBeaconEntry]) {
    final value = incomingQuery[key]?.trim();
    if (value != null && value.isNotEmpty) {
      preserved[key] = value;
    }
  }

  final pathThread = pathThreadId?.trim();
  final queryThread = incomingQuery[kQueryThreadId]?.trim();
  final resolvedThread = pathThread != null && pathThread.isNotEmpty
      ? pathThread
      : (queryThread != null && queryThread.isNotEmpty ? queryThread : null);

  final incomingTab = incomingQuery[kQueryBeaconViewTab]?.trim();
  final message = incomingQuery[kQueryMessageId]?.trim();
  final peopleAttention =
      incomingQuery[kQueryBeaconPeopleTabAttention]?.trim();

  final result = <String, String>{...preserved};

  if (resolvedThread != null && resolvedThread.isNotEmpty) {
    result[kQueryBeaconViewTab] = kBeaconViewTabThreads;
    result[kQueryThreadId] = resolvedThread;
    if (resolvedThread == RequestThread.generalId &&
        message != null &&
        message.isNotEmpty) {
      result[kQueryMessageId] = message;
    }
    return NormalizedBeaconViewQuery(queryParameters: result);
  }

  switch (incomingTab) {
    case kBeaconViewTabNow:
      result[kQueryBeaconViewTab] = kBeaconViewTabNow;
    case kBeaconViewTabThreads:
      result[kQueryBeaconViewTab] = kBeaconViewTabThreads;
      if (message != null && message.isNotEmpty) {
        result[kQueryMessageId] = message;
      }
    case 'people':
      result[kQueryBeaconViewTab] = 'people';
      if (peopleAttention != null && peopleAttention.isNotEmpty) {
        result[kQueryBeaconPeopleTabAttention] = peopleAttention;
      }
    case 'log':
      result[kQueryBeaconViewTab] = 'log';
    case null:
    case '':
      break;
    default:
      break;
  }

  if (message != null &&
      message.isNotEmpty &&
      !result.containsKey(kQueryMessageId)) {
    result[kQueryMessageId] = message;
  }

  return NormalizedBeaconViewQuery(queryParameters: result);
}

NormalizedBeaconViewQuery normalizeBeaconViewRouteQueryFromParameters(
  Parameters qp, {
  String? pathThreadId,
}) =>
    normalizeBeaconViewRouteQuery(
      pathThreadId: pathThreadId,
      incomingQuery: _incomingQueryFromParameters(qp),
    );

String beaconViewPathWithQuery(String beaconId, NormalizedBeaconViewQuery q) {
  final params = q.queryParameters;
  if (params.isEmpty) return '$kPathBeaconView/$beaconId';
  return '$kPathBeaconView/$beaconId?${Uri(queryParameters: params).query}';
}

BeaconViewOperationalRoute beaconViewOperationalFromNormalized(
  NormalizedBeaconViewQuery normalized,
) {
  final q = normalized.queryParameters;
  return BeaconViewOperationalRoute(
    isDeepLink: q[kQueryIsDeepLink],
    viewTab: q[kQueryBeaconViewTab],
    peopleTabAttention: q[kQueryBeaconPeopleTabAttention],
    entry: q[kQueryBeaconEntry],
    threadId: q[kQueryThreadId],
    messageId: q[kQueryMessageId],
  );
}
