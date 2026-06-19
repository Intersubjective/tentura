import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';

import 'package:tentura/domain/entity/beacon_lifecycle.dart';
import 'package:tentura/features/evaluation/data/repository/evaluation_repository.dart';
import 'package:tentura/features/evaluation/domain/entity/evaluation_summary.dart';

import 'evaluation_summary_card.dart';

/// Loads post-review summary for beacon People tab.
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
  EvaluationSummary? _summary;
  Object? _error;

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
    if (widget.lifecycle != BeaconLifecycle.closedReviewComplete) {
      return;
    }
    setState(() {
      _error = null;
    });
    try {
      final s = await GetIt.I<EvaluationRepository>().fetchSummary(
        widget.beaconId,
      );
      if (mounted) {
        setState(() => _summary = s);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _error = e);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.lifecycle != BeaconLifecycle.closedReviewComplete) {
      return const SizedBox.shrink();
    }
    if (_summary != null) {
      return EvaluationSummaryCard(summary: _summary!);
    }
    if (_error != null) {
      return const SizedBox.shrink();
    }
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 8),
      child: LinearProgressIndicator(),
    );
  }
}
