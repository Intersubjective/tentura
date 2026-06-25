import 'dart:io';
import 'package:logging/logging.dart';
import 'package:injectable/injectable.dart';
import 'package:dart_jsonwebtoken/dart_jsonwebtoken.dart';
import 'package:postgres/postgres.dart'
    show ConnectionSettings, Endpoint, PoolSettings, SslMode;

import 'consts.dart';

export 'consts.dart';

String resolveServerEnvironment(String? environment) =>
    environment == Environment.dev ? Environment.dev : Environment.prod;

class Env {
  Env({
    // Common
    Level? logLevel,
    String? environment,
    bool? isDebugModeOn,
    int? workersCount,
    Uri? serverUri,
    bool? printEnv,

    // Auth
    bool? isNeedInvite,
    Duration? jwtExpiresIn,
    Duration? sessionExpiresIn,
    Duration? invitationTTL,
    String? publicKey,
    String? privateKey,
    String? publicOrigin,
    String? googleClientId,
    String? googleClientSecret,
    String? googleIosClientId,
    bool? oauthPreloadEnabled,
    String? resendApiKey,
    String? resendFromEmail,
    String? emailDebugSinkDir,
    String? qaAuthToken,
    List<String>? qaEmailDomains,
    String? unsubscribeSigningSecret,
    Duration? emailNotifCooldown,
    int? emailDigestHour,
    Duration? emailAuthTtl,
    Duration? emailAuthRateLimitWindow,
    int? emailAuthMaxPerEmail,
    int? emailAuthMaxPerIp,
    int? emailAuthMaxPerInvite,
    Duration? beaconCreateRateWindow,
    int? beaconCreateMaxPerUser,
    Duration? roomMessageRateWindow,
    int? roomMessageMaxPerUser,
    int? uploadDailyCapBytes,

    // Web server
    String? bindAddress,
    int? listenWebPort,
    bool? isPongEnabled,
    String? minClientVersion,

    // Postgres
    String? pgHost,
    int? pgPort,
    String? pgDatabase,
    String? pgUsername,
    String? pgPassword,
    int? maxConnectionAge,
    int? maxConnectionCount,

    // S3 storage
    String? kS3AccessKey,
    String? kS3SecretKey,
    String? kS3Endpoint,
    String? kS3Bucket,
    bool? kS3PathStyle,
    bool? kS3UseSSL,

    // Task Worker
    Duration? taskOnEmptyDelay,

    // Meritrank service
    Duration? meritrankCalculateTimeout,
    Duration? trustEdgeHalfLife,
    double? trustEdgeEpsilon,

    // User presence (WS offline delay; env CHAT_OFFLINE_DELAY)
    Duration? chatStatusOfflineAfterDelay,

    // Firebase
    String? fbAppId,
    String? fbApiKey,
    String? fbSenderId,
    String? fbProjectId,
    String? fbAuthDomain,
    String? fbStorageBucket,
    String? fbClientEmail,
    String? fbPrivateKey,
    String? fbClientId,
    Duration? fbAccessTokenExpiresIn,

    // Sentry
    String? sentryDsn,
    String? sentryRelease,
    String? sentryDist,
    double? sentryTracesSampleRate,
  }) : // Common
       printEnv = printEnv ?? _env['PRINT_ENV'] == 'true',
       isDebugModeOn = isDebugModeOn ?? _env['DEBUG_MODE'] == 'true',
       environment = environment ?? _env['ENVIRONMENT'] ?? Environment.prod,
       serverUri = serverUri ?? Uri.parse(kServerName),
       workersCount =
           workersCount ??
           int.tryParse(_env['WORKERS_COUNT'] ?? '') ??
           Platform.numberOfProcessors,

