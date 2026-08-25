import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/contacts/contact_name_overlay.dart';
import 'package:tentura/domain/entity/image_entity.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/evaluation/domain/entity/evaluation_participant.dart';
import 'package:tentura/features/evaluation/domain/entity/evaluation_value.dart';
import 'package:tentura/features/evaluation/ui/presenter/evaluation_capability_presenter.dart';
import 'package:tentura/features/evaluation/ui/widget/evaluation_capability_picker_sheet.dart';
import 'package:tentura/features/evaluation/ui/widget/evaluation_impact_control.dart';
import 'package:tentura/features/profile/ui/bloc/profile_cubit.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/test_ids.dart';
import 'package:tentura/ui/widget/self_aware_profile_avatar.dart';

/// Opens the one-question contribution impact editor.
///
/// The callback intentionally has no reason-tag argument. Existing legacy
/// reasons are preserved by the nullable server argument when this client
/// omits it.
Future<void> showEvaluationDetailSheet({
  required BuildContext context,
  required EvaluationParticipant participant,
  bool isDraftMode = false,
  required Future<bool> Function(
    EvaluationValue value,
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

  final body = _EvaluationDetailSheetBody(
    l10n: l10n,
    participant: participant,
    isDraftMode: isDraftMode,
    onSave: onSave,
  );
  await showTenturaAdaptiveSheet<void>(
    context: context,
    enableDrag: false,
    builder: (_) => profileCubit == null
        ? body
        : BlocProvider<ProfileCubit>.value(value: profileCubit, child: body),
  );
}

class _EvaluationDetailSheetBody extends StatefulWidget {
  const _EvaluationDetailSheetBody({
    required this.l10n,
    required this.participant,
    required this.isDraftMode,
    required this.onSave,
  });

  final L10n l10n;
  final EvaluationParticipant participant;
  final bool isDraftMode;
  final Future<bool> Function(
    EvaluationValue value,
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
  final _impactKey = GlobalKey();
  late EvaluationValue? _value;
  late EvaluationValue? _initialValue;
  late TextEditingController _noteController;
  late Set<String> _ackTags;
  late Set<String> _initialAckTags;
  late String _initialNote;
  String? _choiceError;
  bool _saveAttempted = false;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _value = widget.participant.currentValue == EvaluationValue.noBasis
        ? null
        : widget.participant.currentValue;
    _initialValue = _value;
    _noteController = TextEditingController(text: widget.participant.note);
    _initialNote = widget.participant.note;
    _ackTags = widget.participant.acknowledgedHelpTags.toSet();
    _initialAckTags = _ackTags.toSet();
  }

  @override
  void dispose() {
    _noteController.dispose();
    super.dispose();
  }

  String get _displayName {
    final contact = contactNameOf(widget.participant.userId);
    return contact.isEmpty ? widget.participant.displayName : contact;
  }

  bool get _isDraft => widget.isDraftMode;

  bool get _positive =>
      _value == EvaluationValue.pos1 || _value == EvaluationValue.pos2;

  bool get _showAcknowledgements =>
      !_isDraft &&
      _positive &&
      widget.participant.maxAcknowledgedHelpTags > 0 &&
      widget.participant.acknowledgeableHelpTags.isNotEmpty;

  bool get _isDirty =>
      _value != _initialValue ||
      _noteController.text != _initialNote ||
      !_sameSet(_ackTags, _initialAckTags);

  static bool _sameSet(Set<String> a, Set<String> b) =>
      a.length == b.length && a.containsAll(b);

  String _roleLabel() => switch (widget.participant.role) {
    EvaluationParticipantRole.author => widget.l10n.evaluationRoleAuthor,
    EvaluationParticipantRole.committer =>
      widget.l10n.evaluationRoleHelpOfferer,
    EvaluationParticipantRole.forwarder => widget.l10n.evaluationRoleForwarder,
  };

  String _promptText() =>
      widget.participant.role == EvaluationParticipantRole.committer &&
          widget.participant.promptVariant == 'handoff'
      ? widget.l10n.evaluationPromptHelpOffererHandoff
      : switch (widget.participant.role) {
          EvaluationParticipantRole.author =>
            widget.l10n.evaluationPromptAuthor,
          EvaluationParticipantRole.committer =>
            widget.l10n.evaluationPromptHelpOfferer,
          EvaluationParticipantRole.forwarder =>
            widget.l10n.evaluationPromptForwarder,
        };

  void _changeValue(EvaluationValue? value) {
    setState(() {
      _value = value;
      if (value == null ||
          (value != EvaluationValue.pos1 && value != EvaluationValue.pos2)) {
        _ackTags.clear();
      }
      if (value != null) {
        _choiceError = null;
      }
    });
  }

  Future<void> _editAcknowledgements() async {
    final selected = await EvaluationCapabilityPickerSheet.show(
      context,
      initialSlugs: _ackTags,
      availableSlugs: widget.participant.acknowledgeableHelpTags.toSet(),
      maxSelection: widget.participant.maxAcknowledgedHelpTags,
    );
    if (!mounted || selected == null) {
      return;
    }
    setState(() => _ackTags = selected);
  }

  Future<void> _scrollToImpact() async {
    final target = _impactKey.currentContext;
    if (target == null) {
      return;
    }
    await Scrollable.ensureVisible(
      target,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeInOut,
      alignment: 0.1,
    );
  }

  Future<void> _save() async {
    if (_isSaving) {
      return;
    }
    setState(() => _saveAttempted = true);
    if (_value == null) {
      setState(() => _choiceError = widget.l10n.evaluationChooseImpact);
      await _scrollToImpact();
      return;
    }
    setState(() => _isSaving = true);
    final ok = await widget.onSave(
      _value!,
      _noteController.text,
      _showAcknowledgements ? _ackTags.toList() : const [],
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
    final theme = Theme.of(context);
    final tt = context.tt;
    final participant = widget.participant;
    final profile = Profile(
      id: participant.userId,
      displayName: participant.displayName,
      contactName: contactNameOf(participant.userId),
      image: participant.imageId.isEmpty
          ? null
          : ImageEntity(id: participant.imageId, authorId: participant.userId),
    );
    final roleLine = _roleLabel();
    final contributionLine = participant.contributionSummary.trim();
    final roleContribution = contributionLine.isEmpty
        ? roleLine
        : '$roleLine · $contributionLine';

    return TenturaSheetDismissGuard(
      isDirty: _isDirty,
      child: SafeArea(
        top: false,
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
                          SizedBox(height: tt.tightGap),
                          Text(
                            roleContribution,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                SizedBox(height: tt.rowGap),
                Text(_promptText(), style: theme.textTheme.bodyMedium),
                SizedBox(height: tt.sectionGap),
                KeyedSubtree(
                  key: _impactKey,
                  child: EvaluationImpactControl(
                    value: _value,
                    onChanged: _changeValue,
                  ),
                ),
                if (_saveAttempted && _choiceError != null) ...[
                  SizedBox(height: tt.tightGap),
                  Semantics(
                    liveRegion: true,
                    child: Text(
                      _choiceError!,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: tt.danger,
                      ),
                    ),
                  ),
                ],
                if (_showAcknowledgements) ...[
                  SizedBox(height: tt.sectionGap),
                  _CapabilityAcknowledgementField(
                    tags: _ackTags,
                    l10n: widget.l10n,
                    onTap: _editAcknowledgements,
                  ),
                ],
                SizedBox(height: tt.sectionGap),
                TextField(
                  controller: _noteController,
                  maxLength: 280,
                  maxLines: 3,
                  minLines: 3,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    labelText: widget.l10n.evaluationNoteLabelOptional,
                    border: const OutlineInputBorder(),
                  ),
                ),
                SizedBox(height: tt.rowGap),
                _EvaluationRevealNotice(
                  isDraft: _isDraft,
                  name: _displayName,
                  l10n: widget.l10n,
                ),
                SizedBox(height: tt.rowGap),
                FilledButton(
                  key: TestIds.key(TestIds.evaluationSave),
                  onPressed: _isSaving ? null : _save,
                  child: _isSaving
                      ? SizedBox(
                          height: tt.iconSize,
                          width: tt.iconSize,
                          child: CircularProgressIndicator.adaptive(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              theme.colorScheme.onPrimary,
                            ),
                          ),
                        )
                      : Text(widget.l10n.evaluationSave),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _EvaluationRevealNotice extends StatelessWidget {
  const _EvaluationRevealNotice({
    required this.isDraft,
    required this.name,
    required this.l10n,
  });

  final bool isDraft;
  final String name;
  final L10n l10n;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Text(
      isDraft
          ? l10n.evaluationRevealNoticeDraft
          : l10n.evaluationRevealNoticeLive(name),
      style: theme.textTheme.bodySmall?.copyWith(
        color: theme.colorScheme.onSurfaceVariant,
      ),
    );
  }
}

class _CapabilityAcknowledgementField extends StatelessWidget {
  const _CapabilityAcknowledgementField({
    required this.tags,
    required this.l10n,
    required this.onTap,
  });

  final Set<String> tags;
  final L10n l10n;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tt = context.tt;
    final summary = presentAcknowledgedCapabilities(tags, l10n);
    return Semantics(
      button: true,
      label: summary.isEmpty ? l10n.evaluationCapabilityChoose : summary,
      child: InkWell(
        key: TestIds.key(TestIds.evaluationCapabilityField),
        onTap: onTap,
        borderRadius: BorderRadius.circular(tt.buttonRadius),
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            minHeight: kMinInteractiveDimension,
          ),
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: tt.tightGap),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    summary.isEmpty ? l10n.evaluationCapabilityChoose : summary,
                    style: theme.textTheme.bodyMedium,
                  ),
                ),
                Icon(Icons.chevron_right_rounded, size: tt.iconSize),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
