// Pins error propagation of the two parallel loads in the profile_view
// feature: ProfileViewCase.load and ProfileSharedBeaconsRepository.fetch.
// When one of the parallel futures fails, the caller must see that future's
// original exception (not a wrapper such as ParallelWaitError), and when both
// fail the first error to arrive wins.
import 'dart:async';

import 'package:ferry/ferry.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';

import 'package:tentura/data/service/remote_api_client/remote_request_client.dart';
import 'package:tentura/domain/capability/person_capability_cues.dart';
import 'package:tentura/domain/contacts/contact_name_store.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/domain/port/capability_repository_port.dart';
import 'package:tentura/env.dart';
import 'package:tentura/features/contacts/domain/use_case/contacts_case.dart';
import 'package:tentura/features/like/data/repository/like_remote_repository.dart';
import 'package:tentura/features/profile/domain/port/profile_repository_port.dart';
import 'package:tentura/features/profile_view/data/gql/_g/profile_shared_beacons_fetch.data.gql.dart';
import 'package:tentura/features/profile_view/data/gql/_g/profile_shared_beacons_fetch.req.gql.dart';
import 'package:tentura/features/profile_view/data/repository/profile_shared_beacons_repository.dart';
import 'package:tentura/features/profile_view/domain/use_case/profile_view_case.dart';

import '../../support/fake_person_shared_context_port.dart';
import '../../support/test_realtime_sync.dart';
import '../auth/auth_test_helpers.dart';
import '../contacts/contacts_case_test.dart';

class _ProfileBoom implements Exception {}

class _CuesBoom implements Exception {}

class _ForwardedBoom implements Exception {}

class _CoHelpBoom implements Exception {}

Future<T> _failAfter<T>(Exception error, Duration delay) =>
    Future<T>.delayed(delay, () => throw error);

final class _FakeProfiles implements ProfileRepositoryPort {
  _FakeProfiles(this.result);

  final Future<Profile> Function() result;