       // Auth
       invitationTTL = invitationTTL ?? kInvitationTTL,
       jwtExpiresIn = jwtExpiresIn ?? const Duration(seconds: kJwtExpiresIn),
       sessionExpiresIn = sessionExpiresIn ??
           Duration(
             seconds:
                 int.tryParse(_env['SESSION_EXPIRES_IN'] ?? '') ??
                 kSessionExpiresIn,
           ),
       isNeedInvite = isNeedInvite ?? _env['NEED_INVITE'] == 'true',
       publicOrigin = publicOrigin ?? kServerName,
       googleClientId = googleClientId ?? _env['GOOGLE_CLIENT_ID'] ?? '',
       googleClientSecret =
           googleClientSecret ?? _env['GOOGLE_CLIENT_SECRET'] ?? '',
       googleIosClientId =
           googleIosClientId ?? _env['GOOGLE_IOS_CLIENT_ID'] ?? '',
       oauthPreloadEnabled =
           oauthPreloadEnabled ?? _env['OAUTH_PRELOAD_ENABLED'] == 'true',
       resendApiKey = resendApiKey ?? _env['RESEND_API_KEY'] ?? '',
       resendFromEmail = resendFromEmail ?? _env['RESEND_FROM_EMAIL'] ?? '',
       emailDebugSinkDir =
           emailDebugSinkDir ?? _env['EMAIL_DEBUG_SINK_DIR'] ?? '',
       qaAuthToken = qaAuthToken ?? _env['QA_AUTH_TOKEN'] ?? '',
       qaEmailDomains =
           qaEmailDomains ??
           (_env['QA_EMAIL_DOMAINS'] ??
                   'test.tentura.local,qa.tentura.local,example.test')
               .split(',')
               .map((domain) => domain.trim().toLowerCase())
               .where((domain) => domain.isNotEmpty)
               .toList(),
       unsubscribeSigningSecret = unsubscribeSigningSecret ??
           _env['UNSUBSCRIBE_SIGNING_SECRET'] ??
           '',
       emailNotifCooldown = emailNotifCooldown ??
           Duration(
             seconds:
                 int.tryParse(_env['EMAIL_NOTIF_COOLDOWN_SECONDS'] ?? '') ??
                     1800,
           ),
       emailDigestHour =
           emailDigestHour ?? int.tryParse(_env['EMAIL_DIGEST_HOUR'] ?? '') ?? 8,
       emailAuthTtl = emailAuthTtl ??
           Duration(
             seconds: int.tryParse(_env['EMAIL_AUTH_TTL_SECONDS'] ?? '') ??
                 900,
           ),
       emailAuthRateLimitWindow = emailAuthRateLimitWindow ??
           Duration(
             seconds: int.tryParse(
                   _env['EMAIL_AUTH_RATE_WINDOW_SECONDS'] ?? '',
                 ) ??
                 3600,
           ),
       emailAuthMaxPerEmail = emailAuthMaxPerEmail ??
           int.tryParse(_env['EMAIL_AUTH_MAX_PER_EMAIL'] ?? '') ??
           5,
       emailAuthMaxPerIp = emailAuthMaxPerIp ??
           int.tryParse(_env['EMAIL_AUTH_MAX_PER_IP'] ?? '') ??
           20,
       emailAuthMaxPerInvite = emailAuthMaxPerInvite ??
           int.tryParse(_env['EMAIL_AUTH_MAX_PER_INVITE'] ?? '') ??
           10,
       beaconCreateRateWindow = beaconCreateRateWindow ??
           Duration(
             seconds: int.tryParse(
                   _env['BEACON_CREATE_RATE_WINDOW_SECONDS'] ?? '',
                 ) ??
                 3600,
           ),
       beaconCreateMaxPerUser = beaconCreateMaxPerUser ??
           int.tryParse(_env['BEACON_CREATE_MAX_PER_USER'] ?? '') ??
           30,
       roomMessageRateWindow = roomMessageRateWindow ??
           Duration(
             seconds: int.tryParse(
                   _env['ROOM_MESSAGE_RATE_WINDOW_SECONDS'] ?? '',
                 ) ??
                 60,
           ),
       roomMessageMaxPerUser = roomMessageMaxPerUser ??
           int.tryParse(_env['ROOM_MESSAGE_MAX_PER_USER'] ?? '') ??
           30,
       uploadDailyCapBytes = uploadDailyCapBytes ??
           (int.tryParse(_env['UPLOAD_DAILY_CAP_MB'] ?? '') ?? 200) *
               1024 *
               1024,
       publicKey = EdDSAPublicKey.fromPEM(
         (publicKey ?? _env['JWT_PUBLIC_PEM'] ?? kJwtPublicKey).replaceAll(
           r'\n',
           '\n',
         ),
       ),
       privateKey = EdDSAPrivateKey.fromPEM(
         (privateKey ?? _env['JWT_PRIVATE_PEM'] ?? kJwtPrivateKey).replaceAll(
           r'\n',
           '\n',
         ),
       ),

