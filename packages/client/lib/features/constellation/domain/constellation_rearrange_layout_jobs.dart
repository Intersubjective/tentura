import 'package:tentura_root/domain/constellation/constellation_anchor.dart';

import 'constellation_drag_cluster.dart';
import 'constellation_layout.dart';
import 'constellation_rearrange_tag_areas.dart';
import 'constellation_rearrange_two_tag_refinement.dart';
import 'layout/constellation_layout_engine.dart';
import 'layout/spatial_index.dart';

/// Bounded job: own-tag area staging on top of [freeLayout] (checkpointed).
final class ConstellationTagStagingLayoutJob implements LayoutJob {
  factory ConstellationTagStagingLayoutJob({
    required ConstellationPlacedLayoutInput input,
    required ConstellationLayout freeLayout,
  }) {
    late ConstellationRearrangeTagStaging staging;
    final iterator = constellationRearrangeTagStagingSteps(
      input: input,
      freeLayout: freeLayout,
      onComplete: (r) => staging = r,
    ).iterator;
    return ConstellationTagStagingLayoutJob._(iterator, () => staging);
  }

  ConstellationTagStagingLayoutJob._(this._iterator, this._stagingOf);

  final Iterator<void> _iterator;
  final ConstellationRearrangeTagStaging Function() _stagingOf;

  static const int _unitWorkBound = 40;

  var _entered = false;
  var _done = false;
  int _lastStepWork = 0;
  ConstellationRearrangeTagStaging get staging {
    if (!_done) {
      throw StateError('Tag staging job has not finished');
    }
    return _stagingOf();
  }

  @override
  bool step(int units) {
    if (units <= 0) {
      _lastStepWork = 0;
      return _done;
    }
    if (_done) {
      _lastStepWork = 0;
      return true;
    }
    if (!_entered) {
      _entered = true;
      _iterator.moveNext();
    }
    var work = 0;
    for (var u = 0; u < units; u++) {
      for (var i = 0; i < constellationLayoutJobCheckpointsPerUnit; i++) {
        work++;
        if (!_iterator.moveNext()) {
          _done = true;
          _lastStepWork = work;
          return true;
        }
      }
    }
    _lastStepWork = work;
    return false;
  }

  @override
  LayoutResult get result =>
      throw UnsupportedError('Tag staging exposes staging, not LayoutResult');

  @override
  int get lastStepWork => _lastStepWork;

  @override
  int get unitWorkBound => _unitWorkBound;
}

/// Checkpoints per layout unit — must match [_ConstellationLayoutJob].
const int constellationLayoutJobCheckpointsPerUnit = 8;

/// Composite «Rearrange everyone»: loose layout → tag staging → settled layout
/// → optional two-tag refinement. Each [step] forwards to the active sub-job.
final class ConstellationRearrangeAllLayoutJob implements LayoutJob {
  ConstellationRearrangeAllLayoutJob(
    this._input, {
    SpatialIndex Function()? newIndex,
  }) : _engine = ConstellationLayoutEngine(
         newIndex: newIndex ?? BruteForceIndex.new,
       );

  final ConstellationPlacedLayoutInput _input;
  final ConstellationLayoutEngine _engine;

  static const int _unitWorkBound = 64;

  _RearrangeStage _stage = _RearrangeStage.loose;
  LayoutJob? _activeJob;
  ConstellationTagStagingLayoutJob? _tagStagingJob;
  Iterator<void>? _refinementIterator;
  ConstellationLayout? _refinedLayout;

  LayoutResult? _looseResult;
  ConstellationRearrangeTagStaging? _staging;
  Map<String, ConstellationPoint>? _pinned;
  ConstellationLayout? _settledLayout;

  late final LayoutResult _finalResult;

  var _done = false;
  int _lastStepWork = 0;

