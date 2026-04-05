import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';

import 'package:tentura/consts.dart';
import 'package:tentura/domain/entity/beacon_lifecycle.dart';
import 'package:tentura/features/evaluation/data/repository/evaluation_repository.dart';
import 'package:tentura/features/evaluation/domain/entity/evaluation_participant.dart';
import 'package:tentura/features/evaluation/domain/entity/evaluation_summary.dart';
import 'package:tentura/features/evaluation/domain/entity/review_window_info.dart';

import 'evaluation_summary_card.dart';
import 'review_banner.dart';

/// Loads review window / draft targets / summary for beacon detail (no global BLoC).
class BeaconEvaluationHooks extends StatefulWidget {
  const BeaconEvaluationHooks({
    required this.beaconId,
    required this.lifecycle,
    super.key,
  });

  final String beaconId;
  final BeaconLifecycle lifecycle;

  @override
  State<BeaconEvaluationHooks> createState() => _BeaconEvaluationHooksState();
}

class _BeaconEvaluationHooksState extends State<BeaconEvaluationHooks> {
  ReviewWindowInfo? _window;
  EvaluationSummary? _summary;
  Object? _error;

  /// Non-null after load attempt while beacon is open: list may be empty.
  List<EvaluationParticipant>? _draftTargetsLoaded;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void didUpdateWidget(covariant BeaconEvaluationHooks oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.beaconId != widget.beaconId ||
        oldWidget.lifecycle != widget.lifecycle) {
      unawaited(_load());
    }
  }

  Future<void> _load() async {
    if (widget.lifecycle != BeaconLifecycle.open &&
        widget.lifecycle != BeaconLifecycle.closedReviewOpen &&
        widget.lifecycle != BeaconLifecycle.closedReviewComplete) {
      return;
    }
    setState(() {
      _error = null;
      if (widget.lifecycle == BeaconLifecycle.open) {
        _draftTargetsLoaded = null;
      }
    });
    try {
      final repo = GetIt.I<EvaluationRepository>();
      if (widget.lifecycle == BeaconLifecycle.open) {
        final list = await repo.fetchDraftParticipants(widget.beaconId);
        if (mounted) {
          setState(() => _draftTargetsLoaded = list);
        }
        return;
      }
      if (widget.lifecycle == BeaconLifecycle.closedReviewOpen ||
          widget.lifecycle == BeaconLifecycle.closedReviewComplete) {
        final w = await repo.fetchReviewWindowStatus(widget.beaconId);
        EvaluationSummary? s;
        if (widget.lifecycle == BeaconLifecycle.closedReviewComplete) {
          s = await repo.fetchSummary(widget.beaconId);
        }
        if (mounted) {
          setState(() {
            _window = w;
            _summary = s;
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _error = e);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.lifecycle == BeaconLifecycle.open) {
      if (_draftTargetsLoaded == null && _error == null) {
        return const Padding(
          padding: EdgeInsets.symmetric(vertical: 8),
          child: LinearProgressIndicator(),
        );
      }
      final list = _draftTargetsLoaded;
      if (list == null || list.isEmpty) {
        return const SizedBox.shrink();
      }
      return ReviewBanner(
        isDraftPhase: true,
        onPrimary: () => context.router.pushPath(
          '$kPathReviewContributions/${widget.beaconId}?draft=true',
        ),
      );
    }

    if (widget.lifecycle == BeaconLifecycle.closedReviewOpen) {
      if (_window == null && _error == null) {
        return const Padding(
          padding: EdgeInsets.symmetric(vertical: 8),
          child: LinearProgressIndicator(),
        );
      }
      final w = _window;
      if (w == null || !w.hasWindow || w.totalCount == 0) {
        return const SizedBox.shrink();
      }
      return ReviewBanner(
        isDraftPhase: false,
        onPrimary: () => context.router.pushPath(
          '$kPathReviewContributions/${widget.beaconId}',
        ),
      );
    }
    if (widget.lifecycle == BeaconLifecycle.closedReviewComplete &&
        _summary != null) {
      return EvaluationSummaryCard(summary: _summary!);
    }
    if (widget.lifecycle == BeaconLifecycle.closedReviewComplete &&
        _error != null) {
      return const SizedBox.shrink();
    }
    if (widget.lifecycle == BeaconLifecycle.closedReviewComplete) {
      if (_summary == null && _error == null) {
        return const Padding(
          padding: EdgeInsets.symmetric(vertical: 8),
          child: LinearProgressIndicator(),
        );
      }
    }
    return const SizedBox.shrink();
  }
}