       // Web server
       bindAddress = bindAddress ?? _env['HOST'] ?? '0.0.0.0',
       listenWebPort =
           listenWebPort ?? int.tryParse(_env['PORT'] ?? '') ?? 2080,
       isPongEnabled = isPongEnabled ?? _env['PONG_ENABLED'] != 'false',
       minClientVersion =
           minClientVersion ?? _env['MIN_CLIENT_VERSION'] ?? '0.0.0',

       // Postgres
       pgHost = pgHost ?? _env['POSTGRES_HOST'] ?? 'postgres',
       pgPort = pgPort ?? int.tryParse(_env['POSTGRES_PORT'] ?? '') ?? 5432,
       pgDatabase = pgDatabase ?? _env['POSTGRES_DBNAME'] ?? 'postgres',
       pgUsername = pgUsername ?? _env['POSTGRES_USERNAME'] ?? 'postgres',
       pgPassword = pgPassword ?? _env['POSTGRES_PASSWORD'] ?? 'password',
       pgMaxConnectionAge =
           maxConnectionAge ??
           int.tryParse(_env['POSTGRES_MAXCONNAGE'] ?? '') ??
           600,
       pgMaxConnectionCount =
           maxConnectionCount ??
           int.tryParse(_env['POSTGRES_MAXCONN'] ?? '') ??
           25,

       // Task Worker
       taskOnEmptyDelay =
           taskOnEmptyDelay ??
           Duration(seconds: int.tryParse(_env['TASK_DELAY'] ?? '') ?? 1),

       // S3 storage
       kS3AccessKey = kS3AccessKey ?? _env['S3_ACCESS_KEY'] ?? '',
       kS3SecretKey = kS3SecretKey ?? _env['S3_SECRET_KEY'] ?? '',
       kS3Endpoint = kS3Endpoint ?? _env['S3_ENDPOINT'] ?? '',
       kS3Bucket = kS3Bucket ?? _env['S3_BUCKET'] ?? '',
       kS3PathStyle = kS3PathStyle ?? _env['S3_PATH_STYLE'] == 'true',
       kS3UseSSL = kS3UseSSL ??
           _inferS3UseSsl(_env['S3_USE_SSL'], kS3Endpoint ?? _env['S3_ENDPOINT'] ?? ''),

       // Meritrank service
       meritrankCalculateTimeout =
           meritrankCalculateTimeout ??
           Duration(
             minutes: int.tryParse(_env['MR_CALCULATE_TIMEOUT'] ?? '') ?? 10,
           ),
       trustEdgeHalfLife = trustEdgeHalfLife ??
           Duration(
             days: int.tryParse(_env['TRUST_EDGE_HALF_LIFE_DAYS'] ?? '') ?? 182,
           ),
       trustEdgeEpsilon =
           trustEdgeEpsilon ??
           double.tryParse(_env['TRUST_EDGE_EPSILON'] ?? '') ??
           0.1,

       chatStatusOfflineAfterDelay =
           chatStatusOfflineAfterDelay ??
           Duration(
             seconds:
                 int.tryParse(_env['CHAT_OFFLINE_DELAY'] ?? '') ??
                 kUserOfflineAfterSeconds,
           ),

       // Firebase
       fbAppId = fbAppId ?? _env['FB_APP_ID'] ?? '',
       fbApiKey = fbApiKey ?? _env['FB_API_KEY'] ?? '',
       fbSenderId = fbSenderId ?? _env['FB_SENDER_ID'] ?? '',
       fbProjectId = fbProjectId ?? _env['FB_PROJECT_ID'] ?? '',
       fbAuthDomain = fbAuthDomain ?? _env['FB_AUTH_DOMAIN'] ?? '',
       fbStorageBucket = fbStorageBucket ?? _env['FB_STORAGE_BUCKET'] ?? '',
       fbClientEmail = fbClientEmail ?? _env['FB_CLIENT_EMAIL'] ?? '',
       fbAccessTokenExpiresIn =
           fbAccessTokenExpiresIn ?? const Duration(hours: 1),
       fbPrivateKey = fbPrivateKey ?? _env['FB_PRIVATE_KEY'] ?? '',
       fbClientId = fbClientId ?? _env['FB_CLIENT_ID'] ?? '',

