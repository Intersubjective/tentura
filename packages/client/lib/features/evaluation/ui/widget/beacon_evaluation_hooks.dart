import 'dart:async';
import 'package:tentura_root/domain/entity/beacon_status.dart';

import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';

import 'package:tentura/features/evaluation/data/repository/evaluation_repository.dart';
import 'package:tentura/features/evaluation/domain/entity/evaluation_summary.dart';

import 'evaluation_summary_card.dart';

/// Loads post-review summary for beacon People tab.
class BeaconEvaluationHooks extends StatefulWidget {
  const BeaconEvaluationHooks({
    required this.beaconId,
    required this.status,
    super.key,
  });

  final String beaconId;
  final BeaconStatus status;

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
        oldWidget.status != widget.status) {
      unawaited(_load());
    }
  }

  Future<void> _load() async {
    if (widget.status != BeaconStatus.closed) {
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
    if (widget.status != BeaconStatus.closed) {
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
