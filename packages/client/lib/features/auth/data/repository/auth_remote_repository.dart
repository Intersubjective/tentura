import 'package:injectable/injectable.dart';

import 'package:tentura_root/domain/entity/auth_request_intent.dart';

import 'package:tentura/data/repository/remote_repository.dart';
import 'package:tentura/data/service/remote_api_client/credentials.dart';
import 'package:tentura/data/service/remote_api_service.dart';
import 'package:tentura/features/auth/domain/port/auth_remote_repository_port.dart';

import '../gql/_g/sign_in.req.gql.dart';
import '../gql/_g/sign_out.req.gql.dart';
import '../gql/_g/sign_up.req.gql.dart';

@Singleton(
  as: AuthRemoteRepositoryPort,
  env: [Environment.dev, Environment.prod],
)
class AuthRemoteRepository extends RemoteRepository
    implements AuthRemoteRepositoryPort {
  AuthRemoteRepository({
    required super.remoteApiService,
    required super.log,
  });

  ///
  /// Returns id of created account
  ///
  @override
  Future<String> signUp({
    required String seed,
    required String title,
    required String invitationCode,
  }) async {
    final authRequestToken = await remoteApiService.setAuth(
      seed: seed,
      authTokenFetcher: authTokenFetcher,
      returnAuthRequestToken: AuthRequestIntentSignUp(
        invitationCode: invitationCode,
      ),
    );
    final request = GSignUpReq((b) {
      b.context = const Context().withEntry(const HttpAuthHeaders.noAuth());
      b.vars
        ..title = title
        ..authRequestToken = authRequestToken;
    });
    final response = await remoteApiService
        .request(request)
        .firstWhere((e) => e.dataSource == DataSource.Link)
        .then((r) => r.dataOrThrow(label: _repositoryKey).signUp);
    return response.subject;
  }

  ///
  /// Returns userId
  ///
  @override
  Future<String> signIn(String seed) async {
    await remoteApiService.dropAuth();
    await remoteApiService.setAuth(
      seed: seed,
      authTokenFetcher: authTokenFetcher,
    );
    final authToken = await remoteApiService.getAuthToken();
    return authToken.userId;
  }

  //
  //
  @override
  Future<void> signOut() async {
    if (remoteApiService.hasValidToken) {
      await remoteApiService
          .request(GSignOutReq())
          .firstWhere((e) => e.dataSource == DataSource.Link);
    }
    await remoteApiService.dropAuth();
  }

  //
  // TBD: check if it can be private
  static Future<Credentials> authTokenFetcher(
    GqlFetcher fetcher,
    String authRequestToken,
  ) {
    final request = GSignInReq((b) {
      b.context = const Context().withEntry(const HttpAuthHeaders.noAuth());
      b.vars.authRequestToken = authRequestToken;
    });
    return fetcher(request)
        .firstWhere((e) => e.dataSource == DataSource.Link)
        .then((r) => r.dataOrThrow(label: _repositoryKey).signIn)
        .then(
          (v) => Credentials(
            userId: v.subject,
            accessToken: v.access_token,
            expiresAt: DateTime.timestamp().add(
              Duration(seconds: v.expires_in),
            ),
          ),
        );
  }

  static const _repositoryKey = 'Auth';
}
