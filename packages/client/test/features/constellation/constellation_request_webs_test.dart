import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';

import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/env.dart';
import 'package:tentura/features/constellation/domain/entity/constellation_anchor_projection.dart';
import 'package:tentura/features/constellation/domain/entity/constellation_field.dart';
import 'package:tentura/features/constellation/domain/port/constellation_member_webs_port.dart';
import 'package:tentura/features/constellation/domain/port/constellation_repository_port.dart';
import 'package:tentura/features/constellation/domain/use_case/constellation_field_case.dart';
import 'package:tentura/features/constellation/ui/bloc/constellation_cubit.dart';
import 'package:tentura/ui/bloc/screen_cubit.dart';

final _loadedAt = DateTime.utc(2026, 10, 3, 12);

final class _StubRepository implements ConstellationRepositoryPort {
  _StubRepository(this.field);

  final ConstellationField field;

  @override
  Future<ConstellationField> fetch({
    ConstellationFieldMembershipFilters membershipFilters =
        ConstellationFieldMembershipFilters.defaults,
    ConstellationProjection projection = ConstellationProjection.full,
  }) async => field;
}

/// Records every lazy member-web fetch; answers from [websByBeaconId].
final class _RecordingMemberWebsPort implements ConstellationMemberWebsPort {
  _RecordingMemberWebsPort(this.websByBeaconId);

  final Map<String, List<ConstellationMemberWeb>> websByBeaconId;
  final List<String> fetchedBeaconIds = [];

  @override
  Future<List<ConstellationMemberWeb>> fetch(String beaconId) async {
    fetchedBeaconIds.add(beaconId);
    return websByBeaconId[beaconId] ?? const [];
  }
}

ConstellationField _field({required bool withPost}) => ConstellationField(
  loadedAt: _loadedAt,
  context: '',
  peers: [
    const ConstellationPerson(id: 'a'),
    const ConstellationPerson(id: 'b'),
  ],
  edges: [
    const ConstellationTrustEdgeEntity(src: 'ego', dst: 'a', tier: 1),
    const ConstellationTrustEdgeEntity(src: 'ego', dst: 'b', tier: 1),
  ],
  requests: const [
    ConstellationRequest(
      id: 'req-1',
      authorId: 'a',
      title: 'Need a ladder',
      status: 0,
    ),
  ],
  posts: [
    if (withPost)
      ConstellationPost(
        id: 'post-1',
        authorId: 'a',
        rootExcerpt: 'Who has a ladder?',
        lastActivityAt: _loadedAt.subtract(const Duration(hours: 1)),
      ),
  ],
);

const _req1Webs = [
  ConstellationMemberWeb(
    beaconId: 'req-1',
    personId: 'a',
    state: ConstellationMemberWebState.inside,
  ),
  ConstellationMemberWeb(
    beaconId: 'req-1',
    personId: 'b',
    state: ConstellationMemberWebState.forwarded,
  ),
];

Future<ConstellationCubit> _load(
  _RecordingMemberWebsPort port, {
  required bool withPost,
}) async {
  final cubit = ConstellationCubit(
    case_: ConstellationFieldCase(
      _StubRepository(_field(withPost: withPost)),
      env: const Env.fromEnvironment(),
      logger: Logger('ConstellationRequestWebsTest'),
    ),
    viewer: const Profile(id: 'ego', displayName: 'Ego'),
    memberWebsPort: port,
  );
  await cubit.stream.firstWhere((state) => state.status is StateIsSuccess);
  return cubit;
}

Set<String> _webIds(ConstellationCubit cubit) => cubit.graphController.edges
    .map((e) => e.semanticId)
    .where((id) => id.endsWith('#webForwarded') || id.endsWith('#webInside'))
    .toSet();

/// Lets any (wrongly) pending work run; for asserting that nothing happens.
Future<void> _flush() async {
  for (var i = 0; i < 10; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

/// Waits until [condition] holds, polling for a bounded time.
Future<void> _until(bool Function() condition) async {
  for (var i = 0; i < 100 && !condition(); i++) {
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
  expect(condition(), isTrue, reason: 'condition not reached in time');
}

/// Semantic ids of every edge in the rendered scene topology.
Set<String> _sceneSemanticIds(ConstellationCubit cubit) => cubit
    .graphController
    .renderSnapshot
    .topology
    .edgesById
    .values
    .map((e) => e.payload.semanticId)
    .toSet();

Set<String> _sceneWebIds(ConstellationCubit cubit) =>
    _sceneSemanticIds(cubit).where((id) => id.contains('#web')).toSet();

const _req1WebIds = {
  'fr:req-1->fp:a#webInside',
  'fr:req-1->fp:b#webForwarded',
};

void main() {
  for (final withPost in [true, false]) {
    _requestWebsSuite(
      withPost
          ? 'Request member webs on selection (field has a Post)'
          : 'Request member webs on selection (field has only Requests)',
      withPost: withPost,
    );
  }
}

void _requestWebsSuite(String title, {required bool withPost}) {
  group(title, () {
    late _RecordingMemberWebsPort port;
    late ConstellationCubit cubit;

    setUp(() async {
      port = _RecordingMemberWebsPort({'req-1': _req1Webs});
      cubit = await _load(port, withPost: withPost);
    });

    tearDown(() => cubit.close());

    test(
      'selecting a Request fetches its webs once and draws them by state',
      () async {
        cubit.selectRequest('req-1');
        await _until(() => _webIds(cubit).isNotEmpty);
        await _flush();

        expect(port.fetchedBeaconIds, ['req-1']);
        expect(_webIds(cubit), _req1WebIds);
        expect(_sceneSemanticIds(cubit), containsAll(_req1WebIds));
      },
    );

    test('deselecting the Request removes its webs from the graph and scene '
        'without another fetch', () async {
      cubit.selectRequest('req-1');
      await _until(() => _webIds(cubit).isNotEmpty);
      await _until(() => _sceneWebIds(cubit).isNotEmpty);

      cubit.selectRequest(null);
      await _until(() => _webIds(cubit).isEmpty && _sceneWebIds(cubit).isEmpty);
      await _flush();

      expect(_webIds(cubit), isEmpty);
      expect(_sceneWebIds(cubit), isEmpty);
      expect(port.fetchedBeaconIds, ['req-1']);
    });

    test(
      'reselecting a Request draws the cached webs without refetching',
      () async {
        cubit.selectRequest('req-1');
        await _until(() => _webIds(cubit).isNotEmpty);
        cubit.selectRequest(null);
        await _until(
          () => _webIds(cubit).isEmpty && _sceneWebIds(cubit).isEmpty,
        );

        cubit.selectRequest('req-1');
        await _until(() => _webIds(cubit).isNotEmpty);
        await _flush();

        expect(port.fetchedBeaconIds, ['req-1']);
        expect(_webIds(cubit), _req1WebIds);
        expect(_sceneSemanticIds(cubit), containsAll(_req1WebIds));
      },
    );
  });
}
