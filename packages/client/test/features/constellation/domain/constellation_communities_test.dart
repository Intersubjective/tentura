@TestOn('vm')
@Tags(['repo-files'])
library;

import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:test/test.dart';
import 'package:tentura/features/constellation/domain/layout/layout_geometry.dart';
import 'package:tentura_root/domain/constellation/constellation_path_resolution.dart';

const LPoint _ego = (x: 2000, y: 2000);
const _seed = 42;
late Directory _root;
final _history = <Map<String, Object?>>[];
final _observed = <int, _LayoutObservation>{};

// A test observation, not a replacement layout algorithm. Missing output is
// represented by empty observations; no partition or position is fabricated.
class _LayoutObservation {
  _LayoutObservation(this.id, this.data);
  final int id;
  Map<String, Object?> data;

  Map<String, Set<String>> get communities => {
    for (final entry in ((data['communities'] as Map?) ?? {}).entries)
      entry.key as String: Set<String>.from(entry.value as List),
  };
  Map<String, LPoint> get positions => {
    for (final entry in ((data['positions'] as Map?) ?? {}).entries)
      entry.key as String: (
        x: ((entry.value as List)[0] as num).toDouble(),
        y: ((entry.value as List)[1] as num).toDouble(),
      ),
  };
  Map<String, double> get sectorAngles => {
    for (final entry in ((data['sectorAngles'] as Map?) ?? {}).entries)
      entry.key as String: (entry.value as num).toDouble(),
  };
}

void _locateRepo() {
  _root = Directory.current.absolute;
  while (!File('${_root.path}/compose.prod.yaml').existsSync()) {
    if (_root.parent.path == _root.path) {
      throw StateError('Repository not found');
    }
    _root = _root.parent;
  }
}

const _computationLibrary =
    'package:tentura/features/constellation/domain/layout/'
    'constellation_communities.dart';

// The probe is generated so this suite loads while the computation is absent
// (it then reports empty layouts instead of failing to compile). It calls the
// production entry point with a static import and only serialises the
// returned value; it computes no partition or position itself.
String _probeSource({required bool computationExists}) =>
    '''
import 'dart:convert';
import 'dart:io';

import 'package:tentura/features/constellation/domain/layout/layout_geometry.dart';
import 'package:tentura_root/domain/constellation/constellation_path_resolution.dart';
${computationExists ? "import '$_computationLibrary';" : ''}

LPoint point(List<Object?> value) =>
    (x: (value[0]! as num).toDouble(), y: (value[1]! as num).toDouble());

Map<String, LPoint> points(Map<String, Object?> values) => {
  for (final entry in values.entries) entry.key: point(entry.value! as List<Object?>),
};

Map<String, Object?> snapshot(dynamic layout) => layout == null
    ? const {}
    : {
        'communities': {
          for (final entry in (layout.communities as Map).entries)
            entry.key.toString(): (entry.value as Iterable).toList(),
        },
        'positions': {
          for (final entry in (layout.positions as Map).entries)
            entry.key as String: [entry.value.x, entry.value.y],
        },
        'sectorAngles': {
          for (final entry in (layout.sectorAngles as Map).entries)
            entry.key.toString(): entry.value,
        },
      };

void main(List<String> args) {
  final requests = jsonDecode(File(args.single).readAsStringSync()) as List<Object?>;
  final layouts = <int, dynamic>{};
  for (final request in requests.cast<Map<String, Object?>>()) {
    final edges = <ConstellationEdgeRef>[
      for (final edge in (request['trustEdges']! as List<Object?>).cast<Map<String, Object?>>())
        (src: edge['src']! as String, dst: edge['dst']! as String, tier: edge['tier']! as int),
    ];
    final fieldPositions = Map<String, LPoint>.unmodifiable(
      points(request['fieldPositions']! as Map<String, Object?>),
    );
    final pinnedPositions = Map<String, LPoint>.unmodifiable(
      points(request['pinnedPositions']! as Map<String, Object?>),
    );
    final ego = point(request['ego']! as List<Object?>);
    layouts[request['id']! as int] = ${computationExists ? '''
computeConstellationCommunities(
      ego: ego,
      fieldPositions: fieldPositions,
      trustEdges: List<ConstellationEdgeRef>.unmodifiable(edges),
      pinnedPositions: pinnedPositions,
      seed: request['seed']! as int,
      previous: layouts[request['previous']],
    )''' : 'null'};
  }
  stdout.writeln(jsonEncode({
    'layouts': {
      for (final entry in layouts.entries) '\${entry.key}': snapshot(entry.value),
    },
  }));
}
''';

