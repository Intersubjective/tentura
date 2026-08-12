import 'package:injectable/injectable.dart';

import 'package:tentura_server/domain/port/meritrank_repository_port.dart';
import 'package:tentura_server/domain/port/user_repository_port.dart';
import 'package:tentura_server/domain/port/witness_window_port.dart';

import '../enum.dart';
import '../exception.dart';
import '_use_case_base.dart';

@Singleton(order: 2)
final class MeritrankCase extends UseCaseBase {
  MeritrankCase(
    this._userRepository,
    this._meritrankRepository, {
    WitnessWindowPort? witnessWindow,
    required super.env,
    required super.logger,
  }) : _witnessWindow = witnessWindow;

  final UserRepositoryPort _userRepository;

  final MeritrankRepositoryPort _meritrankRepository;
  final WitnessWindowPort? _witnessWindow;

  Future<int> init({
    required String userId,
    Iterable<UserRoles>? userRoles,
    bool? forceCalculate,
  }) async {
    if ((userRoles != null && userRoles.contains(UserRoles.admin)) ||
        (await _userRepository.getById(
          userId,
        )).hasPrivilege(UserPrivileges.mrInit)) {
      await _meritrankRepository.reset();

      final initResult = await _meritrankRepository.init();

      await _witnessWindow?.bumpMrEpoch();

      if (forceCalculate ?? false) {
        await _meritrankRepository.calculate(
          timeout: env.meritrankCalculateTimeout,
        );
      }

      return initResult;
    }
    throw const UnauthorizedException();
  }
}
