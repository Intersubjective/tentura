import 'dart:math' as math;

import 'package:tentura_root/domain/constellation/constellation_path_resolution.dart';

import '../constellation_sector_arrangement.dart';
import 'layout_geometry.dart';

/// Distance between neighbouring dots inside one overview cluster.
const double kConstellationCommunitySpacing = 36;

/// Overview grouping of the Field by trust: which people form a community,
/// where each dot goes and the direction (radians, scene coordinates) of the
/// sector each community sits in. Exists only as this return value: it is
/// recomputed from the Field, never stored or sent anywhere.
class ConstellationCommunityLayout {
  const ConstellationCommunityLayout({
    required this.communities,
    required this.positions,
    required this.sectorAngles,
  });

  /// Community id → member ids. Ids stay stable across recomputations that
  /// pass the previous layout.
  final Map<String, Set<String>> communities;

  /// Overview position of every Field person.
  final Map<String, LPoint> positions;

  /// Community id → sector direction.
  final Map<String, double> sectorAngles;
}

/// Louvain communities over the [trustEdges] among the people in
/// [fieldPositions], placed as compact clusters around [ego].
///
/// Deterministic for the same input and [seed]. Communities are matched to
/// [previous] by maximum overlap so they keep their ids and sectors. Each
/// community sits in the sector of its members' mean Field direction, pulled
/// towards its pinned members; people in [pinnedPositions] stay where they
/// are pinned.
ConstellationCommunityLayout computeConstellationCommunities({
  required LPoint ego,
  required Map<String, LPoint> fieldPositions,
  required List<ConstellationEdgeRef> trustEdges,
  required Map<String, LPoint> pinnedPositions,
  required int seed,
  ConstellationCommunityLayout? previous,
}) {
  final people = fieldPositions.keys.toList()..sort();
  final partition = _louvain(people, trustEdges, seed);
  final communities = _matchToPrevious(partition, previous);

  final positions = <String, LPoint>{};
  final sectorAngles = <String, double>{};
  for (final MapEntry(key: id, value: members) in communities.entries) {
    final sorted = members.toList()..sort();
    final normal = [for (final member in sorted) fieldPositions[member]!];
    final angle =
        previous?.sectorAngles[id] ??
        constellationSectorCentroidDirection(
          centre: ego,
          points: normal,
          fallback: 0,
        );
    sectorAngles[id] = angle;

    final radius =
        normal.fold<double>(0, (sum, p) => sum + _distance(p, ego)) /
        normal.length;
    var centre = (
      x: ego.x + radius * math.cos(angle),
      y: ego.y + radius * math.sin(angle),
    );
    final pins = [for (final member in sorted) ?pinnedPositions[member]];
    if (pins.isNotEmpty) {
      final pull = pins.length / sorted.length;
      final pinCentre = (
        x: pins.fold<double>(0, (sum, p) => sum + p.x) / pins.length,
        y: pins.fold<double>(0, (sum, p) => sum + p.y) / pins.length,
      );
      centre = (
        x: centre.x + (pinCentre.x - centre.x) * pull,
        y: centre.y + (pinCentre.y - centre.y) * pull,
      );
    }

    // Sunflower spiral: a compact disc whatever the community size.
    var slot = 0;
    for (final member in sorted) {
      if (pinnedPositions[member] case final pin?) {
        positions[member] = pin;
        continue;
      }
      final r = kConstellationCommunitySpacing * math.sqrt(slot + 0.5);
      final theta = slot * math.pi * (3 - math.sqrt(5));
      positions[member] = (
        x: centre.x + r * math.cos(theta),
        y: centre.y + r * math.sin(theta),
      );
      slot++;
    }
  }

  return ConstellationCommunityLayout(
    communities: Map.unmodifiable({
      for (final entry in communities.entries)
        entry.key: Set<String>.unmodifiable(entry.value),
    }),
    positions: Map.unmodifiable(positions),
    sectorAngles: Map.unmodifiable(sectorAngles),
  );
}

double _distance(LPoint a, LPoint b) =>
    math.sqrt(math.pow(a.x - b.x, 2) + math.pow(a.y - b.y, 2));