Map<String, Object?> _runProbe(String request) {
  final computationExists = File(
    '${_root.path}/packages/client/lib/'
    '${_computationLibrary.substring('package:tentura/'.length)}',
  ).existsSync();
  final scratch = Directory.systemTemp.createTempSync('community_probe_');
  addTearDown(() => scratch.deleteSync(recursive: true));
  final probe = File('${scratch.path}/probe.dart')
    ..writeAsStringSync(_probeSource(computationExists: computationExists));
  final requests = File('${scratch.path}/requests.json')
    ..writeAsStringSync(request);
  final result = Process.runSync(
    RegExp(r'[/\\]dart(?:\.exe)?$').hasMatch(Platform.resolvedExecutable)
        ? Platform.resolvedExecutable
        : 'dart',
    [
      '--packages=${_root.path}/.dart_tool/package_config.json',
      probe.path,
      requests.path,
    ],
  );
  expect(
    result.exitCode,
    0,
    reason: 'The probe calling $_computationLibrary must run: ${result.stderr}',
  );
  return jsonDecode(result.stdout as String) as Map<String, Object?>;
}

const _groups = [
  ['a0', 'a1', 'a2', 'a3', 'a4'],
  ['b0', 'b1', 'b2', 'b3', 'b4'],
  ['c0', 'c1', 'c2', 'c3', 'c4'],
];

// Normal Field positions point east, north and west. Trust, rather than
// coordinates or labels, must determine the partition.
Map<String, LPoint> _fieldPositions() => {
  for (var g = 0; g < _groups.length; g++)
    for (var i = 0; i < _groups[g].length; i++)
      _groups[g][i]: (
        x: _ego.x + (900 + i * 25) * math.cos(g * math.pi / 2),
        y: _ego.y + (900 + i * 25) * math.sin(g * math.pi / 2),
      ),
};

List<ConstellationEdgeRef> _trustEdges() => [
  for (final group in _groups)
    for (var i = 0; i < group.length; i++)
      for (var j = i + 1; j < group.length; j++)
        if (!(group[i] == 'a0' && group[j] == 'a4'))
          (src: group[i], dst: group[j], tier: 1),
  // One connected component still has two densely connected communities.
  (src: 'a4', dst: 'b0', tier: 1),
];

_LayoutObservation _layout({
  Map<String, LPoint>? fieldPositions,
  List<ConstellationEdgeRef>? trustEdges,
  Map<String, LPoint> pinnedPositions = const {},
  _LayoutObservation? previous,
}) {
  final id = _history.length;
  _history.add({
    'id': id,
    'ego': [_ego.x, _ego.y],
    'fieldPositions': {
      for (final entry in (fieldPositions ?? _fieldPositions()).entries)
        entry.key: [entry.value.x, entry.value.y],
    },
    'trustEdges': [
      for (final edge in trustEdges ?? _trustEdges())
        {'src': edge.src, 'dst': edge.dst, 'tier': edge.tier},
    ],
    'pinnedPositions': {
      for (final entry in pinnedPositions.entries)
        entry.key: [entry.value.x, entry.value.y],
    },
    'seed': _seed,
    'previous': previous?.id,
  });
  // Replay this test's calls in one VM so repeat-call determinism, previous
  // result mutation and edgeless/full-graph interleaving remain observable.
  final reply = _runProbe(jsonEncode(_history));
  final layouts = reply['layouts']! as Map<String, Object?>;
  final observation = _LayoutObservation(
    id,
    layouts['$id']! as Map<String, Object?>,
  );
  _observed[id] = observation;
  for (final entry in _observed.entries) {
    entry.value.data = layouts['${entry.key}']! as Map<String, Object?>;
  }
  return observation;
}

String _communityOf(_LayoutObservation layout, String personId) {
  final containing = layout.communities.entries
      .where((entry) => entry.value.contains(personId))
      .toList();
  expect(
    containing,
    hasLength(1),
    reason: '$personId belongs to exactly one returned community',
  );
  return containing.single.key;
}

LPoint _position(_LayoutObservation layout, String id) {
  expect(
    layout.positions,
    contains(id),
    reason: '$id needs an overview position',
  );
  return layout.positions[id]!;
}

