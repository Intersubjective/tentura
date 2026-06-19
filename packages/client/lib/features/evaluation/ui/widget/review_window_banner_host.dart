import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';

import 'package:tentura/consts.dart';
import 'package:tentura/features/evaluation/data/repository/evaluation_repository.dart';
import 'package:tentura/features/evaluation/domain/entity/review_window_info.dart';

import 'review_banner.dart';

/// Fetches review-window status and shows [ReviewBanner] in the beacon header HUD.
class ReviewWindowBannerHost extends StatefulWidget {
  const ReviewWindowBannerHost({
    required this.beaconId,
    super.key,
  });

  final String beaconId;

  @override
  State<ReviewWindowBannerHost> createState() => _ReviewWindowBannerHostState();
}

class _ReviewWindowBannerHostState extends State<ReviewWindowBannerHost> {
  ReviewWindowInfo? _window;
  Object? _error;

  static const _slotPadding = EdgeInsets.only(top: 10, bottom: 10);

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void didUpdateWidget(covariant ReviewWindowBannerHost oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.beaconId != widget.beaconId) {
      unawaited(_load());
    }
  }

  Future<void> _load() async {
    setState(() {
      _error = null;
      _window = null;
    });
    try {
      final w = await GetIt.I<EvaluationRepository>().fetchReviewWindowStatus(
        widget.beaconId,
      );
      if (mounted) {
        setState(() => _window = w);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _error = e);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_window == null && _error == null) {
      return const Padding(
        padding: _slotPadding,
        child: LinearProgressIndicator(),
      );
    }
    final w = _window;
    if (w == null || !w.hasWindow || w.totalCount == 0) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: _slotPadding,
      child: ReviewBanner(
        isDraftPhase: false,
        margin: EdgeInsets.zero,
        onPrimary: () => context.router.pushPath(
          '$kPathReviewContributions/${widget.beaconId}',
        ),
      ),
    );
  }
}
