import 'dart:math' as math;
import 'dart:ui' show Offset;

import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart' show immutable;
import 'package:force_directed_graphview/force_directed_graphview.dart';

import 'package:tentura/features/constellation/domain/constellation_drag_cluster.dart';
import 'package:tentura/features/constellation/domain/layout/constellation_magnet_layout.dart';
import 'package:tentura/features/constellation/domain/layout/layout_geometry.dart';
import 'package:tentura/features/graph/ui/utils/graph_scene_ids.dart';

/// Magnets bias free members after normal layout. Clean priors keep repeated
/// layout passes from compounding the attraction or moving unrelated people.
///
/// When [peopleInTag] / [tagsOfPerson] are set (#1020), newcomers without a
/// prior sit near their tag area centroid (or between areas), then the magnet
/// pass runs as before. A cold layout (no previous positions) has no
/// newcomers.
@immutable
class ConstellationMagnetLayout implements SceneLayoutAlgorithm {
  ConstellationMagnetLayout({
    required this.base,
    required this.viewerId,
    required this.tagsOfPerson,
    required this.peopleInTag,
    required Map<String, ScenePoint> priors,
    required Map<String, List<LPoint>> magnetsByPerson,
    required Map<String, String> followers,
    Map<String, Offset> tagMagnetOffsets = const {},
  }) : priors = Map.unmodifiable(priors),
       magnetsByPerson = Map.unmodifiable({
         for (final e in magnetsByPerson.entries)
           e.key: List<LPoint>.unmodifiable(e.value),
       }),
       followers = Map.unmodifiable(followers),
       tagMagnetOffsets = Map.unmodifiable(tagMagnetOffsets);

  final SceneLayoutAlgorithm base;
  final String viewerId;
  final Set<String> Function(String personId) tagsOfPerson;
  final Set<String> Function(String tagId) peopleInTag;
  final Map<String, ScenePoint> priors;
  final Map<String, List<LPoint>> magnetsByPerson;
  final Map<String, String> followers;
  final Map<String, Offset> tagMagnetOffsets;

  static const _equality = DeepCollectionEquality();

  GraphNodeId _personGid(String domainId) =>
      '${TenturaGraphNodeKind.fieldPerson}:$domainId';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ConstellationMagnetLayout &&
          base == other.base &&
          viewerId == other.viewerId &&
          tagsOfPerson == other.tagsOfPerson &&
          peopleInTag == other.peopleInTag &&
          _equality.equals(priors, other.priors) &&
          _equality.equals(magnetsByPerson, other.magnetsByPerson) &&
          _equality.equals(followers, other.followers) &&
          _equality.equals(tagMagnetOffsets, other.tagMagnetOffsets);

  @override
  int get hashCode => Object.hash(
    base,
    viewerId,
    tagsOfPerson,
    peopleInTag,
    _equality.hash(priors),
    _equality.hash(magnetsByPerson),
    _equality.hash(followers),
    _equality.hash(tagMagnetOffsets),
  );

  bool _positionIsFixed(
    GraphLayoutRequest request,
    GraphNodeId graphNodeId,
  ) {
    final node = request.nodesById[graphNodeId];
    if (node?.simulationFixed ?? false) {
      return true;
    }
    if (priors.containsKey(graphNodeId)) {
      return true;
    }
    final prev = request.previous?.positions[graphNodeId];
    return prev != null;
  }

  LSize _sizeFor(GraphLayoutRequest request, GraphNodeId id) {
    final raw = request.nodesById[id]?.size;
    if (raw == null) {
      return (
        w: kConstellationDragPersonBodySize.width,
        h: kConstellationDragPersonBodySize.height,
      );
    }
    return (w: raw.width, h: raw.height);
  }

  Iterable<LPoint> _memberCentresExcluding({
    required Map<GraphNodeId, ScenePoint> positions,
    required Iterable<String> memberDomainIds,
    required String excludeDomainId,
  }) sync* {
    for (final id in memberDomainIds) {
      if (id == excludeDomainId) continue;
      final g = _personGid(id);
      final at = positions[g];
      if (at == null) continue;
      yield (x: at.x, y: at.y);
    }
  }

  LRect _nodeRectAt(LPoint centre, LSize size) {
    final h = math.max(size.w, size.h) / 2;
    return (
      left: centre.x - h,
      top: centre.y - h,
      right: centre.x + h,
      bottom: centre.y + h,
    );
  }

