import 'package:logging/logging.dart';
import 'package:injectable/injectable.dart' show Environment;
import 'package:test/test.dart';

import 'package:tentura_server/domain/entity/realtime_watch_grant.dart';
import 'package:tentura_server/domain/port/realtime_watch_authorization_port.dart';
import 'package:tentura_server/domain/use_case/realtime_watch_grant_case.dart';
import 'package:tentura_server/env.dart';

const _viewerId = 'Uaaaaaaaaaaaa';
const _otherAccountId = 'Ubbbbbbbbbbbb';
const _allowedId = 'U111111111111';
const _deniedId = 'U222222222222';

void main() {
  test(
    'issue intersects requested IDs and verify binds account and scope',
    () async {
      final case_ = _case(_FixedAuthorizationPort({_allowedId}));
      final grant = await case_.issue(
        viewerId: _viewerId,
        descriptor: const RealtimeWatchDescriptor(
          scope: RealtimeWatchScope.graph,
          requestedSubjectIds: {_allowedId, _deniedId},
          focusId: _viewerId,
          context: '',
          positiveOnly: true,
        ),
      );

      expect(grant.authorizedSubjectIds, {_allowedId});
      final claims = case_.verify(
        token: grant.token,
        accountId: _viewerId,
        expectedScope: RealtimeWatchScope.graph,
      );
      expect(claims?.subjectIds, {_allowedId});
      expect(
        case_.verify(token: grant.token, accountId: _otherAccountId),
        isNull,
      );
      expect(
        case_.verify(
          token: grant.token,
          accountId: _viewerId,
          expectedScope: RealtimeWatchScope.people,
        ),
        isNull,
      );
      expect(
        case_.verify(token: '${grant.token}forged', accountId: _viewerId),
        isNull,
      );
    },
  );

  test('expired grant and malformed descriptors fail closed', () async {
    final expiredCase = _case(
      _FixedAuthorizationPort({_allowedId}),
      ttl: const Duration(seconds: -1),
    );
    final expired = await expiredCase.issue(
      viewerId: _viewerId,
      descriptor: const RealtimeWatchDescriptor(
        scope: RealtimeWatchScope.profile,
        requestedSubjectIds: {_allowedId},
        profileId: _allowedId,
      ),
    );
    expect(
      expiredCase.verify(token: expired.token, accountId: _viewerId),
      isNull,
    );

    final case_ = _case(_FixedAuthorizationPort({_allowedId}));
    await expectLater(
      case_.issue(
        viewerId: _viewerId,
        descriptor: const RealtimeWatchDescriptor(
          scope: RealtimeWatchScope.profile,
          requestedSubjectIds: {_allowedId},
          profileId: _deniedId,
        ),
      ),
      throwsA(isA<FormatException>()),
    );
  });

  test('subject count and bytes are bounded before authorization', () async {
    final port = _CountingAuthorizationPort();
    final case_ = RealtimeWatchGrantCase(
      port,
      env: Env(
        environment: Environment.test,
        realtimeWatchMaxSubjects: 1,
      ),
      logger: Logger('RealtimeWatchGrantCaseTest'),
    );
    await expectLater(
      case_.issue(
        viewerId: _viewerId,
        descriptor: const RealtimeWatchDescriptor(
          scope: RealtimeWatchScope.graph,
          requestedSubjectIds: {_allowedId, _deniedId},
          focusId: _viewerId,
          context: '',
          positiveOnly: false,
        ),
      ),
      throwsA(isA<FormatException>()),
    );
    expect(port.calls, 0);
  });
}

RealtimeWatchGrantCase _case(
  RealtimeWatchAuthorizationPort port, {
  Duration ttl = const Duration(minutes: 2),
}) => RealtimeWatchGrantCase(
  port,
  env: Env(environment: Environment.test, realtimeWatchGrantTtl: ttl),
  logger: Logger('RealtimeWatchGrantCaseTest'),
);

final class _FixedAuthorizationPort implements RealtimeWatchAuthorizationPort {
  const _FixedAuthorizationPort(this.authorized);

  final Set<String> authorized;

  @override
  Future<Set<String>> authorizeSubjects({
    required String viewerId,
    required RealtimeWatchDescriptor descriptor,
  }) async => authorized;
}

final class _CountingAuthorizationPort
    implements RealtimeWatchAuthorizationPort {
  int calls = 0;

  @override
  Future<Set<String>> authorizeSubjects({
    required String viewerId,
    required RealtimeWatchDescriptor descriptor,
  }) async {
    calls++;
    return descriptor.requestedSubjectIds;
  }
}
