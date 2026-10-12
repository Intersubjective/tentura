import 'package:flutter/material.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/ui/l10n/l10n.dart';

import '../../domain/entity/beacon_plan.dart';
import '../../domain/entity/plan_fork_copy.dart';
import '../util/plan_presenter.dart';
import 'plan_datetime_field.dart';

/// What the person chose on [PlanCopySheet]. [stepTimes] is null when the
/// copy goes without the plan.
@immutable
final class PlanCopyChoice {
  const PlanCopyChoice({this.stepTimes});

  final List<PlanStepTime>? stepTimes;

  bool get copyPlan => stepTimes != null;
}

/// «Скопировать план» before a Request is copied (plan §5.11). Null when the
/// sheet was dismissed: the copy is then not made at all.
Future<PlanCopyChoice?> showPlanCopySheet(
  BuildContext context, {
  required BeaconPlan plan,
  DateTime Function()? clock,
}) => showTenturaAdaptiveSheet<PlanCopyChoice>(
  context: context,
  useRootNavigator: true,
  builder: (_) => PlanCopySheet(steps: plan.steps, clock: clock),
);

/// The sheet body: a «copy the plan» toggle, the new start of the first
/// timed step, the shift every timed step gets, and a preview of the new
/// times. Assignees are never copied.
class PlanCopySheet extends StatefulWidget {
  const PlanCopySheet({required this.steps, this.clock, super.key});

  final List<PlanStep> steps;

  /// Test seam for «now».
  final DateTime Function()? clock;

  static const toggleKey = Key('plan-copy-toggle');
  static const confirmKey = Key('plan-copy-confirm');
  static const shiftKey = Key('plan-copy-shift');

  /// Steps listed before «ещё N».
  static const previewLimit = 5;

  @override
  State<PlanCopySheet> createState() => _PlanCopySheetState();
}

class _PlanCopySheetState extends State<PlanCopySheet> {
  late final DateTime? _sourceAnchor = planCopySourceAnchor(widget.steps);
  late DateTime? _anchor = _sourceAnchor == null
      ? null
      : defaultPlanCopyAnchor(
          sourceAnchor: _sourceAnchor,
          now: (widget.clock ?? DateTime.now)(),
        );
  bool _copy = true;

  PlanCopyShift get _shift {
    final source = _sourceAnchor;
    final anchor = _anchor;
    if (source == null || anchor == null) return (days: 0, minutes: 0);
    return planCopyShift(sourceAnchor: source, newAnchor: anchor);
  }

  void _confirm() => Navigator.of(context).pop(
    PlanCopyChoice(
      stepTimes: _copy ? planCopyStepTimes(widget.steps, _shift) : null,
    ),
  );

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final tt = context.tt;
    final shift = _shift;
    final times = planCopyStepTimes(widget.steps, shift);
    final shown = widget.steps.length > PlanCopySheet.previewLimit
        ? PlanCopySheet.previewLimit
        : widget.steps.length;
    return SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.symmetric(
          horizontal: tt.screenHPadding,
          vertical: tt.rowGap,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(l10n.planCopyTitle, style: TenturaText.titleSmall(tt.text)),
            SwitchListTile.adaptive(
              key: PlanCopySheet.toggleKey,
              contentPadding: EdgeInsets.zero,
              title: Text(l10n.planCopyHeader(widget.steps.length)),
              value: _copy,
              onChanged: (v) => setState(() => _copy = v),
            ),
            if (_copy) ...[
              if (_anchor == null)
                Text(
                  l10n.planCopyNoTimes,
                  style: TenturaText.bodySmall(tt.textMuted),
                )
              else ...[
                PlanDateTimeField(
                  label: l10n.planCopyStartLabel,
                  value: _anchor,
                  clearable: false,
                  onChanged: (v) {
                    if (v != null) setState(() => _anchor = v);
                  },
                ),
                SizedBox(height: tt.tightGap),
                Text(
                  planCopyShiftLabel(shift, l10n),
                  key: PlanCopySheet.shiftKey,
                  style: TenturaText.bodySmall(tt.textMuted),
                ),
              ],
              SizedBox(height: tt.rowGap),
              for (var i = 0; i < shown; i++)
                _PreviewRow(step: widget.steps[i], time: times[i]),
              if (widget.steps.length > shown)
                Text(
                  l10n.planLineMore(widget.steps.length - shown),
                  style: TenturaText.bodySmall(tt.textMuted),
                ),
              SizedBox(height: tt.tightGap),
              Text(
                l10n.planCopyNoAssignees,
                style: TenturaText.bodySmall(tt.textMuted),
              ),
            ],
            SizedBox(height: tt.rowGap),
            FilledButton(
              key: PlanCopySheet.confirmKey,
              onPressed: _confirm,
              child: Text(l10n.planCopyConfirm),
            ),
          ],
        ),
      ),
    );
  }
}

class _PreviewRow extends StatelessWidget {
  const _PreviewRow({required this.step, required this.time});

  final PlanStep step;
  final PlanStepTime time;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final tt = context.tt;
    return Padding(
      padding: EdgeInsets.only(bottom: tt.tightGap),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            planStepWhenLabel(
              startAt: time.startAt,
              endAt: time.endAt,
              l10n: l10n,
            ),
            style: TenturaText.bodySmall(tt.textMuted),
          ),
          Text(step.title, style: TenturaText.body(tt.text)),
        ],
      ),
    );
  }
}

/// «все шаги сдвинутся на +7 дней −30 мин» / «время не изменится».
String planCopyShiftLabel(PlanCopyShift shift, L10n l10n) {
  if (shift.days == 0 && shift.minutes == 0) return l10n.planCopyNoShift;
  String sign(int v) => v < 0 ? '−' : '+';
  final parts = [
    if (shift.days != 0)
      '${sign(shift.days)}${l10n.planCopyShiftDays(shift.days.abs())}',
    if (shift.minutes != 0)
      sign(shift.minutes) +
          planDuration(Duration(minutes: shift.minutes.abs()), l10n),
  ];
  return l10n.planCopyShift(parts.join(' '));
}
