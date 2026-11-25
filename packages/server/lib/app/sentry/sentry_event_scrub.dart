import 'package:sentry/sentry.dart';

import 'sentry_benign_filter.dart';

const _scrubbedHeaderKeys = {
  'authorization',
  'cookie',
  'set-cookie',
};

final _phantomMutation = RegExp(
  r'\bphantom(?:Create|Update|Delete|InviteEnsure|InviteRotate|Link|Unmerge|HintDismiss)\b',
  caseSensitive: false,
);

Breadcrumb? scrubPhantomBreadcrumb(Breadcrumb? breadcrumb, Hint _) {
  if (breadcrumb == null) return null;

  final operationName = breadcrumb.data?['operationName'];
  final operation =
      (operationName is String
          ? _phantomMutation.firstMatch(operationName)
          : null) ??
      _phantomMutation.firstMatch(breadcrumb.message ?? '');
  if (operation == null) return breadcrumb;

  // Either payload field can contain variables, so retain only the known
  // mutation name and the breadcrumb's metadata.
  return Breadcrumb(
    message: operation.group(0),
    timestamp: breadcrumb.timestamp,
    category: breadcrumb.category,
    level: breadcrumb.level,
    type: breadcrumb.type,
  );
}

SentryEvent? scrubAndFilterSentryEvent(SentryEvent event, Hint hint) {
  if (isBenignSentryEvent(event, hint)) {
    return null;
  }
  return _scrubEvent(event);
}

SentryEvent _scrubEvent(SentryEvent event) {
  final request = event.request;
  if (request != null) {
    event.request = _scrubRequest(request);
  }

  final user = event.user;
  if (user != null) {
    event.user = SentryUser(
      id: user.id,
      username: user.username,
      email: user.email,
      ipAddress: user.ipAddress,
    );
  }

  return event;
}

SentryRequest _scrubRequest(SentryRequest request) {
  final sanitizedHeaders = <String, String>{};
  for (final entry in request.headers.entries) {
    if (_scrubbedHeaderKeys.contains(entry.key.toLowerCase())) {
      sanitizedHeaders[entry.key] = '[Filtered]';
    } else {
      sanitizedHeaders[entry.key] = entry.value;
    }
  }

  return SentryRequest(
    url: request.url,
    method: request.method,
    queryString: request.queryString,
    fragment: request.fragment,
    apiTarget: request.apiTarget,
    headers: sanitizedHeaders,
    env: request.env,
  );
}

Map<String, String> sanitizeHttpHeaders(Map<String, String> headers) {
  final sanitized = <String, String>{};
  for (final entry in headers.entries) {
    if (_scrubbedHeaderKeys.contains(entry.key.toLowerCase())) {
      sanitized[entry.key] = '[Filtered]';
    } else {
      sanitized[entry.key] = entry.value;
    }
  }
  return sanitized;
}

/// Attaches sanitized HTTP request metadata to every event on a request hub.
final class SentryRequestEventProcessor implements EventProcessor {
  SentryRequestEventProcessor(this.request);

  final SentryRequest request;

  @override
  SentryEvent? apply(SentryEvent event, Hint hint) {
    return event..request = event.request ?? request;
  }
}

String? clientIpFromHeaders(Map<String, String> headers) {
  final forwarded = headers['x-forwarded-for'] ?? headers['X-Forwarded-For'];
  if (forwarded != null && forwarded.isNotEmpty) {
    return forwarded.split(',').first.trim();
  }
  final realIp = headers['x-real-ip'] ?? headers['X-Real-Ip'];
  if (realIp != null && realIp.isNotEmpty) {
    return realIp;
  }
  return null;
}
