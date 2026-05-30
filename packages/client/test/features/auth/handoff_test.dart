import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';
import 'package:tentura/domain/port/device_push_port.dart';
import 'package:tentura/env.dart';
import 'package:tentura/features/auth/domain/entity/account_entity.dart';
import 'package:tentura/features/auth/domain/port/auth_local_repository_port.dart';
import 'package:tentura/features/auth/domain/port/auth_remote_repository_port.dart';
import 'package:tentura/features/auth/domain/use_case/auth_case.dart';
import 'package:tentura/features/auth/data/service/handoff_codec.dart';
import 'package:tentura/features/auth/data/service/handoff_payload.dart';

// Mirrors packages/landing/handoff.js: UTF-8 -> base64url(, padding stripped).
String encodeFragment(Map<String, dynamic> payload, {bool stripPadding = true}) {
  final b64 = base64Url.encode(utf8.encode(jsonEncode(payload)));
  final encoded = stripPadding ? b64.replaceAll('=', '') : b64;
  return '#th=$encoded';
}

void main() {
  group('decodeHandoffFragment', () {
    test('decodes a valid payload', () {
      final p = decodeHandoffFragment(
        encodeFragment({'v': 1, 'userId': 'U1', 'seed': 'c2VlZA', 'displayName': 'Alice'}),
      );
      expect(p, isNotNull);
      expect(p!.userId, 'U1');
      expect(p.seed, 'c2VlZA');
      expect(p.displayName, 'Alice');
    });

    test('round-trips a non-ASCII display name', () {
      final p = decodeHandoffFragment(
        encodeFragment({'v': 1, 'userId': 'U1', 'seed': 'c2VlZA', 'displayName': 'Алиса Café'}),
      );
      expect(p?.displayName, 'Алиса Café');
    });

    test('tolerates missing base64 padding and a leading #-less fragment', () {
      final withHash = encodeFragment({'v': 1, 'userId': 'U1', 'seed': 's'});
      expect(decodeHandoffFragment(withHash.substring(1)), isNotNull);
      final padded = encodeFragment({'v': 1, 'userId': 'U1', 'seed': 's'}, stripPadding: false);
      expect(decodeHandoffFragment(padded)?.userId, 'U1');
    });

    test('displayName is optional', () {
      final p = decodeHandoffFragment(encodeFragment({'v': 1, 'userId': 'U1', 'seed': 's'}));
      expect(p?.displayName, isNull);
    });

    test('returns null for absent / wrong-key / empty fragment', () {
      expect(decodeHandoffFragment(null), isNull);
      expect(decodeHandoffFragment(''), isNull);
      expect(decodeHandoffFragment('#'), isNull);
      expect(decodeHandoffFragment('#other=abc'), isNull);
      expect(decodeHandoffFragment('#th='), isNull);
    });

    test('rejects an unsupported version', () {
      expect(
        decodeHandoffFragment(encodeFragment({'v': 2, 'userId': 'U1', 'seed': 's'})),
        isNull,
      );
    });

    test('rejects missing or empty userId / seed', () {
      expect(decodeHandoffFragment(encodeFragment({'v': 1, 'seed': 's'})), isNull);
      expect(decodeHandoffFragment(encodeFragment({'v': 1, 'userId': 'U1'})), isNull);
      expect(
        decodeHandoffFragment(encodeFragment({'v': 1, 'userId': '', 'seed': 's'})),
        isNull,
      );
      expect(
        decodeHandoffFragment(encodeFragment({'v': 1, 'userId': 'U1', 'seed': ''})),
        isNull,
      );
    });

    test('returns null for garbage instead of throwing', () {
      expect(decodeHandoffFragment('#th=!!!not-base64!!!'), isNull);
      expect(decodeHandoffFragment('#th=${base64Url.encode(utf8.encode("not json"))}'), isNull);
    });
  });

  group('AuthCase.applyHandoff', () {
    AuthCase build(FakeAuthLocal local) => AuthCase(
          local,
          FakeAuthRemote(),
          FakeDevicePush(),
          env: const Env(),
          logger: Logger('test'),
        );

    const payload = HandoffPayload(userId: 'U1', seed: 'c2VlZA', displayName: 'Alice');

    test('adds the account and makes it current when absent', () async {
      final local = FakeAuthLocal();
      await build(local).applyHandoff(payload);

      expect(local.added, [('U1', 'c2VlZA', 'Alice')]);
      expect(local.currentAccountId, 'U1');
    });

    test('is idempotent: skips the insert when the account already exists', () async {
      final local = FakeAuthLocal(existing: {'U1': const AccountEntity(id: 'U1')});
      await build(local).applyHandoff(payload);

      expect(local.added, isEmpty);
      expect(local.currentAccountId, 'U1');
    });
  });
}

class FakeAuthLocal implements AuthLocalRepositoryPort {
  FakeAuthLocal({Map<String, AccountEntity>? existing}) : _existing = existing ?? {};

  final Map<String, AccountEntity> _existing;
  final List<(String, String, String?)> added = [];
  String? currentAccountId;

  @override
  Future<AccountEntity?> getAccountById(String id) async => _existing[id];

  @override
  Future<void> addAccount(String id, String seed, [String? displayName]) async {
    added.add((id, seed, displayName));
  }

  @override
  Future<void> setCurrentAccountId(String? id) async {
    currentAccountId = id;
  }

  @override
  Stream<String> currentAccountChanges() => const Stream.empty();
  @override
  Future<void> dispose() async {}
  @override
  Future<String> getCurrentAccountId() async => currentAccountId ?? '';
  @override
  Future<String> getSeedByAccountId(String id) async => '';
  @override
  Future<List<AccountEntity>> getAccountsAll() async => _existing.values.toList();
  @override
  Future<AccountEntity?> getCurrentAccount() async => null;
  @override
  Future<void> removeAccount(String id) async {}
  @override
  Future<void> updateAccount(AccountEntity account) async {}
}

class FakeAuthRemote implements AuthRemoteRepositoryPort {
  @override
  Future<void> signOut() async {}
  @override
  Future<String> signIn(String seed) async => '';
  @override
  Future<String> signUp({
    required String seed,
    required String displayName,
    required String invitationCode,
    String? handle,
  }) async =>
      '';
}

class FakeDevicePush implements DevicePushPort {
  @override
  Future<void> unregisterCurrentDevice() async {}
}