       // Sentry
       sentryDsn = sentryDsn ?? _env['SERVER_SENTRY_DSN'] ?? '',
       sentryRelease = sentryRelease ?? _env['SENTRY_RELEASE'] ?? '',
       sentryDist = sentryDist ?? _env['SENTRY_DIST'] ?? '',
       sentryTracesSampleRate = sentryTracesSampleRate ??
           double.tryParse(_env['SENTRY_TRACES_SAMPLE_RATE'] ?? '') ??
           1.0
  //
  {
    if (environment == Environment.dev || environment == Environment.prod) {
      _assertServingUrls(
        serverName: kServerName.isNotEmpty ? kServerName : serverUri.toString(),
        imageServer: kImageServer.isNotEmpty
            ? kImageServer
            : serverUri.toString(),
        googleClientId: this.googleClientId,
        googleClientSecret: this.googleClientSecret,
      );
      final envJwtPrivate = _env['JWT_PRIVATE_PEM']?.trim();
      final envJwtPublic = _env['JWT_PUBLIC_PEM']?.trim();
      if (envJwtPrivate != null &&
          envJwtPrivate.isNotEmpty &&
          envJwtPublic != null &&
          envJwtPublic.isNotEmpty) {
        _assertJwtKeys();
      }
    }
    _printEnvInfo();
    Logger.root.level =
        logLevel ??
        Level.LEVELS.firstWhere(
          (e) => e.name == _env['LOG_LEVEL']?.toUpperCase(),
          orElse: () => Level.INFO,
        );
  }

  Env.dev()
    : this(
        environment: Environment.dev,
        isDebugModeOn: true,
        logLevel: Level.ALL,
        workersCount: 1,
        printEnv: true,
      );

  Env.prod()
    : this(
        environment: Environment.prod,
      );

  Env.test()
    : this(
        environment: Environment.test,
        isDebugModeOn: true,
        logLevel: Level.ALL,
        workersCount: 1,
        printEnv: true,
      );

  // Common
  final bool isDebugModeOn;

  final String environment;

  final bool printEnv;

  final Uri serverUri;

  final int workersCount;

  late final isolatesCount = isDebugModeOn ? 1 : workersCount;

  // Auth
  final bool isNeedInvite;

  final Duration jwtExpiresIn;

  final Duration sessionExpiresIn;

  final Duration invitationTTL;

  final EdDSAPublicKey publicKey;

  final EdDSAPrivateKey privateKey;

  /// Public web origin (`SERVER_NAME` env var): OAuth callbacks, invite preview CORS, OG URLs.
  final String publicOrigin;

  /// Google OAuth client id; empty disables `/api/auth/google/start`.
  final String googleClientId;

  final String googleClientSecret;

  /// Google iOS OAuth client id. Native iOS `google_sign_in` mints id tokens
  /// whose `aud` is this client (not the web client), so it joins the verify
  /// `aud` allow-list. Empty disables the iOS audience.
  final String googleIosClientId;

  /// When true, Google OAuth start/callback return HTML that warms WASM assets.
  final bool oauthPreloadEnabled;

  final String resendApiKey;

  final String resendFromEmail;

  /// Dev-only magic-link delivery sink (`EMAIL_DEBUG_SINK_DIR`): when set, the
  /// server writes verify URLs to `<dir>/<sanitized-email>.json` instead of
  /// sending via Resend, so local and automated flows can read the link from
  /// disk. NEVER set in production — it bypasses real email delivery entirely.
  final String emailDebugSinkDir;

  /// Shared secret for development/staging-only QA HTTP endpoints.
  final String qaAuthToken;

  /// Domains accepted by the QA email-sink endpoint.
  final List<String> qaEmailDomains;

  /// HMAC secret for one-click email unsubscribe tokens.
  final String unsubscribeSigningSecret;

  /// Minimum gap between immediate notification emails per recipient+category.
  final Duration emailNotifCooldown;

  /// Local hour-of-day (0–23) at which the daily/weekly digest is sent.
  final int emailDigestHour;

  final Duration emailAuthTtl;

  final Duration emailAuthRateLimitWindow;

  final int emailAuthMaxPerEmail;

  final int emailAuthMaxPerIp;

  final int emailAuthMaxPerInvite;

