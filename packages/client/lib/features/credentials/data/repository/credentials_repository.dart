import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:dart_jsonwebtoken/dart_jsonwebtoken.dart';
import 'package:ed25519_edwards/ed25519_edwards.dart';
import 'package:injectable/injectable.dart';

import 'package:tentura/env.dart';
import 'package:tentura/data/repository/remote_repository.dart';
import 'package:tentura/domain/exception/credential_exception.dart';
import 'package:tentura/domain/exception/server_exception.dart';
import 'package:tentura_root/domain/entity/auth_request_intent.dart';

import '../../domain/entity/credential_entity.dart';
import '../service/google_link_platform.dart';

/// REST client for the authenticated `/api/v2/accounts/me/credentials` endpoints
/// (sign-in methods of the current account). Uses the bearer token bound to the
/// active session in `RemoteApiService`.
@Singleton(env: [Environment.dev, Environment.prod])
class CredentialsRepository extends RemoteRepository {
  CredentialsRepository({
    required super.remoteApiService,
    required super.log,
    required this._env,
  });

  final Env _env;

  static final _base = Uri.parse(
    '$kServerName/api/v2/accounts/me/credentials',
  );

  static final _emailLinkStart = Uri.parse(
    '$kServerName/api/v2/auth/email/link/start',
  );

  static final _googleLinkIntent = Uri.parse(
    '$kServerName/api/auth/google/link/intent',
  );

  Future<List<CredentialEntity>> fetchCredentials() async {
    final json = await remoteApiService.getAuthenticatedJson(_base);
    final list = (json['credentials'] as List?) ?? const [];
    return [
      for (final e in list)
        CredentialEntity.fromMap((e as Map).cast<String, dynamic>()),
    ];
  }

  /// Links a new `ed25519_device` credential. Returns the generated seed
  /// (show-once backup) on success.
  Future<String> linkSeed() async {
    final seed = _generateSeed();
    final authRequestToken = _authRequestTokenForSeed(seed);
    try {
      await remoteApiService.postAuthenticatedJson(
        _base,
        body: {'authRequestToken': authRequestToken},
      );
    } on ServerStatusException catch (e) {
      throw mapLinkStatus(e.statusCode);
    }
    return seed;
  }

  /// Native: obtain a Google id token and strict-link `oidc:google`.
  Future<void> linkGoogleNative() async {
    final idToken = await obtainGoogleIdTokenForLink(_env);
    if (idToken == null || idToken.isEmpty) {
      throw const ServerUnknownException();
    }
    try {
      await remoteApiService.postAuthenticatedJson(
        _base.replace(pathSegments: [..._base.pathSegments, 'google']),
        body: {'idToken': idToken},
      );
    } on ServerStatusException catch (e) {
      throw mapLinkStatus(e.statusCode);
    }
  }

  /// Web: mint a signed link token and return the top-level navigation URL.
  Future<String> fetchGoogleLinkStartUrl() async {
    final json = await remoteApiService.postAuthenticatedJson(_googleLinkIntent);
    final url = json['url'] as String? ?? '';
    if (url.isEmpty) {
      throw const ServerUnknownException();
    }
    return url;
  }

  /// Start an email magic link to add an address to the current account.
  Future<void> startEmailLink(String email) async {
    try {
      await remoteApiService.postAuthenticatedJson(
        _emailLinkStart,
        body: {'email': email},
      );
    } on ServerStatusException catch (e) {
      throw mapLinkStatus(e.statusCode);
    }
  }

  Future<void> removeCredential(String id) async {
    try {
      await remoteApiService.deleteAuthenticated(
        _base.replace(pathSegments: [..._base.pathSegments, id]),
      );
    } on ServerStatusException catch (e) {
      throw mapRemoveStatus(e.statusCode);
    }
  }

  static String _generateSeed() => base64UrlEncode(
    Uint8List.fromList(
      List<int>.generate(
        kSeedLength,
        (_) => Random.secure().nextInt(256),
        growable: false,
      ),
    ),
  );

  static String _authRequestTokenForSeed(String seed) {
    final key = newKeyFromSeed(base64Decode(seed));
    final privateKey = EdDSAPrivateKey(key.bytes);
    final publicKey = EdDSAPublicKey(public(key).bytes);
    return JWT({
      AuthRequestIntent.keyPublicKey: base64UrlEncode(publicKey.bytes),
    }).sign(
      privateKey,
      algorithm: JWTAlgorithm.EdDSA,
      expiresIn: const Duration(seconds: kAuthJwtExpiresIn),
    );
  }

  /// Maps a non-2xx link POST status to a domain exception.
  static Exception mapLinkStatus(int statusCode) => switch (statusCode) {
    409 => const CredentialConflictException(),
    _ => const ServerUnknownException(),
  };

  /// Maps a non-2xx DELETE status to a domain exception: 409 = the account's
  /// last credential, 404 = already gone.
  static Exception mapRemoveStatus(int statusCode) => switch (statusCode) {
    409 => const LastCredentialException(),
    404 => const CredentialNotFoundException(),
    _ => const ServerUnknownException(),
  };
}
