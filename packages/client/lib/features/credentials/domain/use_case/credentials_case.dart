import 'package:injectable/injectable.dart';

import 'package:tentura/domain/exception/credential_exception.dart';
import 'package:tentura/domain/exception/server_exception.dart';
import 'package:tentura/domain/use_case/use_case_base.dart';

import '../../data/repository/credentials_repository.dart';
import '../entity/credential_entity.dart';

@injectable
final class CredentialsCase extends UseCaseBase {
  CredentialsCase(this._repository, {required super.env, required super.logger});

  final CredentialsRepository _repository;

  Future<List<CredentialEntity>> fetch() => _repository.fetchCredentials();

  Future<void> remove(String id) => _repository.removeCredential(id);

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
}
