import 'package:injectable/injectable.dart';

import 'package:tentura_root/domain/entity/auth_request_intent.dart';

import 'package:tentura/data/service/remote_api_client/credentials.dart';
import 'package:tentura/data/service/remote_api_service.dart';

import '../gql/_g/sign_in.req.gql.dart';
import '../gql/_g/sign_out.req.gql.dart';
import '../gql/_g/sign_up.req.gql.dart';

@singleton
class AuthRemoteRepository {
  AuthRemoteRepository(
    this._remoteApiService,
  );

  final RemoteApiService _remoteApiService;

  ///
  /// Returns id of created account
  ///
  Future<String> signUp({
    required String seed,
    required String title,
    required String invitationCode,
  }) async {
    final authRequestToken = await _remoteApiService.setAuth(
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
    final response = await _remoteApiService
        .request(request)
        .firstWhere((e) => e.dataSource == DataSource.Link)
        .then((r) => r.dataOrThrow(label: _repositoryKey).signUp);
    return response.subject;
  }

  ///
  /// Returns userId
  ///
  Future<String> signIn(String seed) async {
    await _remoteApiService.setAuth(
      seed: seed,
      authTokenFetcher: authTokenFetcher,
    );
    final authToken = await _remoteApiService.getAuthToken();
    return authToken.userId;
  }

  //
  //
  Future<void> signOut() async {
    if (_remoteApiService.hasValidToken) {
      await _remoteApiService
          .request(GSignOutReq())
          .firstWhere((e) => e.dataSource == DataSource.Link);
    }
    await _remoteApiService.dropAuth();
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