  /// Sliding window for beacon-creation spam control (per author).
  final Duration beaconCreateRateWindow;

  /// Max beacons one author may create within [beaconCreateRateWindow].
  final int beaconCreateMaxPerUser;

  /// Sliding window for room-message spam control (per author).
  final Duration roomMessageRateWindow;

  /// Max room messages one author may post within [roomMessageRateWindow].
  final int roomMessageMaxPerUser;

  /// Max total bytes (images + file attachments) one user may upload per UTC
  /// day. Configured in MB via `UPLOAD_DAILY_CAP_MB` (default 200MB).
  final int uploadDailyCapBytes;

  bool get isEmailAuthConfigured =>
      (resendApiKey.isNotEmpty && resendFromEmail.isNotEmpty) ||
      emailDebugSinkDir.isNotEmpty;

  bool get isQaEmailSinkEnabled =>
      environment != Environment.prod &&
      qaAuthToken.isNotEmpty &&
      emailDebugSinkDir.isNotEmpty;

  // Web server
  final String bindAddress;

  final int listenWebPort;

  final bool isPongEnabled;

  /// Minimum Tentura client semver required; `0.0.0` disables the check.
  final String minClientVersion;

  // Task Worker
  final Duration taskOnEmptyDelay;

  // S3 settings
  final String kS3AccessKey;

  final String kS3SecretKey;

  /// Hostname, or `host:port` (e.g. `localhost:9000`). Parsed into host + port for the MinIO client.
  final String kS3Endpoint;

  final String kS3Bucket;

  /// Path-style URLs (e.g. MinIO at localhost). Virtual-hosted style for S3/Spaces.
  final bool kS3PathStyle;

  /// HTTPS for the S3 API (`S3_USE_SSL=true` / `false`). If unset: TLS on for
  /// `*.digitaloceanspaces.com` and `*.amazonaws.com`, else HTTP (local MinIO).
  final bool kS3UseSSL;

  /// When non-null, object uploads send `x-amz-acl` with this value.
  /// When null, the header is omitted (use a bucket policy for anonymous GET).
  ///
  /// [S3_OBJECT_ACL]: `omit`, `none`, or `false` (case-insensitive) forces omit; any other
  /// non-empty string is sent as the ACL value (e.g. `public-read`).
  /// If unset: `public-read` for `*.digitaloceanspaces.com` and other endpoints (anonymous
  /// image URLs in the app). Use `omit` if your provider rejects ACL headers; then set a
  /// Spaces/S3 bucket policy allowing `s3:GetObject` for `images/*`.
  late final String? kS3PutObjectAclValue = _putObjectAclFromEnv(
    _env['S3_OBJECT_ACL'],
    kS3Endpoint,
  );

  late final kIsRemoteStorageEnabled =
      kS3Endpoint.isNotEmpty &&
      kS3Bucket.isNotEmpty &&
      kS3AccessKey.isNotEmpty &&
      kS3SecretKey.isNotEmpty;

  // Postgres
  final String pgHost;

  final int pgPort;

  final String pgDatabase;

  final String pgUsername;

  final String pgPassword;

  final int pgMaxConnectionAge;

  final int pgMaxConnectionCount;

  final pgEndpointSettings = const ConnectionSettings(
    sslMode: SslMode.disable,
  );

  late final pgPoolSettings = PoolSettings(
    maxConnectionAge: Duration(seconds: pgMaxConnectionAge),
    maxConnectionCount: pgMaxConnectionCount,
    sslMode: pgEndpointSettings.sslMode,
  );

  late final pgEndpoint = Endpoint(
    host: pgHost,
    port: pgPort,
    database: pgDatabase,
    username: pgUsername,
    password: pgPassword,
  );

  // Meritrank service
  final Duration meritrankCalculateTimeout;

  final Duration trustEdgeHalfLife;

  final double trustEdgeEpsilon;

  final Duration chatStatusOfflineAfterDelay;

  // Firebase
  final String fbAppId;

  final String fbApiKey;

  final String fbSenderId;

  final String fbProjectId;

  final String fbAuthDomain;

  final String fbStorageBucket;

  final String fbClientEmail;

  final String fbPrivateKey;

  final String fbClientId;

  final Duration fbAccessTokenExpiresIn;

  // Sentry
  final String sentryDsn;

  final String sentryRelease;

