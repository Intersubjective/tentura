import 'package:injectable/injectable.dart';

import 'package:tentura/domain/exception/credential_exception.dart';
import 'package:tentura/domain/exception/server_exception.dart';
import 'package:tentura/domain/use_case/use_case_base.dart';
import 'package:tentura/features/auth/domain/port/auth_local_repository_port.dart';

import '../../data/repository/credentials_repository.dart';
import '../entity/credential_entity.dart';

@injectable
final class CredentialsCase extends UseCaseBase {
  CredentialsCase(
    this._repository,
    this._authLocalRepository, {
    required super.env,
    required super.logger,
  });

  final CredentialsRepository _repository;
  final AuthLocalRepositoryPort _authLocalRepository;

  Future<List<CredentialEntity>> fetch() => _repository.fetchCredentials();

  Future<void> remove(String id) => _repository.removeCredential(id);

  /// Generate + link a recovery seed; persists locally when the account has
  /// none yet. Returns the seed for show-once backup.
  Future<String> linkRecoverySeed() async {
    final seed = await _repository.linkSeed();
    final accountId = await _authLocalRepository.getCurrentAccountId();
    if (accountId.isNotEmpty) {
      await _authLocalRepository.storeLinkedSeedIfAbsent(accountId, seed);
    }
    return seed;
  }

  Future<void> linkGoogleNative() => _repository.linkGoogleNative();

  Future<String> googleLinkStartUrl() => _repository.fetchGoogleLinkStartUrl();

  Future<void> startEmailLink(String email) =>
      _repository.startEmailLink(email);

  Exception mapRemoveError(Object error) {
    if (error is LastCredentialException) {
      return error;
    }
    if (error is CredentialNotFoundException) {
      return error;
    }
    if (error is ServerStatusException) {
      return CredentialsRepository.mapRemoveStatus(error.statusCode);
    }
    if (error is Exception) {
      return error;
    }
    return const ServerUnknownException();
  }

  Exception mapLinkError(Object error) {
    if (error is CredentialConflictException) {
      return error;
    }
    if (error is ServerStatusException) {
      return CredentialsRepository.mapLinkStatus(error.statusCode);
    }
    if (error is Exception) {
      return error;
    }
    return const ServerUnknownException();
  }
}
