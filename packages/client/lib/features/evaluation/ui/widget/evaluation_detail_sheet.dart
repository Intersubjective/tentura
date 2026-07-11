import 'dart:async' show unawaited;

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/rendering.dart' show View;
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/contacts/contact_name_overlay.dart';
import 'package:tentura/domain/entity/image_entity.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/capability/ui/widget/capability_chip_set.dart';
import 'package:tentura/features/evaluation/domain/entity/evaluation_participant.dart';
import 'package:tentura/features/evaluation/domain/entity/evaluation_trust_selection.dart';
import 'package:tentura/features/evaluation/domain/entity/evaluation_value.dart';
import 'package:tentura/features/evaluation/ui/widget/evaluation_trust_control.dart';
import 'package:tentura/features/profile/ui/bloc/profile_cubit.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/test_ids.dart';
import 'package:tentura/ui/widget/self_aware_profile_avatar.dart';

/// Modal sheet to set one participant evaluation.
Future<void> showEvaluationDetailSheet({
  required BuildContext context,
  required EvaluationParticipant participant,
  required Future<bool> Function(
    EvaluationValue value,
    List<String> tags,
    String note,
    List<String> acknowledgedHelpTags,
  )
  onSave,
}) async {
  final l10n = L10n.of(context)!;
  ProfileCubit? profileCubit;
  try {
    profileCubit = context.read<ProfileCubit>();
  } on ProviderNotFoundException {
    profileCubit = null;
  }
  await showTenturaAdaptiveSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    enableDrag: false,
    builder: (ctx) {
      Widget body = _EvaluationDetailSheetBody(
        l10n: l10n,
        participant: participant,
        onSave: onSave,
      );
      if (profileCubit != null) {
        body = BlocProvider<ProfileCubit>.value(
          value: profileCubit,
          child: body,
        );
      }
      return body;
    },
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
  final Future<bool> Function(
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

class _EvaluationDetailSheetBodyState
    extends State<_EvaluationDetailSheetBody> {
  late EvaluationTrustSelection _selection;
  late final List<String> _tags;
  final _ackTags = <String>{};
  late final TextEditingController _noteController;
  late final EvaluationTrustSelection _initialSelection;
  late final List<String> _initialTags;
  late final String _initialNote;
  late final Set<String> _initialAckTags;
  late final Map<String, String> _tagLabelBySlug;

  bool _saveAttempted = false;
  bool _isSaving = false;
  String? _categoryError;
  String? _intensityError;
  String? _reasonError;

  final _trustSectionKey = GlobalKey();
  final _reasonSectionKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _selection = EvaluationTrustSelectionX.fromEvaluationValue(
      widget.participant.currentValue,
    );
    _tags = List<String>.from(widget.participant.reasonTags);
    _noteController = TextEditingController(text: widget.participant.note);
    _initialSelection = _selection;
    _initialTags = List<String>.from(_tags);
    _initialNote = widget.participant.note;
    _initialAckTags = <String>{};
    _tagLabelBySlug = _buildTagLabelBySlug(widget.l10n);
  }

  @override
  void dispose() {
    _noteController.dispose();
    super.dispose();
  }

  String get _displayName {
    final contact = contactNameOf(widget.participant.userId);
    if (contact.isNotEmpty) {
      return contact;
    }
    return widget.participant.displayName;
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

  String _roleLabel(L10n l10n) => switch (widget.participant.role) {
        EvaluationParticipantRole.author => l10n.evaluationRoleAuthor,
        EvaluationParticipantRole.committer => l10n.evaluationRoleHelpOfferer,
        EvaluationParticipantRole.forwarder => l10n.evaluationRoleForwarder,
      };

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

  bool get _isDirty {
    if (_selection == EvaluationTrustSelection.decreasePending ||
        _selection == EvaluationTrustSelection.increasePending) {
      return true;
    }
    return _selection != _initialSelection ||
        _tags.length != _initialTags.length ||
        !_tags.every(_initialTags.contains) ||
        _noteController.text != _initialNote ||
        !_setEquals(_ackTags, _initialAckTags);
  }

  bool _setEquals(Set<String> a, Set<String> b) =>
      a.length == b.length && a.containsAll(b);

  void _onSelectionChanged(EvaluationTrustSelection selection) {
    setState(() {
      _selection = selection;
      if (!selection.showsReasonCard) {
        _tags.clear();
      } else {
        final value = selection.evaluationValue!;
        final pool = _allowedTags(value);
        _tags.retainWhere(pool.contains);
      }
      if (_selection != EvaluationTrustSelection.unselected) {
        _categoryError = null;
      }
      if (_selection.isComplete) {
        _intensityError = null;
      }
      final value = selection.evaluationValue;
      if (value == null || !value.requiresReasonTag || _tags.isNotEmpty) {
        _reasonError = null;
      }
    });
  }

  Future<void> _scrollTo(GlobalKey key) async {
    final ctx = key.currentContext;
    if (ctx == null) {
      return;
    }
    await Scrollable.ensureVisible(
      ctx,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeInOut,
      alignment: 0.1,
    );
  }

  bool _validate() {
    final l10n = widget.l10n;
    String? categoryError;
    String? intensityError;
    String? reasonError;

    if (_selection == EvaluationTrustSelection.unselected) {
      categoryError = l10n.evaluationTrustChoiceRequired;
    } else if (_selection == EvaluationTrustSelection.decreasePending ||
        _selection == EvaluationTrustSelection.increasePending) {
      intensityError = l10n.evaluationTrustIntensityRequired;
    } else {
      final value = _selection.evaluationValue;
      if (value != null &&
          value.requiresReasonTag &&
          _tags.isEmpty &&
          _selection.showsReasonCard) {
        reasonError = l10n.evaluationReasonValidationError;
      }
    }

    setState(() {
      _categoryError = categoryError;
      _intensityError = intensityError;
      _reasonError = reasonError;
    });

    if (categoryError != null) {
      unawaited(_scrollTo(_trustSectionKey));
      SemanticsService.sendAnnouncement(
        View.of(context),
        categoryError,
        TextDirection.ltr,
      );
      return false;
    }
    if (intensityError != null) {
      unawaited(_scrollTo(_trustSectionKey));
      SemanticsService.sendAnnouncement(
        View.of(context),
        intensityError,
        TextDirection.ltr,
      );
      return false;
    }
    if (reasonError != null) {
      unawaited(_scrollTo(_reasonSectionKey));
      SemanticsService.sendAnnouncement(
        View.of(context),
        reasonError,
        TextDirection.ltr,
      );
      return false;
    }
    return true;
  }

  Future<void> _save() async {
    if (_isSaving) {
      return;
    }
    setState(() => _saveAttempted = true);
    if (!_validate()) {
      return;
    }
    final value = _selection.evaluationValue!;
    setState(() => _isSaving = true);
    final ok = await widget.onSave(
      value,
      _tags,
      _noteController.text,
      _ackTags.toList(),
    );
    if (!mounted) {
      return;
    }
    setState(() => _isSaving = false);
    if (ok) {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = widget.l10n;
    final participant = widget.participant;
    final tt = context.tt;
    final theme = Theme.of(context);
    final resolvedValue = _selection.evaluationValue;
    final showReasonCard = _selection.showsReasonCard;
    final pool = showReasonCard && resolvedValue != null
        ? _allowedTags(resolvedValue)
        : <String>[];
    final needsReason = resolvedValue?.requiresReasonTag ?? false;

    final profile = Profile(
      id: participant.userId,
      displayName: participant.displayName,
      contactName: contactNameOf(participant.userId),
      image: participant.imageId.isNotEmpty
          ? ImageEntity(id: participant.imageId, authorId: participant.userId)
          : null,
    );

    final contributionLine = [
      _roleLabel(l10n),
      if (participant.contributionSummary.isNotEmpty)
        participant.contributionSummary,
    ].join(' · ');

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
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SelfAwareAvatar.small(profile: profile),
                  SizedBox(width: tt.avatarTextGap),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _displayName,
                          style: theme.textTheme.titleMedium,
                        ),
                        if (contributionLine.isNotEmpty) ...[
                          SizedBox(height: tt.tightGap),
                          Text(
                            contributionLine,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                        if (participant.causalHint.isNotEmpty) ...[
                          SizedBox(height: tt.tightGap),
                          Text(
                            participant.causalHint,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
              SizedBox(height: tt.rowGap),
              Text(
                _promptText(),
                style: theme.textTheme.bodyMedium,
              ),
              SizedBox(height: tt.sectionGap),
              KeyedSubtree(
                key: _trustSectionKey,
                child: EvaluationTrustControl(
                  selection: _selection,
                  onChanged: _onSelectionChanged,
                  participantName: _displayName,
                  categoryError: _saveAttempted ? _categoryError : null,
                  intensityError: _saveAttempted ? _intensityError : null,
                ),
              ),
              if (showReasonCard && pool.isNotEmpty) ...[
                SizedBox(height: tt.sectionGap),
                KeyedSubtree(
                  key: _reasonSectionKey,
                  child: TenturaTechCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          needsReason
                              ? l10n.evaluationReasonRequiredHeading
                              : l10n.evaluationReasonOptionalHeading,
                          style: theme.textTheme.labelLarge,
                        ),
                        SizedBox(height: tt.iconTextGap),
                        Wrap(
                          spacing: tt.iconTextGap,
                          runSpacing: tt.iconTextGap,
                          children: [
                            for (final t in pool)
                              FilterChip(
                                key: TestIds.key(
                                  TestIds.evaluationReasonChip(t),
                                ),
                                label: Text(
                                  _tagLabelBySlug[t] ??
                                      l10n.evaluationReasonUnknown,
                                ),
                                selected: _tags.contains(t),
                                onSelected: (sel) => setState(() {
                                  if (sel) {
                                    _tags.add(t);
                                  } else {
                                    _tags.remove(t);
                                  }
                                  if (_tags.isNotEmpty) {
                                    _reasonError = null;
                                  }
                                }),
                              ),
                          ],
                        ),
                        if (_saveAttempted && _reasonError != null) ...[
                          SizedBox(height: tt.tightGap),
                          Semantics(
                            liveRegion: true,
                            child: Text(
                              _reasonError!,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: tt.danger,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
              SizedBox(height: tt.sectionGap),
              Text(
                l10n.evaluationAckOptionalHeading,
                style: theme.textTheme.labelLarge,
              ),
              SizedBox(height: tt.iconTextGap),
              Text(
                l10n.closeAckPrompt,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
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
              SizedBox(height: tt.sectionGap),
              Text(
                l10n.evaluationSubjectiveTrustHint,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              SizedBox(height: tt.rowGap),
              FilledButton(
                key: TestIds.key(TestIds.evaluationSave),
                onPressed: _isSaving ? null : _save,
                child: _isSaving
                    ? SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator.adaptive(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            theme.colorScheme.onPrimary,
                          ),
                        ),
                      )
                    : Text(l10n.evaluationSave),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

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
