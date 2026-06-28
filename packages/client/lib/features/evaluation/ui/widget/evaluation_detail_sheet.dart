import 'package:flutter/material.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/contacts/contact_name_overlay.dart';
import 'package:tentura/features/capability/ui/widget/capability_chip_set.dart';
import 'package:tentura/features/evaluation/domain/entity/evaluation_participant.dart';
import 'package:tentura/features/evaluation/domain/entity/evaluation_value.dart';
import 'package:tentura/features/evaluation/ui/widget/evaluation_privacy_info_row.dart';
import 'package:tentura/ui/l10n/l10n.dart';

/// Modal sheet to set one participant evaluation.
Future<void> showEvaluationDetailSheet({
  required BuildContext context,
  required EvaluationParticipant participant,
  required Future<void> Function(
    EvaluationValue value,
    List<String> tags,
    String note,
    List<String> acknowledgedHelpTags,
  )
  onSave,
}) async {
  final l10n = L10n.of(context)!;
  await showTenturaAdaptiveSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    enableDrag: false,
    isDismissible: false,
    builder: (ctx) => _EvaluationDetailSheetBody(
      l10n: l10n,
      participant: participant,
      onSave: onSave,
    ),
  );
}

class _EvaluationDetailSheetBody extends StatefulWidget {
  const _EvaluationDetailSheetBody({
    required this.l10n,
    required this.participant,
    required this.onSave,
  });

  final L10n l10n;
  final EvaluationParticipant participant;
  final Future<void> Function(
    EvaluationValue value,
    List<String> tags,
    String note,
    List<String> acknowledgedHelpTags,
  )
  onSave;

  @override
  State<_EvaluationDetailSheetBody> createState() =>
      _EvaluationDetailSheetBodyState();
}

class _EvaluationDetailSheetBodyState extends State<_EvaluationDetailSheetBody> {
  late EvaluationValue _value;
  late final List<String> _tags;
  final _ackTags = <String>{};
  late final TextEditingController _noteController;

  @override
  void initState() {
    super.initState();
    _value = widget.participant.currentValue ?? EvaluationValue.noBasis;
    _tags = List<String>.from(widget.participant.reasonTags);
    _noteController = TextEditingController(text: widget.participant.note);
  }

  @override
  void dispose() {
    _noteController.dispose();
    super.dispose();
  }

  List<String> _allowedTags(EvaluationValue v) {
    final neg = v == EvaluationValue.neg2 || v == EvaluationValue.neg1;
    final pos = v == EvaluationValue.pos1 || v == EvaluationValue.pos2;
    const ap = [
      'clear_request',
      'fair_closure',
      'useful_updates',
      'coordinated_well',
    ];
    const an = [
      'unclear_request',
      'poor_updates',
      'closed_unfairly',
      'hard_to_coordinate',
    ];
    const cp = [
      'delivered_as_promised',
      'very_useful',
      'communicated_honestly',
      'above_expectation',
    ];
    const cn = [
      'did_not_follow_through',
      'overpromised',
      'created_extra_work',
      'poor_communication',
    ];
    const fp = [
      'reached_right_person',
      'forwarded_quickly',
      'useful_routing_note',
      'crucial_bridge',
    ];
    const fn = [
      'sent_to_wrong_people',
      'created_noise',
      'forwarded_too_late',
      'misleading_note',
    ];
    return switch (widget.participant.role) {
      EvaluationParticipantRole.author =>
        neg ? an : (pos ? ap : [...ap, ...an]),
      EvaluationParticipantRole.committer =>
        neg ? cn : (pos ? cp : [...cp, ...cn]),
      EvaluationParticipantRole.forwarder =>
        neg ? fn : (pos ? fp : [...fp, ...fn]),
    };
  }

