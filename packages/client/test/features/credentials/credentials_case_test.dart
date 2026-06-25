import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';
import 'package:mockito/mockito.dart';

import 'package:tentura/domain/exception/credential_exception.dart';
import 'package:tentura/domain/exception/server_exception.dart';
import 'package:tentura/env.dart';
import 'package:tentura/features/credentials/data/repository/credentials_repository.dart';
import 'package:tentura/features/credentials/domain/entity/credential_entity.dart';
import 'package:tentura/features/credentials/domain/use_case/credentials_case.dart';

import '../auth/auth_test_helpers.dart';

void main() {
  late FakeCredentialsRepository repository;
  late TrackingAuthLocal authLocal;
  late CredentialsCase case_;

  const accountId = 'Uacc';
  const seed = 'seed-backup';
  const credential = CredentialEntity(
    id: 'c1',
    type: 'ed25519_device',
    identifier: 'PUBKEY',
  );

  setUp(() {
    repository = FakeCredentialsRepository();
    authLocal = TrackingAuthLocal();
    case_ = CredentialsCase(
      repository,
      authLocal,
      env: const Env(),
      logger: Logger('test'),
    );
  });

  group('fetch', () {
    test('returns credentials from the repository', () async {
      repository.credentials = [credential];

      final result = await case_.fetch();

      expect(result, [credential]);
    });
  });

  group('remove', () {
    test('delegates to the repository', () async {
      await case_.remove('c1');

      expect(repository.removedId, 'c1');
    });
  });

  group('linkRecoverySeed', () {
    test('returns seed and persists locally when account is signed in', () async {
      authLocal.accountId = accountId;
      repository.linkSeedResult = seed;

      final result = await case_.linkRecoverySeed();

      expect(result, seed);
      expect(
        authLocal.linkedSeeds,
        [(id: accountId, seed: seed)],
      );
    });

    test('returns seed without persisting when account id is empty', () async {
      authLocal.accountId = '';
      repository.linkSeedResult = seed;

      final result = await case_.linkRecoverySeed();

      expect(result, seed);
      expect(authLocal.linkedSeeds, isEmpty);
    });
  });

  group('linkGoogleNative', () {
    test('delegates to the repository', () async {
      await case_.linkGoogleNative();

      expect(repository.linkGoogleNativeCalled, isTrue);
    });
  });

  group('googleLinkStartUrl', () {
    test('returns the repository URL', () async {
      repository.googleLinkUrl = 'https://auth.example/link';

      final url = await case_.googleLinkStartUrl();

      expect(url, 'https://auth.example/link');
    });
  });

  group('startEmailLink', () {
    test('delegates to the repository', () async {
      await case_.startEmailLink('user@example.com');

      expect(repository.emailLinkStarted, 'user@example.com');
    });
  });

  group('mapRemoveError', () {
    test('passes through LastCredentialException', () {
      const error = LastCredentialException();
      expect(case_.mapRemoveError(error), same(error));
    });

    test('passes through CredentialNotFoundException', () {
      const error = CredentialNotFoundException();
      expect(case_.mapRemoveError(error), same(error));
    });

    test('maps ServerStatusException 409 to LastCredentialException', () {
      expect(
        case_.mapRemoveError(const ServerStatusException(409)),
        isA<LastCredentialException>(),
      );
    });

    test('maps ServerStatusException 404 to CredentialNotFoundException', () {
      expect(
        case_.mapRemoveError(const ServerStatusException(404)),
        isA<CredentialNotFoundException>(),
      );
    });

    test('maps other ServerStatusException to ServerUnknownException', () {
      expect(
        case_.mapRemoveError(const ServerStatusException(500)),
        isA<ServerUnknownException>(),
      );
    });

    test('passes through generic Exception', () {
      final error = Exception('network');
      expect(case_.mapRemoveError(error), same(error));
    });

    test('maps non-Exception to ServerUnknownException', () {
      expect(
        case_.mapRemoveError('oops'),
        isA<ServerUnknownException>(),
      );
    });
  });

  group('mapLinkError', () {
    test('passes through CredentialConflictException', () {
      const error = CredentialConflictException();
      expect(case_.mapLinkError(error), same(error));
    });

    test('maps ServerStatusException 409 to CredentialConflictException', () {
      expect(
        case_.mapLinkError(const ServerStatusException(409)),
        isA<CredentialConflictException>(),
      );
    });

    test('maps other ServerStatusException to ServerUnknownException', () {
      expect(
        case_.mapLinkError(const ServerStatusException(500)),
        isA<ServerUnknownException>(),
      );
    });

    test('passes through generic Exception', () {
      final error = Exception('network');
      expect(case_.mapLinkError(error), same(error));
    });

    test('maps non-Exception to ServerUnknownException', () {
      expect(
        case_.mapLinkError('oops'),
        isA<ServerUnknownException>(),
      );
    });
  });
}

class FakeCredentialsRepository extends Fake implements CredentialsRepository {
  List<CredentialEntity> credentials = [];
  String linkSeedResult = '';
  String googleLinkUrl = '';
  String? removedId;
  String? emailLinkStarted;
  bool linkGoogleNativeCalled = false;

  @override
  Future<List<CredentialEntity>> fetchCredentials() async => credentials;

  @override
  Future<String> linkSeed() async => linkSeedResult;

  @override
  Future<void> linkGoogleNative() async {
    linkGoogleNativeCalled = true;
  }

  @override
  Future<String> fetchGoogleLinkStartUrl() async => googleLinkUrl;

  @override
  Future<void> startEmailLink(String email) async {
    emailLinkStarted = email;
  }

  @override
  Future<void> removeCredential(String id) async {
    removedId = id;
  }
}

class TrackingAuthLocal extends EmptyAuthLocal {
  String accountId = '';
  final linkedSeeds = <({String id, String seed})>[];

  @override
  Future<String> getCurrentAccountId() async => accountId;

  @override
  Future<void> storeLinkedSeedIfAbsent(String id, String seed) async {
    linkedSeeds.add((id: id, seed: seed));
  }
}