  @override
  Future<Profile> fetchById(String id) => result();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _FakeCapabilities implements CapabilityRepositoryPort {
  _FakeCapabilities(this.result);

  final Future<PersonCapabilityCues> Function() result;

  @override
  Future<PersonCapabilityCues> fetchCues(String subjectId) => result();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _UnusedLikes implements LikeRemoteRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Fails each shared-beacons query with its own error after its own delay.
final class _PerQueryErrorClient implements RemoteRequestClient {
  _PerQueryErrorClient({
    this.forwardedError,
    this.forwardedDelay = Duration.zero,
    this.coHelpError,
    this.coHelpDelay = Duration.zero,
  });

  final Exception? forwardedError;
  final Duration forwardedDelay;
  final Exception? coHelpError;
  final Duration coHelpDelay;

  @override
  Stream<OperationResponse<TData, TVars>> request<TData, TVars>(
    OperationRequest<TData, TVars> request, [
    Stream<OperationResponse<TData, TVars>> Function(
      OperationRequest<TData, TVars>,
    )?
    forward,
  ]) {
    final (error, delay, emptyData) = switch (request) {
      GProfileForwardedToUserReq() => (
        forwardedError,
        forwardedDelay,
        GProfileForwardedToUserData() as Object,
      ),
      GProfileCoCommittedReq() => (
        coHelpError,
        coHelpDelay,
        GProfileCoCommittedData() as Object,
      ),
      _ => throw UnsupportedError('unexpected request $request'),
    };
    // A query with no configured error answers with an empty Link response.
    if (error == null) {
      return Stream.value(
        OperationResponse<TData, TVars>(
          operationRequest: request,
          data: emptyData as TData,
          dataSource: DataSource.Link,
        ),
      );
    }
    return Stream.fromFuture(
      _failAfter<OperationResponse<TData, TVars>>(error, delay),
    );
  }
}

void main() {
  group('ProfileViewCase.load parallel error propagation', () {
    final cleanups = <Future<void> Function()>[];

    tearDown(() async {
      for (final cleanup in cleanups.reversed) {
        await cleanup();
      }
      cleanups.clear();
    });

    ProfileViewCase buildCase({
      required Future<Profile> Function() profile,
      required Future<PersonCapabilityCues> Function() cues,
    }) {
      final authLocal = StreamingAuthLocal();
      final contactStore = ContactNameStore();
      final realtime = buildTestRealtimeSync();
      final contactsCase = ContactsCase(
        FakeContactsRepository(),
        buildTestAuthCase(authLocal, EmptyAuthRemote()),
        contactStore,
        realtime.case_,
        env: const Env(),
        logger: Logger('test'),
      );
      cleanups
        ..add(authLocal.dispose)
        ..add(contactStore.dispose)
        ..add(realtime.port.dispose)
        ..add(contactsCase.dispose);
      return ProfileViewCase(
        _FakeProfiles(profile),
        _UnusedLikes(),
        _FakeCapabilities(cues),
        contactsCase,
        realtime.case_,
        FakePersonSharedContextPort(),
        env: const Env(),
        logger: Logger('test'),
      );
    }

    test('profile failure reaches the caller as the original error', () {
      final case_ = buildCase(
        profile: () => _failAfter(_ProfileBoom(), Duration.zero),
        cues: () async => PersonCapabilityCues.empty,
      );

      expect(case_.load('U-target'), throwsA(isA<_ProfileBoom>()));
    });

    test('cues failure reaches the caller as the original error', () {
      final case_ = buildCase(
        profile: () async => const Profile(id: 'U-target'),
        cues: () => _failAfter(_CuesBoom(), Duration.zero),
      );

      expect(case_.load('U-target'), throwsA(isA<_CuesBoom>()));
    });

    test('both fail: the first error to arrive wins', () async {
      final cuesFirst = buildCase(
        profile: () =>
            _failAfter(_ProfileBoom(), const Duration(milliseconds: 20)),
        cues: () => _failAfter(_CuesBoom(), Duration.zero),
      );
      await expectLater(
        cuesFirst.load('U-target'),
        throwsA(isA<_CuesBoom>()),
      );

      final profileFirst = buildCase(
        profile: () => _failAfter(_ProfileBoom(), Duration.zero),
        cues: () => _failAfter(_CuesBoom(), const Duration(milliseconds: 20)),
      );
      await expectLater(
        profileFirst.load('U-target'),
        throwsA(isA<_ProfileBoom>()),
      );
    });
  });

  group('ProfileSharedBeaconsRepository.fetch parallel error propagation', () {
    Future<ProfileSharedBeaconsData> fetchWith(_PerQueryErrorClient client) =>
        ProfileSharedBeaconsRepository(
          client,
        ).fetch(meId: 'U-me', targetId: 'U-target');

    test('forwarded failure reaches the caller as the original error', () {
      expect(
        fetchWith(_PerQueryErrorClient(forwardedError: _ForwardedBoom())),
        throwsA(isA<_ForwardedBoom>()),
      );
    });

    test('co-help failure reaches the caller as the original error', () {
      expect(
        fetchWith(_PerQueryErrorClient(coHelpError: _CoHelpBoom())),
        throwsA(isA<_CoHelpBoom>()),
      );
    });

    test('both fail: the first error to arrive wins', () async {
      await expectLater(
        fetchWith(
          _PerQueryErrorClient(
            forwardedError: _ForwardedBoom(),
            forwardedDelay: const Duration(milliseconds: 20),
            coHelpError: _CoHelpBoom(),
          ),
        ),
        throwsA(isA<_CoHelpBoom>()),
      );
      await expectLater(
        fetchWith(
          _PerQueryErrorClient(
            forwardedError: _ForwardedBoom(),
            coHelpError: _CoHelpBoom(),
            coHelpDelay: const Duration(milliseconds: 20),
          ),
        ),
        throwsA(isA<_ForwardedBoom>()),
      );
    });
  });
}