LPoint _centroid(Iterable<LPoint> positions) {
  final points = positions.toList();
  return (
    x: points.fold<double>(0, (sum, p) => sum + p.x) / points.length,
    y: points.fold<double>(0, (sum, p) => sum + p.y) / points.length,
  );
}

double _distance(LPoint a, LPoint b) =>
    math.sqrt(math.pow(a.x - b.x, 2) + math.pow(a.y - b.y, 2));

double _direction(LPoint point) =>
    math.atan2(point.y - _ego.y, point.x - _ego.x);

double _angleGap(double a, double b) {
  final gap = (a - b) % (2 * math.pi);
  return math.min(gap, 2 * math.pi - gap);
}

void _expectSameLayout(
  _LayoutObservation actual,
  _LayoutObservation expected,
) {
  expect(actual.positions.keys, unorderedEquals(_fieldPositions().keys));
  expect(
    actual.communities.values,
    unorderedEquals(expected.communities.values),
  );
  expect(actual.positions, equals(expected.positions));
  for (final community in expected.communities.entries) {
    final actualId = _communityOf(actual, community.value.first);
    expect(actual.sectorAngles[actualId], expected.sectorAngles[community.key]);
  }
}

void main() {
  setUpAll(_locateRepo);
  setUp(() {
    _history.clear();
    _observed.clear();
  });
  group('Trust communities at overview', () {
    test('dense trust groups remain separate across a sparse bridge', () {
      final result = _layout();

      expect(result.communities.values, unorderedEquals(_groups.map(toSet)));
      expect(result.positions.keys, unorderedEquals(_fieldPositions().keys));
      final members = result.communities.values.expand((ids) => ids).toList();
      expect(members, unorderedEquals(_fieldPositions().keys));
      expect(members.toSet(), hasLength(members.length));
      for (final position in result.positions.values) {
        expect(position.x.isFinite && position.y.isFinite, isTrue);
      }
    });

    test(
      'the same graph and fixed seed give identical partitions and positions',
      () {
        final first = _layout();
        for (var run = 0; run < 5; run++) {
          _expectSameLayout(_layout(), first);
        }
      },
    );

    test(
      'trust edges determine communities even when normal positions coincide',
      () {
        final result = _layout(
          fieldPositions: {
            for (final id in _fieldPositions().keys)
              id: (x: _ego.x + 900, y: _ego.y),
          },
        );

        expect(result.communities.values, unorderedEquals(_groups.map(toSet)));
      },
    );

    test(
      'rewiring trust changes communities while ids and normal positions stay fixed',
      () {
        const rewiredGroups = [
          ['a0', 'b1', 'c2', 'a3', 'b4'],
          ['b0', 'c1', 'a2', 'b3', 'c4'],
          ['c0', 'a1', 'b2', 'c3', 'a4'],
        ];
        final original = _layout();
        final rewired = _layout(
          trustEdges: [
            for (final group in rewiredGroups)
              for (var i = 0; i < group.length; i++)
                for (var j = i + 1; j < group.length; j++)
                  (src: group[i], dst: group[j], tier: 1),
            (src: 'b4', dst: 'b0', tier: 1),
          ],
        );

        expect(
          original.communities.values,
          unorderedEquals(_groups.map(toSet)),
        );
        expect(
          rewired.communities.values,
          unorderedEquals(rewiredGroups.map(toSet)),
        );
        expect(
          rewired.communities.values,
          isNot(unorderedEquals(original.communities.values)),
        );
      },
    );

    test('only trust edges between Field people influence the result', () {
      final result = _layout(
        trustEdges: [
          ..._trustEdges(),
          for (final id in _fieldPositions().keys)
            (src: id, dst: 'outside-field', tier: 1),
          (src: 'outside-field', dst: 'another-outsider', tier: 1),
        ],
      );

      _expectSameLayout(result, _layout());
      expect(result.positions, isNot(contains('outside-field')));
    });

    test(
      'each unpinned community forms a compact cluster in its mean Field direction',
      () {
        final result = _layout();
        final normal = _fieldPositions();

        for (final group in _groups) {
          final centre = _centroid(group.map((id) => _position(result, id)));
          final normalCentre = _centroid(group.map((id) => normal[id]!));
          final otherCentres = [
            for (final other in _groups)
              if (other != group)
                _centroid(other.map((id) => _position(result, id))),
          ];
          final nearestOther = otherCentres
              .map((other) => _distance(centre, other))
              .reduce(math.min);

          expect(
            _angleGap(_direction(centre), _direction(normalCentre)),
            lessThan(0.3),
          );
          for (final id in group) {
            expect(
              _distance(_position(result, id), centre),
              lessThan(nearestOther / 2),
            );
          }
        }
      },
    );

    test(
      'adding an edge preserves unaffected community identities and sectors',
      () {
        final previous = _layout();
        final next = _layout(
          trustEdges: [
            ..._trustEdges(),
            (src: 'a0', dst: 'a4', tier: 1),
          ],
          previous: previous,
        );

        for (final group in _groups.skip(1)) {
          final oldId = _communityOf(previous, group.first);
          final newId = _communityOf(next, group.first);
          expect(next.communities[newId], unorderedEquals(group));
          expect(
            newId,
            oldId,
            reason: 'maximum-overlap matching keeps identity',
          );
          expect(
            _angleGap(next.sectorAngles[newId]!, previous.sectorAngles[oldId]!),
            lessThan(1e-9),
          );
          final oldCentre = _centroid(
            group.map((id) => _position(previous, id)),
          );
          final newCentre = _centroid(group.map((id) => _position(next, id)));
          expect(
            _angleGap(_direction(newCentre), _direction(oldCentre)),
            lessThan(0.3),
          );
        }
      },
    );

    test(
      'pinned people retain exact coordinates during initial and updated placement',
      () {
        const pins = <String, LPoint>{
          'a0': (x: 1100.125, y: 1700.75),
          'b3': (x: 2720.5, y: 2399.875),
        };
        final previous = _layout(pinnedPositions: pins);
        final next = _layout(
          pinnedPositions: pins,
          trustEdges: [..._trustEdges(), (src: 'a0', dst: 'a4', tier: 1)],
          previous: previous,
        );

        for (final pin in pins.entries) {
          expect(previous.positions[pin.key], pin.value);
          expect(next.positions[pin.key], pin.value);
        }
      },
    );

    test('a community is pulled towards its pinned members', () {
      const pins = <String, LPoint>{
        'a0': (x: 1000, y: 1950),
        'a1': (x: 1000, y: 2000),
        'a2': (x: 1000, y: 2050),
      };
      final automatic = _layout();
      final pinned = _layout(pinnedPositions: pins);
      final pinCentre = _centroid(pins.values);
      const unpinnedIds = ['a3', 'a4'];
      final before = _centroid(
        unpinnedIds.map((id) => _position(automatic, id)),
      );
      final after = _centroid(unpinnedIds.map((id) => _position(pinned, id)));

      expect(
        _distance(after, pinCentre),
        lessThan(_distance(before, pinCentre)),
      );
      for (final pin in pins.entries) {
        expect(pinned.positions[pin.key], pin.value);
      }
    });

    test(
      'community results leave Field positions, edges, pins and previous results untouched',
      () {
        final positions = _fieldPositions();
        final edges = _trustEdges();
        const pins = <String, LPoint>{'a0': (x: 1120, y: 1750)};
        final previous = _layout(pinnedPositions: pins);
        final previousCommunities = <String, Set<String>>{
          for (final entry in previous.communities.entries)
            entry.key: <String>{...entry.value},
        };
        final previousPositions = <String, LPoint>{...previous.positions};
        final previousSectors = <String, double>{...previous.sectorAngles};

        final result = _layout(
          fieldPositions: Map.unmodifiable(positions),
          trustEdges: List.unmodifiable(edges),
          pinnedPositions: Map.unmodifiable(pins),
          previous: previous,
        );

        expect(positions, equals(_fieldPositions()));
        expect(edges, equals(_trustEdges()));
        expect(pins, equals({'a0': (x: 1120.0, y: 1750.0)}));
        expect(previous.communities, equals(previousCommunities));
        expect(previous.positions, equals(previousPositions));
        expect(previous.sectorAngles, equals(previousSectors));
        expect(result.communities.values, unorderedEquals(_groups.map(toSet)));
      },
    );

    test(
      'edgeless graphs have singleton communities and do not affect later layouts',
      () {
        final first = _layout();
        final edgeless = _layout(trustEdges: const []);
        expect(
          edgeless.communities.values,
          unorderedEquals([
            for (final id in _fieldPositions().keys) {id},
          ]),
        );

        _expectSameLayout(_layout(), first);
      },
    );
  });
}

Set<String> toSet(List<String> ids) => ids.toSet();
