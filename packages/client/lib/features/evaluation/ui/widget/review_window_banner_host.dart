import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';

import 'package:tentura/consts.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/features/beacon_view/domain/use_case/beacon_view_case.dart';
import 'package:tentura/features/evaluation/data/repository/evaluation_repository.dart';
import 'package:tentura/features/evaluation/domain/entity/review_window_info.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/utils/ui_utils.dart';

import 'review_banner.dart';

/// Fetches review-window status and shows [ReviewBanner] in the beacon header HUD.
class ReviewWindowBannerHost extends StatefulWidget {
  const ReviewWindowBannerHost({
    required this.beaconId,
    this.isAuthor = false,
    super.key,
  });

  final String beaconId;
  final bool isAuthor;

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
    if (oldWidget.beaconId != widget.beaconId ||
        oldWidget.isAuthor != widget.isAuthor) {
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

  Future<void> _extendReview() async {
    final l10n = L10n.of(context)!;
    try {
      await GetIt.I<BeaconViewCase>().beaconExtendReview(widget.beaconId);
      await _load();
      if (mounted) {
        showSnackBar(context, text: l10n.beaconReviewExtendSuccess);
      }
    } catch (e) {
      if (mounted) {
        showSnackBar(context, isError: true, text: e.toString());
      }
    }
  }

  Future<void> _reopen() async {
    final l10n = L10n.of(context)!;
    final ok = await showAdaptiveDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog.adaptive(
        title: Text(l10n.beaconReviewReopenTitle),
        content: Text(l10n.beaconReviewReopenBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(l10n.beaconReviewReopenConfirm),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(l10n.buttonCancel),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await GetIt.I<BeaconViewCase>().beaconReopen(widget.beaconId);
      if (mounted) {
        showSnackBar(context, text: l10n.beaconReviewReopenSuccess);
      }
    } catch (e) {
      if (mounted) {
        showSnackBar(context, isError: true, text: e.toString());
      }
    }
  }

  Future<void> _closeNow() async {
    final l10n = L10n.of(context)!;
    try {
      await GetIt.I<BeaconViewCase>().beaconCloseNow(widget.beaconId);
      if (mounted) {
        showSnackBar(context, text: l10n.beaconReviewCloseNowSuccess);
      }
    } catch (e) {
      if (mounted) {
        showSnackBar(context, isError: true, text: e.toString());
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
    final l10n = L10n.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    final canCloseNow = widget.isAuthor &&
        !w.windowComplete &&
        w.reviewedCount >= w.totalCount;
    return Padding(
      padding: _slotPadding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ReviewBanner(
            isDraftPhase: false,
            margin: EdgeInsets.zero,
            onPrimary: () => context.router.pushPath(
              '$kPathReviewContributions/${widget.beaconId}',
            ),
          ),
          if (w.closesAt != null && w.closesAt!.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              l10n.beaconReviewWindowClosesAt(w.closesAt!),
              style: TenturaText.status(scheme.onSurfaceVariant),
            ),
          ],
          if (widget.isAuthor) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                TextButton(
                  onPressed: _extendReview,
                  child: Text(l10n.beaconReviewExtendAction),
                ),
                TextButton(
                  onPressed: _reopen,
                  child: Text(l10n.beaconReviewReopenAction),
                ),
                TextButton(
                  onPressed: canCloseNow ? _closeNow : null,
                  child: Text(l10n.beaconReviewCloseNowAction),
                ),
              ],
            ),
            if (!canCloseNow && !w.windowComplete)
              Text(
                l10n.beaconReviewCloseNowBlocked,
                style: TenturaText.status(scheme.onSurfaceVariant),
              ),
          ],
        ],
      ),
    );
  }
}