/// Groups of [people] (sorted) found by Louvain modularity optimisation.
List<Set<String>> _louvain(
  List<String> people,
  List<ConstellationEdgeRef> trustEdges,
  int seed,
) {
  final index = {for (var i = 0; i < people.length; i++) people[i]: i};
  // Undirected weighted graph; mutual trust counts twice.
  var adjacency = [for (final _ in people) <int, double>{}];
  var selfLoops = List<double>.filled(people.length, 0);
  for (final edge in trustEdges) {
    final a = index[edge.src];
    final b = index[edge.dst];
    if (a == null || b == null || a == b) continue;
    adjacency[a][b] = (adjacency[a][b] ?? 0) + 1;
    adjacency[b][a] = (adjacency[b][a] ?? 0) + 1;
  }

  // membership[i]: current super-node of person i.
  final membership = List<int>.generate(people.length, (i) => i);
  final random = math.Random(seed);
  while (true) {
    final n = adjacency.length;
    final degree = [
      for (var i = 0; i < n; i++)
        adjacency[i].values.fold<double>(0, (sum, w) => sum + w) +
            2 * selfLoops[i],
    ];
    final total = degree.fold<double>(0, (sum, k) => sum + k);
    if (total == 0) break;

    final community = List<int>.generate(n, (i) => i);
    final communityDegree = [...degree];
    final order = List<int>.generate(n, (i) => i)..shuffle(random);
    var moved = false;
    var improved = true;
    while (improved) {
      improved = false;
      for (final node in order) {
        final current = community[node];
        communityDegree[current] -= degree[node];
        final links = <int, double>{};
        for (final MapEntry(key: other, value: w) in adjacency[node].entries) {
          links[community[other]] = (links[community[other]] ?? 0) + w;
        }
        var best = current;
        var bestGain =
            (links[current] ?? 0) -
            communityDegree[current] * degree[node] / total;
        for (final MapEntry(key: candidate, value: w) in links.entries) {
          final gain = w - communityDegree[candidate] * degree[node] / total;
          if (gain > bestGain + 1e-12) {
            best = candidate;
            bestGain = gain;
          }
        }
        communityDegree[best] += degree[node];
        if (best != current) {
          community[node] = best;
          improved = true;
          moved = true;
        }
      }
    }
    if (!moved) break;

    // Aggregate each community into one super-node.
    final renumber = <int, int>{};
    for (final c in community) {
      renumber.putIfAbsent(c, () => renumber.length);
    }
    final nextAdjacency = [for (final _ in renumber.keys) <int, double>{}];
    final nextSelfLoops = List<double>.filled(renumber.length, 0);
    for (var i = 0; i < n; i++) {
      final ci = renumber[community[i]]!;
      nextSelfLoops[ci] += selfLoops[i];
      for (final MapEntry(key: j, value: w) in adjacency[i].entries) {
        final cj = renumber[community[j]]!;
        if (ci == cj) {
          nextSelfLoops[ci] += w / 2;
        } else {
          nextAdjacency[ci][cj] = (nextAdjacency[ci][cj] ?? 0) + w;
        }
      }
    }
    for (var p = 0; p < membership.length; p++) {
      membership[p] = renumber[community[membership[p]]]!;
    }
    adjacency = nextAdjacency;
    selfLoops = nextSelfLoops;
  }

  final groups = <int, Set<String>>{};
  for (var p = 0; p < people.length; p++) {
    groups.putIfAbsent(membership[p], () => {}).add(people[p]);
  }
  return groups.values.toList();
}

/// Names [partition]'s groups: the previous community with the largest
/// overlap lends its id; a new group is named after its first member.
Map<String, Set<String>> _matchToPrevious(
  List<Set<String>> partition,
  ConstellationCommunityLayout? previous,
) {
  String firstOf(Set<String> group) => (group.toList()..sort()).first;
  final groups = [...partition]
    ..sort((a, b) => firstOf(a).compareTo(firstOf(b)));
  final pairs =
      <({int group, String id, int overlap})>[
        for (var g = 0; g < groups.length; g++)
          for (final MapEntry(key: id, value: members)
              in previous?.communities.entries ??
                  <MapEntry<String, Set<String>>>[])
            if (members.where(groups[g].contains).length case final overlap
                when overlap > 0)
              (group: g, id: id, overlap: overlap),
      ]..sort((a, b) {
        final byOverlap = b.overlap.compareTo(a.overlap);
        if (byOverlap != 0) return byOverlap;
        final byGroup = a.group.compareTo(b.group);
        return byGroup != 0 ? byGroup : a.id.compareTo(b.id);
      });

  final names = <int, String>{};
  final used = <String>{};
  for (final pair in pairs) {
    if (names.containsKey(pair.group) || used.contains(pair.id)) continue;
    names[pair.group] = pair.id;
    used.add(pair.id);
  }
  // Fresh names must not collide with ids kept from the previous layout.
  final reserved = {...used, ...?previous?.communities.keys};
  for (var g = 0; g < groups.length; g++) {
    if (names.containsKey(g)) continue;
    var name = firstOf(groups[g]);
    for (var suffix = 2; reserved.contains(name); suffix++) {
      name = '${firstOf(groups[g])}#$suffix';
    }
    names[g] = name;
    reserved.add(name);
  }
  return {for (var g = 0; g < groups.length; g++) names[g]!: groups[g]};
}
