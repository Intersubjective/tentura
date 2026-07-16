import 'package:injectable/injectable.dart';

import 'package:tentura/domain/attention/port/attention_account_port.dart';

import 'use_case/auth_case.dart';

/// Keeps authentication as the owner of account identity changes.
@LazySingleton(as: AttentionAccountPort)
final class AttentionAccountAdapter implements AttentionAccountPort {
  AttentionAccountAdapter(this._auth);

  final AuthCase _auth;

  @override
  Stream<String> get currentAccountChanges => _auth.currentAccountChanges();
}