  final String sentryDist;

  final double sentryTracesSampleRate;

  bool get isSentryEnabled => sentryDsn.isNotEmpty;

  //
  //
  static void _assertServingUrls({
    required String serverName,
    required String imageServer,
    required String googleClientId,
    required String googleClientSecret,
  }) {
    void requireUrl(String name, String value) {
      final trimmed = value.trim();
      if (trimmed.isEmpty) {
        throw StateError('$name is required (non-empty absolute http(s) URL).');
      }
      final uri = Uri.tryParse(trimmed);
      if (uri == null || !uri.hasScheme || !uri.hasAuthority) {
        throw StateError('$name must be an absolute URL (got: $value).');
      }
      if (uri.scheme != 'http' && uri.scheme != 'https') {
        throw StateError('$name must use http or https (got: $value).');
      }
    }

    requireUrl('SERVER_NAME', serverName);
    requireUrl('IMAGE_SERVER', imageServer);

    if (googleClientId.isNotEmpty && googleClientSecret.trim().isEmpty) {
      throw StateError(
        'GOOGLE_CLIENT_SECRET is required when GOOGLE_CLIENT_ID is set.',
      );
    }
  }

  static void _assertJwtKeys() {
    final rawPrivate = _env['JWT_PRIVATE_PEM'];
    final rawPublic = _env['JWT_PUBLIC_PEM'];
    if (rawPrivate == null || rawPrivate.trim().isEmpty) {
      throw StateError('JWT_PRIVATE_PEM must be set in dev/prod environments.');
    }
    if (rawPublic == null || rawPublic.trim().isEmpty) {
      throw StateError('JWT_PUBLIC_PEM must be set in dev/prod environments.');
    }
    final normPrivate = rawPrivate.replaceAll(r'\n', '\n').trim();
    final normPublic = rawPublic.replaceAll(r'\n', '\n').trim();
    if (normPrivate == kJwtPrivateKey.trim() ||
        normPublic == kJwtPublicKey.trim()) {
      throw StateError(
        'JWT_PRIVATE_PEM / JWT_PUBLIC_PEM must not be the embedded test keys '
        'in dev/prod environments.',
      );
    }
  }

  void _printEnvInfo() {
    if (printEnv) {
      print('Debug Mode: [$isDebugModeOn]');
      print('Need Invitation: [$isNeedInvite]');
      print('Invitation TTL: [${invitationTTL.inHours}]');
    }
  }

  static final _env = Platform.environment;

  /// When [explicit] is non-empty, only the value `true` enables TLS.
  /// When unset or empty: TLS for known HTTPS-only S3 hosts; otherwise plain HTTP (MinIO).
  static bool _inferS3UseSsl(String? explicit, String endpoint) {
    final trimmed = explicit?.trim();
    if (trimmed != null && trimmed.isNotEmpty) {
      return trimmed.toLowerCase() == 'true';
    }
    final e = endpoint.toLowerCase();
    if (e.contains('digitaloceanspaces.com') || e.contains('amazonaws.com')) {
      return true;
    }
    return false;
  }

  static String? _putObjectAclFromEnv(String? rawAcl, String endpoint) {
    final trimmed = rawAcl?.trim();
    if (trimmed != null && trimmed.isNotEmpty) {
      final lower = trimmed.toLowerCase();
      if (lower == 'omit' || lower == 'none' || lower == 'false') {
        return null;
      }
      return trimmed;
    }
    return 'public-read';
  }

  // JWT

  ///
  /// This key needed for testing purposes only!
  /// You should not use this key on public server!
  /// Be sure if you set your own public key!
  ///
  static const kJwtPublicKey = '''
-----BEGIN PUBLIC KEY-----
MCowBQYDK2VwAyEA2CmIb3Ho2eb6m8WIog6KiyzCY05sbyX04PiGlH5baDw=
-----END PUBLIC KEY-----
''';

  ///
  /// This key needed for testing purposes only!
  /// You should not use this key on public server!
  /// Be sure if you set your own private key!
  ///
  static const kJwtPrivateKey = '''
-----BEGIN PRIVATE KEY-----
MC4CAQAwBQYDK2VwBCIEIN3rCo3wCksyxX4qBYAC1vFr51kx/Od78QVrRLOV1orF
-----END PRIVATE KEY-----
''';
}