  @override
  Stream<GraphLayoutFrame> layout(GraphLayoutRequest request) async* {
    final previous = request.previous;
    final clean = GraphLayoutRequest(
      ticket: request.ticket,
      canvasSize: request.canvasSize,
      nodesById: request.nodesById,
      edgesById: request.edgesById,
      previous: previous == null
          ? null
          : SceneLayout(
              ticket: previous.ticket,
              revision: previous.revision,
              positions: {...previous.positions, ...priors},
            ),
    );
    // Only a person new to an arrangement already on screen is a newcomer.
    // A cold layout (first load, account change) has no arrangement yet: the
    // base layout is the settled one, and seating everyone there would draw
    // every tag squeezed until the next relayout spreads it again.
    final seatNewcomers = previous != null && previous.positions.isNotEmpty;
    await for (final frame in base.layout(clean)) {
      final positions = Map.of(frame.positions);

      final fieldPersonIds = <String>{
        for (final gid in positions.keys)
          if (gid.startsWith('${TenturaGraphNodeKind.fieldPerson}:'))
            tenturaLayoutDomainId(gid),
      }..remove(viewerId);

      final personCentreById = <String, LPoint>{
        for (final id in fieldPersonIds)
          id: (
            x: positions[_personGid(id)]!.x,
            y: positions[_personGid(id)]!.y,
          ),
      };

      for (final personId in fieldPersonIds) {
        if (!seatNewcomers || personId == viewerId) {
          continue;
        }
        final graphId = _personGid(personId);
        if (_positionIsFixed(request, graphId)) {
          continue;
        }
        final at = positions[graphId];
        if (at == null) {
          continue;
        }
        final ownTags = {
          for (final t in tagsOfPerson(personId))
            if (peopleInTag(t).isNotEmpty) t,
        };
        if (ownTags.isEmpty) {
          continue;
        }
        final eligible = constellationTagIdsWithOtherMembersOnField(
          ownTagIds: ownTags,
          peopleOfTag: peopleInTag,
          fieldPersonIds: fieldPersonIds,
          egoId: viewerId,
        );
        if (eligible.isEmpty) {
          continue;
        }
        final movingSize = _sizeFor(clean, graphId);
        final tagCentroidForPerson = <String, LPoint?>{
          for (final tagId in eligible)
            tagId: constellationTagMemberCentroidScene(
              tagId: tagId,
              peopleOfTag: peopleInTag,
              personCentreById: personCentreById,
              egoId: viewerId,
              excludePersonIds: {personId},
            ),
        };
        final tagMagnetsScene = <String, LPoint>{
          for (final MapEntry(:key, :value) in tagMagnetOffsets.entries)
            key: (x: value.dx, y: value.dy),
        };

        double cellFor(String domainId) {
          final id = _personGid(domainId);
          final size = _sizeFor(clean, id);
          return math.max(size.w, size.h) + 16;
        }

        double tagDiskRadius(String tagId) {
          final members = peopleInTag(tagId)
              .where(fieldPersonIds.contains)
              .where((id) => id != personId)
              .toList();
          final n = math.max(1, members.length);
          var maxCell = 0.0;
          for (final id in members) {
            maxCell = math.max(maxCell, cellFor(id));
          }
          return constellationTagAreaRadiusForSeating(
            memberCount: n,
            maxCell: maxCell,
          );
        }

        final target = constellationTagAreaSeatingTargetScene(
          eligibleTagIds: eligible,
          tagCentroidScene: tagCentroidForPerson,
          tagMagnetsScene: tagMagnetsScene,
          movingSize: movingSize,
        );
        if (target == null) {
          continue;
        }

        final hullPoints = <LPoint>[];
        if (eligible.length == 1) {
          final tagId = eligible.single;
          hullPoints.addAll(
            _memberCentresExcluding(
              positions: positions,
              memberDomainIds: peopleInTag(tagId),
              excludeDomainId: personId,
            ),
          );
        } else {
          final seen = <String>{};
          for (final tagId in eligible) {
            for (final id in peopleInTag(tagId)) {
              if (!fieldPersonIds.contains(id) || id == personId) continue;
              if (seen.add(id)) {
                final g = _personGid(id);
                final p = positions[g];
                if (p != null) {
                  hullPoints.add((x: p.x, y: p.y));
                }
              }
            }
          }
        }
        final hull = constellationConvexHullMonotoneChain(hullPoints);

        var maxR = 0.0;
        for (final tagId in eligible) {
          maxR = math.max(maxR, tagDiskRadius(tagId));
        }
        if (eligible.length > 1) {
          final cs = <LPoint>[
            for (final t in eligible)
              if (tagMagnetsScene[t] != null)
                tagMagnetsScene[t]!
              else if (tagCentroidForPerson[t] != null)
                tagCentroidForPerson[t]!,
          ];
          if (cs.length >= 2) {
            for (var i = 0; i < cs.length; i++) {
              for (var j = i + 1; j < cs.length; j++) {
                final dx = cs[i].x - cs[j].x;
                final dy = cs[i].y - cs[j].y;
                maxR = math.max(maxR, math.sqrt(dx * dx + dy * dy));
              }
            }
          }
        }

        final obstacles = <LRect>[
          for (final MapEntry(:key, :value) in positions.entries)
            if (key != graphId)
              _nodeRectAt(
                (x: value.x, y: value.y),
                _sizeFor(clean, key),
              ),
        ];

        final resolved = constellationTagAreaSeatingResolvePositionScene(
          movingCentre: (x: at.x, y: at.y),
          target: target,
          movingSize: movingSize,
          obstacles: obstacles,
          insideHull: hull.isEmpty ? null : hull,
          maxRadius: maxR,
        );
        positions[graphId] = ScenePoint(x: resolved.x, y: resolved.y);
      }

      for (final entry in magnetsByPerson.entries) {
        final at = positions[entry.key];
        if (at == null) continue;
        final moved = attractToTagMagnets((x: at.x, y: at.y), entry.value);
        positions[entry.key] = ScenePoint(x: moved.x, y: moved.y);
      }
      for (final entry in followers.entries) {
        final at = frame.positions[entry.key];
        final was = frame.positions[entry.value];
        final now = positions[entry.value];
        if (at == null || was == null || now == null) continue;
        positions[entry.key] = ScenePoint(
          x: at.x + now.x - was.x,
          y: at.y + now.y - was.y,
        );
      }
      yield GraphLayoutFrame(
        ticket: frame.ticket,
        sequence: frame.sequence,
        isTerminal: frame.isTerminal,
        positions: positions,
      );
    }
  }
}