  ConstellationPlacedLayoutInput get _looseInput {
    final seatedOffPath = {
      for (final id in _input.pinnedPersonIds)
        if (id != _input.egoId &&
            !_input.paths.keep.contains(id) &&
            !_input.paths.ring.contains(id))
          id,
    };
    return (
      egoId: _input.egoId,
      paths: seatedOffPath.isEmpty
          ? _input.paths
          : (
              depth: _input.paths.depth,
              derived: _input.paths.derived,
              parent: _input.paths.parent,
              parentTier: _input.paths.parentTier,
              attributed: _input.paths.attributed,
              keep: _input.paths.keep,
              ring: {..._input.paths.ring, ...seatedOffPath},
            ),
      automaticKeptPeerIds: {
        ..._input.automaticKeptPeerIds,
        ..._input.pinnedPersonIds,
      },
      pinnedPersonIds: const <String>{},
      pinnedRequestIds: const <String>{},
      supportPersonIds: _input.supportPersonIds,
      anchorByNodeId: const <String, ConstellationAnchorPosition>{},
      priorHints: null,
      nodeSizes: _input.nodeSizes,
      satelliteRequestIdsByAuthor: _input.satelliteRequestIdsByAuthor,
      requestAuthorById: _input.requestAuthorById,
      egoOwnRequestIds: _input.egoOwnRequestIds,
      spacing: _input.spacing,
      maxHops: _input.maxHops,
      viewportClass: _input.viewportClass,
      footprints: _input.footprints,
      rearrangeOwnTagPeopleByTagId: _input.rearrangeOwnTagPeopleByTagId,
      rearrangeTagMagnetsByTagId: _input.rearrangeTagMagnetsByTagId,
    );
  }

  @override
  bool step(int units) {
    if (units <= 0) {
      _lastStepWork = 0;
      return _done;
    }
    start();
    if (_done) {
      _lastStepWork = 0;
      return true;
    }
    switch (_stage) {
      case _RearrangeStage.loose:
      case _RearrangeStage.tagStaging:
      case _RearrangeStage.settled:
        final job = _activeJob;
        if (job == null) {
          return false;
        }
        final subDone = job.step(units);
        _lastStepWork = job.lastStepWork;
        if (!subDone) {
          return false;
        }
        return _afterSubJobComplete();

      case _RearrangeStage.refinement:
        var work = 0;
        final maxCheckpoints = units * constellationLayoutJobCheckpointsPerUnit;
        for (var c = 0; c < maxCheckpoints; c++) {
          work++;
          if (_refinementIterator!.moveNext()) {
            _lastStepWork = work;
            return false;
          }
          _finalize(_refinedLayout!);
          _lastStepWork = work;
          return true;
        }
        _lastStepWork = work;
        return false;

      case _RearrangeStage.done:
        _lastStepWork = 0;
        return true;
    }
  }

  bool _afterSubJobComplete() {
    switch (_stage) {
      case _RearrangeStage.loose:
        _looseResult = _activeJob!.result;
        final hasOwnTagIds = _input.rearrangeOwnTagPeopleByTagId.keys.any(
          (k) => !k.startsWith('auto:'),
        );
        if (hasOwnTagIds) {
          _tagStagingJob = ConstellationTagStagingLayoutJob(
            input: _input,
            freeLayout: (
              positions: _looseResult!.positions,
              ring: _looseResult!.ring,
            ),
          );
          _activeJob = _tagStagingJob;
          _stage = _RearrangeStage.tagStaging;
        } else {
          _staging = (areaPositions: const {}, tagCentres: const {});
          _startSettledJob();
        }
        return false;

      case _RearrangeStage.tagStaging:
        _staging = _tagStagingJob!.staging;
        _startSettledJob();
        return false;

      case _RearrangeStage.settled:
        _settledLayout = (
          positions: _activeJob!.result.positions,
          ring: _activeJob!.result.ring,
        );
        _activeJob = null;
        _maybeStartRefinement();
        return _done;

      case _RearrangeStage.refinement:
      case _RearrangeStage.done:
        return false;
    }
  }

  ConstellationPlacedLayoutInput? _settledInput;

