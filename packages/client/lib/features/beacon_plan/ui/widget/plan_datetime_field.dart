import 'package:flutter/material.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/ui/l10n/l10n.dart';

import '../util/plan_presenter.dart';

/// Optional date + time of a plan step, picked in the viewer's zone and
/// reported as a UTC instant. «Без времени» clears it.
class PlanDateTimeField extends StatelessWidget {
  const PlanDateTimeField({
    required this.label,
    required this.value,
    required this.onChanged,
    this.fallbackDay,
    super.key,
  });

  final String label;
  final DateTime? value;
  final ValueChanged<DateTime?> onChanged;

  /// Day the picker opens on when [value] is empty.
  final DateTime? fallbackDay;

  Future<void> _pick(BuildContext context) async {
    final now = DateTime.now();
    final initial = (value ?? fallbackDay ?? now).toLocal();
    final date = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 5),
    );
    if (date == null || !context.mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: value == null
          ? const TimeOfDay(hour: 10, minute: 0)
          : TimeOfDay.fromDateTime(initial),
    );
    if (time == null) return;
    onChanged(
      DateTime(date.year, date.month, date.day, time.hour, time.minute).toUtc(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final tt = context.tt;
    final v = value;
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: TenturaText.bodySmall(tt.textMuted)),
              SizedBox(height: tt.tightGap),
              TenturaCommandButton(
                label: v == null
                    ? l10n.planFieldClearTime
                    : planDayTime(v, l10n.localeName),
                icon: const Icon(Icons.event_outlined),
                minInteractive: true,
                onPressed: () => _pick(context),
              ),
            ],
          ),
        ),
        if (v != null)
          IconButton(
            tooltip: l10n.planFieldClearTime,
            icon: const Icon(Icons.close),
            onPressed: () => onChanged(null),
          ),
      ],
    );
  }
}
