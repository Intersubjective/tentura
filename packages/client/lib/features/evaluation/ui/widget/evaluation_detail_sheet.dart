import 'package:flutter/material.dart';

import 'package:tentura/features/evaluation/domain/entity/evaluation_participant.dart';
import 'package:tentura/features/evaluation/domain/entity/evaluation_value.dart';
import 'package:tentura/ui/l10n/l10n.dart';

/// Modal sheet to set one participant evaluation.
Future<void> showEvaluationDetailSheet({
  required BuildContext context,
  required EvaluationParticipant participant,
  required Future<void> Function(
    EvaluationValue value,
    List<String> tags,
    String note,
  ) onSave,
}) async {
  final l10n = L10n.of(context)!;
  var value = participant.currentValue ?? EvaluationValue.noBasis;
  final tags = List<String>.from(participant.reasonTags);
  final noteController = TextEditingController(text: participant.note);

  List<String> allowedTags(EvaluationValue v) {
    final neg = v == EvaluationValue.neg2 || v == EvaluationValue.neg1;
    final pos = v == EvaluationValue.pos1 || v == EvaluationValue.pos2;
    const ap = ['clear_request', 'fair_closure', 'useful_updates', 'coordinated_well'];
    const an = ['unclear_request', 'poor_updates', 'closed_unfairly', 'hard_to_coordinate'];
    const cp = ['delivered_as_promised', 'very_useful', 'communicated_honestly', 'above_expectation'];
    const cn = ['did_not_follow_through', 'overpromised', 'created_extra_work', 'poor_communication'];
    const fp = ['reached_right_person', 'forwarded_quickly', 'useful_routing_note', 'crucial_bridge'];
    const fn = ['sent_to_wrong_people', 'created_noise', 'forwarded_too_late', 'misleading_note'];
    return switch (participant.role) {
      EvaluationParticipantRole.author => neg ? an : (pos ? ap : [...ap, ...an]),
      EvaluationParticipantRole.committer => neg ? cn : (pos ? cp : [...cp, ...cn]),
      EvaluationParticipantRole.forwarder => neg ? fn : (pos ? fp : [...fp, ...fn]),
    };
  }

  String prompt(EvaluationParticipantRole r) => switch (r) {
        EvaluationParticipantRole.author =>
          'How did the author’s contribution affect this beacon?',
        EvaluationParticipantRole.committer =>
          'How did this person’s commitment affect this beacon?',
        EvaluationParticipantRole.forwarder =>
          'How did this forwarding help or hurt this beacon?',
      };

  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) {
      return StatefulBuilder(
        builder: (context, setState) {
          final needs = value.requiresReasonTag;
          final allowTags = value.allowsReasonTag;
          final pool = allowTags ? allowedTags(value) : <String>[];

          return Padding(
            padding: EdgeInsets.only(
              left: 16,
              right: 16,
              top: 8,
              bottom: MediaQuery.viewInsetsOf(context).bottom + 16,
            ),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    participant.title,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    prompt(participant.role),
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final v in EvaluationValue.values)
                        ChoiceChip(
                          label: Text(_label(v, l10n)),
                          selected: value == v,
                          onSelected: (_) => setState(() => value = v),
                        ),
                    ],
                  ),
                  if (allowTags && pool.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Text(
                      needs ? 'Choose reason (required)' : 'Reason (optional)',
                      style: Theme.of(context).textTheme.labelLarge,
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        for (final t in pool)
                          FilterChip(
                            label: Text(t),
                            selected: tags.contains(t),
                            onSelected: (sel) => setState(() {
                              if (sel) {
                                tags.add(t);
                              } else {
                                tags.remove(t);
                              }
                            }),
                          ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 8),
                  TextField(
                    controller: noteController,
                    decoration: const InputDecoration(
                      labelText: 'Short note (optional)',
                      border: OutlineInputBorder(),
                    ),
                    maxLines: 3,
                    maxLength: 280,
                  ),
                  Text(
                    l10n.evaluationPrivateHint,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 12),
                  FilledButton(
                    onPressed: () async {
                      if (needs && tags.isEmpty) {
                        return;
                      }
                      await onSave(value, tags, noteController.text);
                      if (context.mounted) {
                        Navigator.of(context).pop();
                      }
                    },
                    child: Text(l10n.evaluationSave),
                  ),
                ],
              ),
            ),
          );
        },
      );
    },
  );
}

String _label(EvaluationValue v, L10n l10n) => switch (v) {
      EvaluationValue.noBasis => l10n.evaluationNoBasisLabel,
      EvaluationValue.neg2 => '-2',
      EvaluationValue.neg1 => '-1',
      EvaluationValue.zero => '0',
      EvaluationValue.pos1 => '+1',
      EvaluationValue.pos2 => '+2',
    };
