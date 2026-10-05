import 'package:flutter/material.dart';
import 'package:tentura_root/domain/plan/plan.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/ui/l10n/l10n.dart';

import '../bloc/plan_edit_state.dart';
import 'plan_datetime_field.dart';
import 'plan_person_picker.dart';

/// Edits one draft step: title, details, assignee (admitted people only),
/// optional start / end. Resolves to the edited step, or null on dismiss.
Future<PlanStepSnapshot?> showPlanStepEditSheet(
  BuildContext context, {
  required PlanStepSnapshot step,
  required List<Profile> people,
  bool isNew = false,
}) => showTenturaAdaptiveSheet<PlanStepSnapshot>(
  context: context,
  useRootNavigator: true,
  builder: (_) => PlanStepEditSheet(step: step, people: people, isNew: isNew),
);

class PlanStepEditSheet extends StatefulWidget {
  const PlanStepEditSheet({
    required this.step,
    required this.people,
    this.isNew = false,
    super.key,
  });

  final PlanStepSnapshot step;
  final List<Profile> people;
  final bool isNew;

  static const titleFieldKey = Key('plan-step-title');
  static const applyKey = Key('plan-step-apply');

  @override
  State<PlanStepEditSheet> createState() => _PlanStepEditSheetState();
}

class _PlanStepEditSheetState extends State<PlanStepEditSheet> {
  late final _title = TextEditingController(text: widget.step.title);
  late final _description = TextEditingController(
    text: widget.step.description,
  );
  late String? _assigneeId = widget.step.assigneeId;
  late DateTime? _start = widget.step.startAt;
  late DateTime? _end = widget.step.endAt;

  PlanStepSnapshot get _edited => PlanStepSnapshot(
    id: widget.step.id,
    title: _title.text.trim(),
    description: _description.text.trim(),
    assigneeId: _assigneeId,
    startAt: _start,
    endAt: _end,
  );

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _pickAssignee() async {
    final l10n = L10n.of(context)!;
    final pick = await showPlanPersonPicker(
      context,
      title: l10n.planAssigneePickerTitle,
      people: widget.people,
      selectedId: _assigneeId,
      allowNone: true,
    );
    if (pick == null || !mounted) return;
    setState(() => _assigneeId = pick.userId);
  }

  String _assigneeLabel(L10n l10n) {
    final id = _assigneeId;
    if (id == null) return l10n.planFieldNoAssignee;
    for (final p in widget.people) {
      if (p.id == id)
        return p.shownName.isEmpty ? l10n.unknownPerson : p.shownName;
    }
    return l10n.planDeletedUser;
  }

  String? _errorText(L10n l10n) => switch (validatePlanStep(_edited)) {
    PlanDraftError.titleRequired => l10n.planValidationTitleRequired,
    PlanDraftError.titleTooLong => l10n.planValidationTooLong(
      PlanLimits.maxTitleLength,
    ),
    PlanDraftError.descriptionTooLong => l10n.planValidationTooLong(
      PlanLimits.maxDescriptionLength,
    ),
    PlanDraftError.endBeforeStart => l10n.planValidationEndBeforeStart,
    _ => null,
  };

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final tt = context.tt;
    final error = _errorText(l10n);
    return SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.only(
          left: tt.screenHPadding,
          right: tt.screenHPadding,
          top: tt.rowGap,
          bottom: MediaQuery.viewInsetsOf(context).bottom + tt.rowGap,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              widget.isNew ? l10n.planEditNewStep : l10n.planEditTitle,
              style: TenturaText.titleSmall(tt.text),
            ),
            SizedBox(height: tt.rowGap),
            TextField(
              key: PlanStepEditSheet.titleFieldKey,
              controller: _title,
              autofocus: widget.isNew,
              maxLength: PlanLimits.maxTitleLength,
              decoration: InputDecoration(labelText: l10n.planFieldTitle),
              onChanged: (_) => setState(() {}),
            ),
            TextField(
              controller: _description,
              minLines: 1,
              maxLines: 5,
              maxLength: PlanLimits.maxDescriptionLength,
              decoration: InputDecoration(labelText: l10n.planFieldDescription),
            ),
            SizedBox(height: tt.rowGap),
            Text(
              l10n.planFieldAssignee,
              style: TenturaText.bodySmall(tt.textMuted),
            ),
            SizedBox(height: tt.tightGap),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: TenturaCommandButton(
                label: _assigneeLabel(l10n),
                icon: const Icon(Icons.person_outline),
                minInteractive: true,
                onPressed: _pickAssignee,
              ),
            ),
            SizedBox(height: tt.rowGap),
            PlanDateTimeField(
              label: l10n.planFieldStart,
              value: _start,
              onChanged: (v) => setState(() => _start = v),
            ),
            SizedBox(height: tt.rowGap),
            PlanDateTimeField(
              label: l10n.planFieldEnd,
              value: _end,
              fallbackDay: _start,
              onChanged: (v) => setState(() => _end = v),
            ),
            if (error != null) ...[
              SizedBox(height: tt.rowGap),
              TenturaStatusText(error, tone: TenturaTone.danger),
            ],
            SizedBox(height: tt.sectionGap),
            FilledButton(
              key: PlanStepEditSheet.applyKey,
              onPressed: error == null
                  ? () => Navigator.of(context).pop(_edited)
                  : null,
              child: Text(l10n.planEditApply),
            ),
          ],
        ),
      ),
    );
  }
}
