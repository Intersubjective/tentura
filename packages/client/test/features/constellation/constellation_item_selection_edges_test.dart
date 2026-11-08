// Selecting a Post or a Request on the Field draws only how the viewer
// reaches it and who takes part in it: the trust path Ego → … → author, the
// author → item hop and the item → participant edges. The author's own trust
// edges to other people (what selecting the author shows) stay hidden.
//
// The author → item edge is not always on: it is drawn only while the item
// itself or its author is selected.
//
// Every test selects through the Field cubit as the Field does and reads the
// rendered scene (the graph topology the edge painter draws).

import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';

import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/env.dart';
import 'package:tentura/features/constellation/domain/entity/constellation_anchor_projection.dart';
import 'package:tentura/features/constellation/domain/entity/constellation_field.dart';
import 'package:tentura/features/constellation/domain/port/constellation_member_webs_port.dart';
import 'package:tentura/features/constellation/domain/port/constellation_repository_port.dart';
import 'package:tentura/features/constellation/domain/use_case/constellation_member_webs_case.dart';
import 'package:tentura/features/constellation/ui/bloc/constellation_cubit.dart';

import '../../support/constellation_store_fixture.dart';

const _ego = 'ego';

/// ego → amy → bob; bob authored the Post and the Request.
const _amy = 'amy';
const _bob = 'bob';

/// Participants of both of bob's items.
const _cat = 'cat';
const _dan = 'dan';

/// People bob trusts: his person-selection fan.
const _eve = 'eve';
const _fay = 'fay';

const _post = 'post-bob';
const _request = 'req-bob';

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

/// The participants of bob's Post and Request (cat inside, dan forwarded),
/// as the server answers when either item is selected — the same answer the
/// Field data carries for the Post.
final class _MemberWebsPort implements ConstellationMemberWebsPort {
  @override
  Future<List<ConstellationMemberWeb>> fetch(String beaconId) async =>
      beaconId == _request || beaconId == _post
      ? _participantsOf(beaconId)
      : const [];
}

List<ConstellationMemberWeb> _participantsOf(String beaconId) => [
  ConstellationMemberWeb(
    beaconId: beaconId,
    personId: _cat,
    state: ConstellationMemberWebState.inside,
  ),
  ConstellationMemberWeb(
    beaconId: beaconId,
    personId: _dan,
    state: ConstellationMemberWebState.forwarded,
  ),
];

ConstellationTrustEdgeEntity _e(String src, String dst) =>
    ConstellationTrustEdgeEntity(src: src, dst: dst, tier: 1);

/// ego → amy → bob explicitly; bob trusts eve and fay. eve and fay hold a
/// Request of their own so they are on the Field whatever is selected. bob
/// holds a Post and a Request, each with participants cat and dan.
ConstellationField _field() {
  final now = DateTime.now().toUtc();
  return ConstellationField(
    loadedAt: now,
    context: '',
    peers: [
      for (final id in [_amy, _bob, _cat, _dan, _eve, _fay])
        ConstellationPerson(id: id, displayName: id),
    ],
    edges: [
      _e(_ego, _amy),
      _e(_amy, _bob),
      _e(_bob, _eve),
      _e(_bob, _fay),
    ],
    directContactIds: const [_amy],
    requests: [
      const ConstellationRequest(
        id: _request,
        authorId: _bob,
        title: 'Move a sofa',
        status: 0,
      ),
      for (final id in [_eve, _fay])
        ConstellationRequest(
          id: 'req-$id',
          authorId: id,
          title: 'Request of $id',
          status: 0,
        ),
    ],
    posts: [
      ConstellationPost(
        id: _post,
        authorId: _bob,
        rootExcerpt: 'Who has a ladder?',
        lastActivityAt: now.subtract(const Duration(hours: 1)),
        expiresAt: now.add(const Duration(hours: 48)),
      ),
    ],
    memberWebs: _participantsOf(_post),
  );
}

Future<ConstellationCubit> _load() async {
  final cubit = ConstellationCubit(
    case_: ConstellationStoreFixture(
      _StubRepository(_field()),
      accountId: _ego,
    ).store,
    viewer: const Profile(id: _ego, displayName: 'Ego'),
    memberWebsCase: ConstellationMemberWebsCase(
      _MemberWebsPort(),
      env: const Env(),
      logger: Logger('test'),
    ),
  );
  addTearDown(cubit.close);
  await cubit.stream.firstWhere((state) => state.status is StateIsSuccess);
  _expectOnField(cubit, [_amy, _bob, _eve, _fay, _post, _request]);
  return cubit;
}

