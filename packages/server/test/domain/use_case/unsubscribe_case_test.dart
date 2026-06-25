import 'package:injectable/injectable.dart' show Environment;
import 'package:test/test.dart';

import 'package:tentura_server/domain/entity/digest_cadence.dart';
import 'package:tentura_server/domain/entity/notification_category.dart';
import 'package:tentura_server/domain/entity/notification_preferences_entity.dart';
import 'package:tentura_server/domain/port/notification_preference_repository_port.dart';
import 'package:tentura_server/domain/unsubscribe/unsubscribe_token.dart';
import 'package:tentura_server/domain/use_case/unsubscribe_case.dart';
import 'package:tentura_server/env.dart';

class _CapturingPrefs implements NotificationPreferenceRepositoryPort {
  _CapturingPrefs(this._prefs);

  NotificationPreferencesEntity _prefs;
  NotificationPreferencesEntity? lastUpserted;

  @override
  Future<NotificationPreferencesEntity> getForAccount(String accountId) async =>
      _prefs;

  @override
  Future<void> upsert(NotificationPreferencesEntity prefs) async {
    lastUpserted = prefs;
    _prefs = prefs;
  }

  @override
  dynamic noSuchMethod(Invocation i) => throw UnimplementedError('$i');
}

void main() {
  const accountId = 'acc-1';
  final env = Env(
    environment: Environment.test,
    unsubscribeSigningSecret: 'test-secret',
  );
  const tokenSigner = UnsubscribeToken('test-secret');

  NotificationPreferencesEntity prefs({
    Set<NotificationCategory> email = const {
      NotificationCategory.asksOfMe,
      NotificationCategory.coordination,
    },
    DigestCadence digest = DigestCadence.daily,
  }) =>
      NotificationPreferencesEntity(
        accountId: accountId,
        emailCategories: email,
        emailDigest: digest,
      );

  group('UnsubscribeCase.peek', () {
    test('returns payload for valid token without mutating prefs', () {
      final repo = _CapturingPrefs(prefs());
      final case_ = UnsubscribeCase(repo, env);
      final t = tokenSigner.sign(accountId: accountId, scope: 'asksOfMe');

      final payload = case_.peek(t);

      expect(payload, isNotNull);
      expect(payload!.accountId, accountId);
      expect(payload.scope, 'asksOfMe');
      expect(repo.lastUpserted, isNull);
    });

    test('returns null for invalid token', () {
      final repo = _CapturingPrefs(prefs());
      final case_ = UnsubscribeCase(repo, env);

      expect(case_.peek('bad-token'), isNull);
      expect(repo.lastUpserted, isNull);
    });
  });

  group('UnsubscribeCase.apply', () {
    test('scope all clears email categories and turns digest off', () async {
      final repo = _CapturingPrefs(prefs());
      final case_ = UnsubscribeCase(repo, env);
      final t = tokenSigner.sign(accountId: accountId, scope: 'all');

      final scope = await case_.apply(t);

      expect(scope, 'all');
      expect(repo.lastUpserted, isNotNull);
      expect(repo.lastUpserted!.emailCategories, isEmpty);
      expect(repo.lastUpserted!.emailDigest, DigestCadence.off);
    });

    test('category scope removes that category from email opt-in', () async {
      final repo = _CapturingPrefs(prefs());
      final case_ = UnsubscribeCase(repo, env);
      final t = tokenSigner.sign(accountId: accountId, scope: 'asksOfMe');

      final scope = await case_.apply(t);

      expect(scope, 'asksOfMe');
      expect(repo.lastUpserted!.emailCategories, {
        NotificationCategory.coordination,
      });
      expect(repo.lastUpserted!.emailDigest, DigestCadence.daily);
    });

    test('returns null and skips upsert for invalid token', () async {
      final repo = _CapturingPrefs(prefs());
      final case_ = UnsubscribeCase(repo, env);

      final scope = await case_.apply('not-valid');

      expect(scope, isNull);
      expect(repo.lastUpserted, isNull);
    });
  });
}
