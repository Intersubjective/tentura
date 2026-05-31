import 'package:shelf_plus/shelf_plus.dart';

/// Parse the `Cookie` header into a name → value map (first value per name).
Map<String, String> parseCookies(Request request) {
  final raw = request.headers['cookie'];
  if (raw == null || raw.isEmpty) {
    return const {};
  }
  final out = <String, String>{};
  for (final part in raw.split(';')) {
    final trimmed = part.trim();
    if (trimmed.isEmpty) continue;
    final eq = trimmed.indexOf('=');
    if (eq <= 0) continue;
    final name = trimmed.substring(0, eq).trim();
    final value = trimmed.substring(eq + 1).trim();
    out.putIfAbsent(name, () => value);
  }
  return out;
}

String? readCookie(Request request, String name) =>
    parseCookies(request)[name];

/// Build a `Set-Cookie` header value. [name] may use the `__Host-` prefix.
String buildSetCookie({
  required String name,
  required String value,
  int? maxAgeSeconds,
  bool httpOnly = true,
  bool secure = true,
  String sameSite = 'Lax',
  String path = '/',
}) {
  final parts = <String>[
    '$name=$value',
    'Path=$path',
    'SameSite=$sameSite',
  ];
  if (httpOnly) parts.add('HttpOnly');
  if (secure) parts.add('Secure');
  if (maxAgeSeconds != null) {
    parts.add('Max-Age=$maxAgeSeconds');
  }
  assert(
    !name.startsWith('__Host-') ||
        (secure && path == '/' && !parts.any((p) => p.startsWith('Domain='))),
    '__Host- cookies require Secure, Path=/, and no Domain',
  );
  return parts.join('; ');
}

/// Clear a cookie by setting Max-Age=0.
String buildClearCookie(String name) => buildSetCookie(
  name: name,
  value: '',
  maxAgeSeconds: 0,
);

/// Append [setCookie] to response headers (supports multiple Set-Cookie).
Map<String, Object> withSetCookie(
  Map<String, Object> headers,
  String setCookie,
) {
  final existing = headers['set-cookie'];
  if (existing == null) {
    return {...headers, 'set-cookie': setCookie};
  }
  if (existing is List<String>) {
    return {...headers, 'set-cookie': [...existing, setCookie]};
  }
  return {
    ...headers,
    'set-cookie': [existing as String, setCookie],
  };
}

const kHeaderCacheControl = 'Cache-Control';
const kHeaderVary = 'Vary';
const kCacheControlNoStore = 'no-store';
