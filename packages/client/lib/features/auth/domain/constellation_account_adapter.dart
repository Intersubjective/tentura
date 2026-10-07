import 'package:injectable/injectable.dart';
import 'package:tentura/features/constellation/domain/port/constellation_account_port.dart';

import 'use_case/auth_case.dart';

/// Keeps authentication as the owner of account identity changes.
@LazySingleton(as: ConstellationAccountPort)
final class ConstellationAccountAdapter implements ConstellationAccountPort {
  ConstellationAccountAdapter(this._auth);

  final AuthCase _auth;

  @override
  Stream<String> get currentAccountChanges => _auth.currentAccountChanges();
}
