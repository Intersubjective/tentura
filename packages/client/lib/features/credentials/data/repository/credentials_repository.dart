import 'package:injectable/injectable.dart';

import 'package:tentura/consts.dart';
import 'package:tentura/data/repository/remote_repository.dart';
import 'package:tentura/domain/exception/credential_exception.dart';
import 'package:tentura/domain/exception/server_exception.dart';

import '../../domain/entity/credential_entity.dart';

/// REST client for the authenticated `/api/v2/accounts/me/credentials` endpoints
/// (sign-in methods of the current account). Uses the bearer token bound to the
/// active session in `RemoteApiService`.
@Singleton(env: [Environment.dev, Environment.prod])
class CredentialsRepository extends RemoteRepository {
  CredentialsRepository({
    required super.remoteApiService,
    required super.log,
  });

  static final _base = Uri.parse(
    '$kServerName/api/v2/accounts/me/credentials',
  );

  Future<List<CredentialEntity>> fetchCredentials() async {
    final json = await remoteApiService.getAuthenticatedJson(_base);
    final list = (json['credentials'] as List?) ?? const [];
    return [
      for (final e in list)
        CredentialEntity.fromMap((e as Map).cast<String, dynamic>()),
    ];
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

  /// Maps a non-2xx DELETE status to a domain exception: 409 = the account's
  /// last credential, 404 = already gone.
  static Exception mapRemoveStatus(int statusCode) => switch (statusCode) {
    409 => const LastCredentialException(),
    404 => const CredentialNotFoundException(),
    _ => const ServerUnknownException(),
  };
}