/// Lets member-web answers land and the scene recompose.
Future<void> _settle() async {
  for (var i = 0; i < 20; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

Future<void> _selectItem(ConstellationCubit cubit, String itemId) async {
  cubit.selectRequest(itemId);
  await _settle();
  _expectOnField(cubit, [_cat, _dan]);
}

Future<void> _selectPerson(ConstellationCubit cubit, String personId) async {
  cubit.selectPerson(personId);
  await _settle();
}

Future<void> _clearSelection(ConstellationCubit cubit) async {
  cubit
    ..selectRequest(null)
    ..selectPerson(null);
  await _settle();
  expect(cubit.state.selectedRequestId, isNull);
  expect(cubit.state.selectedPersonId, isNull);
}

/// Domain ids of every node the rendered scene holds.
Set<String> _nodeIds(ConstellationCubit cubit) => {
  for (final node
      in cubit.graphController.renderSnapshot.topology.nodesById.values)
    node.payload.id,
};

void _expectOnField(ConstellationCubit cubit, List<String> ids) => expect(
  _nodeIds(cubit),
  containsAll(ids),
  reason: '$ids must be on the Field for this case',
);

/// Every drawn edge as an undirected pair `x–y` of domain ids (sorted), so
/// the assertion does not depend on direction or edge kind.
Set<String> _drawnPairs(ConstellationCubit cubit) => {
  for (final edge
      in cubit.graphController.renderSnapshot.topology.edgesById.values)
    if (edge.payload.source.id != edge.payload.destination.id)
      _pair(edge.payload.source.id, edge.payload.destination.id),
};

String _pair(String x, String y) => x.compareTo(y) <= 0 ? '$x–$y' : '$y–$x';

/// bob's trust edges to people off the path to him.
final _authorFan = {_pair(_bob, _eve), _pair(_bob, _fay)};

/// The author edges of every Post and Request on the Field.
final _authorEdges = {
  _pair(_bob, _post),
  _pair(_bob, _request),
  _pair(_eve, 'req-$_eve'),
  _pair(_fay, 'req-$_fay'),
};

void main() {
  for (final (item, other, label) in [
    (_post, _request, 'Post'),
    (_request, _post, 'Request'),
  ]) {
    group('selecting a $label', () {
      test("draws none of its author's trust edges to other people", () async {
        final cubit = await _load();

        await _selectItem(cubit, item);

        final drawn = _drawnPairs(cubit);
        expect(
          drawn.intersection(_authorFan),
          isEmpty,
          reason:
              "selecting the $label must not show bob's person fan, drawn: "
              '${drawn.toList()..sort()}',
        );
        expect(
          drawn.where((pair) => pair.contains(_eve) || pair.contains(_fay)),
          isEmpty,
          reason: 'eve and fay are neither on the path nor participants',
        );
      });

      test('draws exactly the path Ego → amy → bob → the $label and its '
          'participant edges', () async {
        final cubit = await _load();

        await _selectItem(cubit, item);

        final drawn = _drawnPairs(cubit);
        // Each hop of the path and each participant edge, named on failure.
        for (final (pair, what) in [
          (_pair(_ego, _amy), 'path hop Ego–amy'),
          (_pair(_amy, _bob), 'path hop amy–bob'),
          (_pair(_bob, item), 'path hop bob–$label'),
          (_pair(item, _cat), '$label–cat participant edge'),
          (_pair(item, _dan), '$label–dan participant edge'),
        ]) {
          expect(drawn, contains(pair), reason: '$what must be drawn');
        }
        expect(
          drawn.toList()..sort(),
          (<String>{
            _pair(_ego, _amy),
            _pair(_amy, _bob),
            _pair(_bob, item),
            _pair(item, _cat),
            _pair(item, _dan),
          }.toList()..sort()),
          reason:
              'only the path and the participants are drawn: no author fan, '
              "no edge of bob's other item ($other), no other author edge",
        );
      });
    });
  }

  group('the author edge of a Post or Request', () {
    test(
      'is not drawn for any Post or Request while nothing is selected',
      () async {
        final cubit = await _load();

        final drawn = _drawnPairs(cubit);
        expect(
          drawn.intersection(_authorEdges),
          isEmpty,
          reason: 'no always-on author edge, drawn: ${drawn.toList()..sort()}',
        );
      },
    );

    for (final (selected, label) in [
      (_amy, 'amy, on the path to the author'),
      (_eve, 'eve, whom the author trusts'),
    ]) {
      test('is not drawn while an unrelated person ($label) is '
          'selected', () async {
        final cubit = await _load();

        await _selectPerson(cubit, selected);

        final drawn = _drawnPairs(cubit);
        expect(drawn, isNot(contains(_pair(_bob, _post))));
        expect(drawn, isNot(contains(_pair(_bob, _request))));
      });
    }

    test("appears for both of the author's items while the author is "
        'selected, next to their usual trust edges, and goes once the '
        'selection is cleared', () async {
      final cubit = await _load();
      expect(
        _drawnPairs(cubit).intersection({
          _pair(_bob, _post),
          _pair(_bob, _request),
        }),
        isEmpty,
        reason: 'nothing selected: no author edge yet',
      );

      await _selectPerson(cubit, _bob);

      final selected = _drawnPairs(cubit);
      expect(selected, contains(_pair(_bob, _post)));
      expect(selected, contains(_pair(_bob, _request)));
      expect(
        selected,
        containsAll(_authorFan),
        reason: 'selecting bob still shows his trust edges to eve and fay',
      );
      expect(
        selected,
        isNot(contains(_pair(_eve, 'req-$_eve'))),
        reason: "eve's Request is not bob's",
      );

      await _clearSelection(cubit);

      final cleared = _drawnPairs(cubit);
      expect(cleared, isNot(contains(_pair(_bob, _post))));
      expect(cleared, isNot(contains(_pair(_bob, _request))));
    });

    for (final (item, label) in [(_post, 'Post'), (_request, 'Request')]) {
      test('appears while the $label is selected and goes once the selection '
          'is cleared', () async {
        final cubit = await _load();
        expect(
          _drawnPairs(cubit),
          isNot(contains(_pair(_bob, item))),
          reason: 'nothing selected: no author edge yet',
        );

        await _selectItem(cubit, item);
        expect(_drawnPairs(cubit), contains(_pair(_bob, item)));

        await _clearSelection(cubit);
        expect(_drawnPairs(cubit), isNot(contains(_pair(_bob, item))));
      });
    }
  });
}
