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
  late final EvaluationValue _initialValue;
  late final List<String> _initialTags;
  late final String _initialNote;
  late final Map<String, String> _tagLabelBySlug;

  @override
  void initState() {
    super.initState();
    _value = widget.participant.currentValue ?? EvaluationValue.noBasis;
    _tags = List<String>.from(widget.participant.reasonTags);
    _noteController = TextEditingController(text: widget.participant.note);
    _initialValue = _value;
    _initialTags = List<String>.from(_tags);
    _initialNote = widget.participant.note;
    _tagLabelBySlug = _buildTagLabelBySlug(widget.l10n);
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

  bool get _isDirty =>
      _value != _initialValue ||
      _tags.length != _initialTags.length ||
      !_tags.every(_initialTags.contains) ||
      _noteController.text != _initialNote ||
      _ackTags.isNotEmpty;

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

    return TenturaSheetDismissGuard(
      isDirty: _isDirty,
      child: Padding(
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
                needs
                    ? l10n.evaluationReasonRequiredHeading
                    : l10n.evaluationReasonOptionalHeading,
                style: Theme.of(context).textTheme.labelLarge,
              ),
              SizedBox(height: tt.iconTextGap),
              Wrap(
                spacing: tt.iconTextGap,
                runSpacing: tt.iconTextGap,
                children: [
                  for (final t in pool)
                    FilterChip(
                      label: Text(_tagLabelBySlug[t] ?? l10n.evaluationReasonUnknown),
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
              decoration: InputDecoration(
                labelText: l10n.evaluationNoteLabelOptional,
                border: const OutlineInputBorder(),
              ),
              maxLines: 3,
              maxLength: 280,
              onChanged: (_) => setState(() {}),
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

Map<String, String> _buildTagLabelBySlug(L10n l10n) => {
  'clear_request': l10n.evaluationReasonClearRequest,
  'fair_closure': l10n.evaluationReasonFairClosure,
  'useful_updates': l10n.evaluationReasonUsefulUpdates,
  'coordinated_well': l10n.evaluationReasonCoordinatedWell,
  'unclear_request': l10n.evaluationReasonUnclearRequest,
  'poor_updates': l10n.evaluationReasonPoorUpdates,
  'closed_unfairly': l10n.evaluationReasonClosedUnfairly,
  'hard_to_coordinate': l10n.evaluationReasonHardToCoordinate,
  'delivered_as_promised': l10n.evaluationReasonDeliveredAsPromised,
  'very_useful': l10n.evaluationReasonVeryUseful,
  'communicated_honestly': l10n.evaluationReasonCommunicatedHonestly,
  'above_expectation': l10n.evaluationReasonAboveExpectation,
  'did_not_follow_through': l10n.evaluationReasonDidNotFollowThrough,
  'overpromised': l10n.evaluationReasonOverpromised,
  'created_extra_work': l10n.evaluationReasonCreatedExtraWork,
  'poor_communication': l10n.evaluationReasonPoorCommunication,
  'reached_right_person': l10n.evaluationReasonReachedRightPerson,
  'forwarded_quickly': l10n.evaluationReasonForwardedQuickly,
  'useful_routing_note': l10n.evaluationReasonUsefulRoutingNote,
  'crucial_bridge': l10n.evaluationReasonCrucialBridge,
  'sent_to_wrong_people': l10n.evaluationReasonSentToWrongPeople,
  'created_noise': l10n.evaluationReasonCreatedNoise,
  'forwarded_too_late': l10n.evaluationReasonForwardedTooLate,
  'misleading_note': l10n.evaluationReasonMisleadingNote,
};