  void _startSettledJob() {
    final free = (
      positions: _looseResult!.positions,
      ring: _looseResult!.ring,
    );
    final staging = _staging!;
    final tagArea = staging.areaPositions;
    final pinned = <String, ConstellationPoint>{
      for (final id in _input.anchorByNodeId.keys)
        if (free.positions[id] case final point?)
          id: constellationClampToDragBounds(point),
    };
    for (final entry in tagArea.entries) {
      pinned[entry.key] = constellationClampToDragBounds(entry.value);
    }
    _pinned = pinned;

    final priorHints = tagArea.isEmpty
        ? null
        : (
            positions: <String, ConstellationPoint>{
              ...free.positions,
              ...tagArea,
            },
            ring: Map<String, int>.from(free.ring),
            viewportClass: _input.viewportClass,
          );

    _settledInput = (
      egoId: _input.egoId,
      paths: _input.paths,
      automaticKeptPeerIds: _input.automaticKeptPeerIds,
      pinnedPersonIds: _input.pinnedPersonIds,
      pinnedRequestIds: _input.pinnedRequestIds,
      supportPersonIds: _input.supportPersonIds,
      anchorByNodeId: {
        ..._input.anchorByNodeId,
        for (final entry in pinned.entries)
          entry.key: constellationPointToV1Anchor(entry.value),
      },
      priorHints: priorHints,
      nodeSizes: _input.nodeSizes,
      satelliteRequestIdsByAuthor: _input.satelliteRequestIdsByAuthor,
      requestAuthorById: _input.requestAuthorById,
      egoOwnRequestIds: _input.egoOwnRequestIds,
      spacing: _input.spacing,
      maxHops: _input.maxHops,
      viewportClass: _input.viewportClass,
      footprints: _input.footprints,
      rearrangeOwnTagPeopleByTagId: _input.rearrangeOwnTagPeopleByTagId,
      rearrangeTagMagnetsByTagId: _input.rearrangeTagMagnetsByTagId,
    );
    // Full placed layout from [settled] inputs (merged priorHints + anchors);
    // do not pass [loose] as `previous` — the engine would replace priorHints
    // with the loose positions only and drop tag-area merged hints (#1020).
    _activeJob = _engine.start(null, _settledInput!);
    _stage = _RearrangeStage.settled;
  }

  void _maybeStartRefinement() {
    final tagArea = _staging!.areaPositions;
    final tagCentres = _staging!.tagCentres;
    final ownTagIds =
        _input.rearrangeOwnTagPeopleByTagId.keys
            .where((k) => !k.startsWith('auto:'))
            .toList()
          ..sort();
    if (ownTagIds.length == 2 && tagCentres.length == 2 && tagArea.isNotEmpty) {
      _refinedLayout = null;
      _refinementIterator = constellationRearrangeTwoTagRefinementSteps(
        input: _input,
        tagCentres: tagCentres,
        staging: _staging!,
        pinned: _pinned!,
        layout: _settledLayout!,
        onComplete: (l) => _refinedLayout = l,
      ).iterator;
      _activeJob = null;
      _stage = _RearrangeStage.refinement;
    } else {
      _finalize(_settledLayout!);
    }
  }

  void _finalize(ConstellationLayout layout) {
    _finalResult = LayoutResult.fromCompleteLayout(layout, _input);
    _done = true;
    _stage = _RearrangeStage.done;
    _activeJob = null;
  }

  @override
  LayoutResult get result {
    if (!_done) {
      throw StateError('Rearrange-all job has not finished');
    }
    return _finalResult;
  }

  /// Same payload as [computeConstellationRearrangeAll] after the job completes.
  ConstellationRearrangeAllJobOutcome completeOutcome() {
    if (!_done) {
      throw StateError('Rearrange-all job has not finished');
    }
    final loose = (
      positions: _looseResult!.positions,
      ring: _looseResult!.ring,
    );
    final staging = _staging!;
    return (
      pinned: Map<String, ConstellationPoint>.from(_pinned!),
      layout: (positions: result.positions, ring: result.ring),
      tagCentres: staging.tagCentres,
      looseLayout: loose,
    );
  }

  @override
  int get lastStepWork => _lastStepWork;

  @override
  int get unitWorkBound => _unitWorkBound;

  /// Idempotent: starts the first (loose) [LayoutJob].
  void start() {
    if (_activeJob != null || _done || _stage == _RearrangeStage.refinement) {
      return;
    }
    if (_stage != _RearrangeStage.loose) {
      return;
    }
    _activeJob = _engine.start(null, _looseInput);
  }
}

typedef ConstellationRearrangeAllJobOutcome = ({
  Map<String, ConstellationPoint> pinned,
  ConstellationLayout layout,
  Map<String, ConstellationPoint> tagCentres,
  ConstellationLayout looseLayout,
});

enum _RearrangeStage { loose, tagStaging, settled, refinement, done }
