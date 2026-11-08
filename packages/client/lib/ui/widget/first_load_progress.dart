import 'package:flutter/material.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/widget/linear_pi_active.dart';

/// Optional stage metadata for the shared first-load gate widget.
///
/// When [step] and [totalSteps] are set, the gate shows a determinate bar at
/// [step]/[totalSteps]. Otherwise the bar stays indeterminate while [stageLabel]
/// still renders (when non-empty).
class FirstLoadProgress {
  const FirstLoadProgress({
    required this.stageLabel,
    this.step,
    this.totalSteps,
  });

  final String stageLabel;
  final int? step;
  final int? totalSteps;

  bool get hasStepCount =>
      step != null && totalSteps != null && totalSteps! > 0 && step! > 0;

  double? get determinateValue {
    if (!hasStepCount) return null;
    return step! / totalSteps!;
  }

  String statusLine(L10n l10n) {
    if (!hasStepCount) return stageLabel;
    return l10n.firstLoadStepProgress(step!, totalSteps!, stageLabel);
  }
}

/// Centre loading chrome: step line plus an honest progress bar.
class FirstLoadStatusPanel extends StatelessWidget {
  const FirstLoadStatusPanel({
    required this.progress,
    super.key,
  });

  final FirstLoadProgress? progress;

  @override
  Widget build(BuildContext context) {
    final tt = context.tt;
    final stage = progress?.stageLabel ?? '';
    final showLabel = stage.isNotEmpty;
    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: tt.contentMaxWidth ?? double.infinity,
        ),
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: tt.screenHPadding),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (showLabel)
                TenturaMetaText(
                  progress!.statusLine(L10n.of(context)!),
                  maxLines: 4,
                  overflow: TextOverflow.visible,
                ),
              if (showLabel) SizedBox(height: tt.sectionGap),
              _FirstLoadBar(progress: progress),
            ],
          ),
        ),
      ),
    );
  }
}

class _FirstLoadBar extends StatelessWidget {
  const _FirstLoadBar({required this.progress});

  final FirstLoadProgress? progress;

  @override
  Widget build(BuildContext context) {
    final tt = context.tt;
    final theme = Theme.of(context);
    final value = progress?.determinateValue;
    final color = theme.colorScheme.primary;
    final track = tt.borderSubtle;
    if (value != null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(tt.buttonRadius),
        child: LinearProgressIndicator(
          value: value,
          minHeight: LinearPiActive.height,
          color: color,
          backgroundColor: track,
        ),
      );
    }
    if (MediaQuery.disableAnimationsOf(context)) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(tt.buttonRadius),
        child: LinearProgressIndicator(
          value: 0.35,
          minHeight: LinearPiActive.height,
          color: color,
          backgroundColor: track,
        ),
      );
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(tt.buttonRadius),
      child: LinearPiActive(color: color, backgroundColor: track),
    );
  }
}