  String _promptText() {
    if (widget.participant.role == EvaluationParticipantRole.committer &&
        widget.participant.promptVariant == 'handoff') {
      return widget.l10n.evaluationPromptHelpOffererHandoff;
    }
    return switch (widget.participant.role) {
      EvaluationParticipantRole.author => widget.l10n.evaluationPromptAuthor,
      EvaluationParticipantRole.committer =>
        widget.l10n.evaluationPromptHelpOfferer,
      EvaluationParticipantRole.forwarder =>
        widget.l10n.evaluationPromptForwarder,
    };
  }

  Future<void> _save() async {
    final needs = _value.requiresReasonTag;
    if (needs && _tags.isEmpty) {
      return;
    }
    await widget.onSave(
      _value,
      _tags,
      _noteController.text,
      _ackTags.toList(),
    );
    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = widget.l10n;
    final participant = widget.participant;
    final tt = context.tt;
    final needs = _value.requiresReasonTag;
    final allowTags = _value.allowsReasonTag;
    final pool = allowTags ? _allowedTags(_value) : <String>[];

    return Padding(
      padding: EdgeInsets.only(
        left: tt.screenHPadding,
        right: tt.screenHPadding,
        top: tt.rowGap,
        bottom: MediaQuery.viewInsetsOf(context).bottom + tt.sectionGap,
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              contactNameOf(participant.userId).isNotEmpty
                  ? contactNameOf(participant.userId)
                  : participant.displayName,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            SizedBox(height: tt.tightGap * 2),
            Text(
              _promptText(),
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            SizedBox(height: tt.sectionGap),
            Wrap(
              spacing: tt.iconTextGap,
              runSpacing: tt.iconTextGap,
              children: [
                for (final v in EvaluationValue.values)
                  ChoiceChip(
                    label: Text(_label(v, l10n)),
                    selected: _value == v,
                    onSelected: (_) => setState(() => _value = v),
                  ),
              ],
            ),
            if (allowTags && pool.isNotEmpty) ...[
              SizedBox(height: tt.sectionGap),
              Text(
                needs ? 'Choose reason (required)' : 'Reason (optional)',
                style: Theme.of(context).textTheme.labelLarge,
              ),
              SizedBox(height: tt.iconTextGap),
              Wrap(
                spacing: tt.iconTextGap,
                runSpacing: tt.iconTextGap,
                children: [
                  for (final t in pool)
                    FilterChip(
                      label: Text(t),
                      selected: _tags.contains(t),
                      onSelected: (sel) => setState(() {
                        if (sel) {
                          _tags.add(t);
                        } else {
                          _tags.remove(t);
                        }
                      }),
                    ),
                ],
              ),
            ],
            SizedBox(height: tt.sectionGap),
            Text(
              l10n.closeAckPrompt,
              style: Theme.of(context).textTheme.labelLarge,
            ),
            SizedBox(height: tt.iconTextGap),
            CapabilityChipSet(
              selectedSlugs: _ackTags,
              onChanged: (slugs) => setState(() {
                _ackTags
                  ..clear()
                  ..addAll(slugs);
              }),
            ),
            SizedBox(height: tt.rowGap),
            TextField(
              controller: _noteController,
              decoration: const InputDecoration(
                labelText: 'Short note (optional)',
                border: OutlineInputBorder(),
              ),
              maxLines: 3,
              maxLength: 280,
            ),
            EvaluationPrivacyInfoRow(
              shortLabel: l10n.evaluationPrivacyShort,
              fullText: l10n.evaluationPrivateHint,
            ),
            SizedBox(height: tt.sectionGap),
            FilledButton(
              onPressed: _save,
              child: Text(l10n.evaluationSave),
            ),
          ],
        ),
      ),
    );
  }
}

String _label(EvaluationValue v, L10n l10n) => switch (v) {
  EvaluationValue.noBasis => l10n.evaluationNoBasisLabel,
  EvaluationValue.neg2 => l10n.evaluationVeryBadLabel,
  EvaluationValue.neg1 => l10n.evaluationBadLabel,
  EvaluationValue.zero => l10n.evaluationNoEffectLabel,
  EvaluationValue.pos1 => l10n.evaluationGoodLabel,
  EvaluationValue.pos2 => l10n.evaluationVeryGoodLabel,
};
