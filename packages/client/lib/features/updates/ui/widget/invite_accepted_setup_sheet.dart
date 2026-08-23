import 'dart:async';

import 'package:flutter/material.dart';

import 'package:tentura/consts.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/capability/invite_seed_prompt_state.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/capability/ui/widget/capability_chip_set.dart';
import 'package:tentura/features/updates/domain/use_case/invite_accepted_setup_case.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/test_ids.dart';
import 'package:tentura/ui/utils/string_input_validator.dart';

enum InviteAcceptedSetupAction { saved, skipped }

class InviteAcceptedSetupResult {
  const InviteAcceptedSetupResult({
    required this.action,
    required this.profile,
  });

  final InviteAcceptedSetupAction action;
  final Profile profile;
}

/// Adaptive setup flow shown only for pending new-account invite receipts.
class InviteAcceptedSetupSheet extends StatefulWidget {
  const InviteAcceptedSetupSheet({
    required this.subjectId,
    required this.profile,
    required this.prompt,
    required this.setupCase,
    super.key,
  });

  static Future<InviteAcceptedSetupResult?> show({
    required BuildContext context,
    required String subjectId,
    required Profile profile,
    required InviteSeedPromptState prompt,
    required InviteAcceptedSetupPort setupCase,
  }) => showTenturaAdaptiveSheet<InviteAcceptedSetupResult>(
    context: context,
    showDragHandle: false,
    enableDrag: false,
    builder: (_) => InviteAcceptedSetupSheet(
      subjectId: subjectId,
      profile: profile,
      prompt: prompt,
      setupCase: setupCase,
    ),
  );

  final String subjectId;
  final Profile profile;
  final InviteSeedPromptState prompt;
  final InviteAcceptedSetupPort setupCase;

  @override
  State<InviteAcceptedSetupSheet> createState() =>
      _InviteAcceptedSetupSheetState();
}

class _InviteAcceptedSetupSheetState extends State<InviteAcceptedSetupSheet>
    with StringInputValidator {
  static const _maxSelections = 3;

  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _privateNameController;
  late Set<String> _selectedSlugs;
  late String _privateNameBaseline;
  late Profile _profile;

  bool _editPrivateName = false;
  bool _busy = false;
  bool _completed = false;
  bool _hasPersistedRename = false;
  double _headerDragDistance = 0;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _profile = widget.profile;
    _selectedSlugs = widget.prompt.slugs.toSet();
    _privateNameBaseline = _initialPrivateName(widget.profile);
    _privateNameController = TextEditingController(
      text: _privateNameBaseline,
    );
  }

  @override
  void dispose() {
    _privateNameController.dispose();
    super.dispose();
  }

  static String _initialPrivateName(Profile profile) {
    final privateName = profile.contactName.trim();
    if (privateName.isNotEmpty) return privateName;
    final publicName = profile.displayName.trim();
    return publicName.isNotEmpty ? publicName : profile.canonicalPublicLabel;
  }

  bool get _selectionChanged =>
      _selectedSlugs.length != widget.prompt.slugs.length ||
      !_selectedSlugs.containsAll(widget.prompt.slugs);

  bool get _privateNameChanged =>
      _editPrivateName &&
      _privateNameController.text.trim() != _privateNameBaseline;

  bool get _isDirty => _selectionChanged || _privateNameChanged;

  TenturaSheetDiscardCopy _discardCopy(L10n l10n) => TenturaSheetDiscardCopy(
    title: l10n.inviteAcceptedSetupDiscardTitle,
    body: l10n.inviteAcceptedSetupDiscardBody,
    confirmLabel: l10n.inviteAcceptedSetupDiscardConfirm,
    cancelLabel: l10n.inviteAcceptedSetupDiscardKeepEditing,
  );

  Future<void> _requestClose() => TenturaSheetDismissGuard.requestClose(
    context,
    isDirty: _isDirty,
    canDismiss: !_busy,
    discardCopy: _discardCopy(L10n.of(context)!),
  );

  Future<void> _save() async {
    if (_busy) return;
    final l10n = L10n.of(context)!;
    setState(() => _errorMessage = null);
    if (_selectedSlugs.isEmpty) {
      setState(
        () => _errorMessage = l10n.inviteAcceptedSetupSelectCapabilityError,
      );
      return;
    }
    if (_editPrivateName && !(_formKey.currentState?.validate() ?? false)) {
      return;
    }

    setState(() => _busy = true);
    final privateName = _privateNameController.text.trim();
    final renameNeeded = _privateNameChanged;
    if (renameNeeded) {
      try {
        await widget.setupCase.rename(
          subjectId: widget.subjectId,
          privateName: privateName,
        );
      } on Object {
        if (!mounted) return;
        setState(() {
          _busy = false;
          _errorMessage = l10n.inviteAcceptedSetupRenameError;
        });
        return;
      }
      if (!mounted) return;
      _privateNameBaseline = privateName;
      _profile = _profile.copyWith(contactName: privateName);
      _hasPersistedRename = true;
    }

    try {
      await widget.setupCase.answer(
        subjectId: widget.subjectId,
        slugs: _selectedSlugs.toList(),
      );
    } on Object {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _errorMessage = _hasPersistedRename
            ? l10n.inviteAcceptedSetupPartialSuccessError
            : l10n.inviteAcceptedSetupCapabilitiesError;
      });
      return;
    }
    if (!mounted) return;
    _finish(InviteAcceptedSetupAction.saved);
  }

  Future<void> _skip() async {
    if (_busy) return;
    final l10n = L10n.of(context)!;
    setState(() {
      _busy = true;
      _errorMessage = null;
    });
    try {
      await widget.setupCase.skip(widget.subjectId);
    } on Object {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _errorMessage = l10n.inviteAcceptedSetupSkipError;
      });
      return;
    }
    if (!mounted) return;
    _finish(InviteAcceptedSetupAction.skipped);
  }

  void _finish(InviteAcceptedSetupAction action) {
    if (_completed) return;
    setState(() {
      _completed = true;
      _busy = false;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      Navigator.of(context).pop(
        InviteAcceptedSetupResult(action: action, profile: _profile),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final tt = context.tt;
    final colors = Theme.of(context).colorScheme;
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    final availableHeight = MediaQuery.sizeOf(context).height - bottomInset;
    final displayName = _profile.displayLabel(l10n.unknownPerson);

    return Semantics(
      identifier: TestIds.inviteAcceptedSetupModal,
      child: TenturaSheetDismissGuard(
        isDirty: _isDirty,
        canDismiss: !_busy,
        discardCopy: _discardCopy(l10n),
        child: AnimatedPadding(
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeOut,
          padding: EdgeInsets.only(bottom: bottomInset),
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: availableHeight * 0.9),
            child: SafeArea(
              top: false,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  GestureDetector(
                    key: TestIds.key(TestIds.inviteAcceptedSetupDragHandle),
                    behavior: HitTestBehavior.opaque,
                    onVerticalDragStart: (_) => _headerDragDistance = 0,
                    onVerticalDragUpdate: (details) {
                      _headerDragDistance += details.delta.dy;
                    },
                    onVerticalDragEnd: (_) {
                      if (_headerDragDistance > kMinInteractiveDimension) {
                        unawaited(_requestClose());
                      }
                      _headerDragDistance = 0;
                    },
                    child: Padding(
                      padding: EdgeInsets.only(
                        left: tt.tightGap,
                        right: tt.tightGap,
                        top: tt.rowGap,
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.drag_handle_outlined,
                            color: tt.textMuted,
                          ),
                          SizedBox(width: tt.tightGap),
                          Expanded(
                            child: Text(
                              l10n.inviteAcceptedSetupTitle,
                              style: TenturaText.title(colors.onSurface),
                            ),
                          ),
                          IconButton(
                            key: TestIds.key(TestIds.inviteAcceptedSetupClose),
                            tooltip: l10n.buttonClose,
                            onPressed: _busy ? null : _requestClose,
                            icon: const Icon(Icons.close_outlined),
                          ),
                        ],
                      ),
                    ),
                  ),
                  Flexible(
                    child: SingleChildScrollView(
                      padding: EdgeInsets.symmetric(
                        horizontal: tt.screenHPadding,
                        vertical: tt.rowGap,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            l10n.inviteSeedPromptQuestion(displayName),
                            style: TenturaText.body(colors.onSurface),
                          ),
                          SizedBox(height: tt.rowGap),
                          CapabilityChipSet(
                            selectedSlugs: _selectedSlugs,
                            maxSelection: _maxSelections,
                            onChanged: (slugs) => setState(() {
                              _selectedSlugs = slugs;
                              _errorMessage = null;
                            }),
                          ),
                          SizedBox(height: tt.rowGap),
                          CheckboxListTile(
                            key: TestIds.key(
                              TestIds.inviteAcceptedSetupChangePrivateName,
                            ),
                            contentPadding: EdgeInsets.zero,
                            controlAffinity: ListTileControlAffinity.leading,
                            title: Text(
                              l10n.inviteAcceptedSetupChangePrivateName,
                            ),
                            value: _editPrivateName,
                            onChanged: _busy
                                ? null
                                : (value) => setState(() {
                                    _editPrivateName = value ?? false;
                                    _errorMessage = null;
                                  }),
                          ),
                          AnimatedSize(
                            duration: const Duration(milliseconds: 150),
                            alignment: Alignment.topCenter,
                            child: !_editPrivateName
                                ? const SizedBox.shrink()
                                : Form(
                                    key: _formKey,
                                    child: TextFormField(
                                      key: TestIds.key(
                                        TestIds.inviteAcceptedSetupPrivateName,
                                      ),
                                      controller: _privateNameController,
                                      enabled: !_busy,
                                      maxLength: kTitleMaxLength,
                                      textInputAction: TextInputAction.done,
                                      decoration: InputDecoration(
                                        labelText: l10n
                                            .inviteAcceptedSetupPrivateNameLabel,
                                        helperText: l10n
                                            .inviteAcceptedSetupPrivateNameHelper,
                                      ),
                                      validator: (value) =>
                                          displayNameValidator(
                                            l10n,
                                            value?.trim(),
                                          ),
                                      onChanged: (_) => setState(
                                        () => _errorMessage = null,
                                      ),
                                      onFieldSubmitted: (_) =>
                                          unawaited(_save()),
                                    ),
                                  ),
                          ),
                          if (_errorMessage case final error?) ...[
                            SizedBox(height: tt.rowGap),
                            Semantics(
                              identifier: TestIds.inviteAcceptedSetupError,
                              liveRegion: true,
                              child: Text(
                                error,
                                style: TenturaText.bodySmall(colors.error),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                  const TenturaHairlineDivider(),
                  Padding(
                    padding: EdgeInsets.fromLTRB(
                      tt.screenHPadding,
                      tt.rowGap,
                      tt.screenHPadding,
                      tt.rowGap,
                    ),
                    child: Row(
                      children: [
                        TextButton(
                          key: TestIds.key(TestIds.inviteAcceptedSetupSkip),
                          onPressed: _busy ? null : _skip,
                          child: Text(l10n.inviteAcceptedSetupSkip),
                        ),
                        const Spacer(),
                        FilledButton(
                          key: TestIds.key(TestIds.inviteAcceptedSetupSave),
                          onPressed: _busy ? null : _save,
                          child: _busy
                              ? SizedBox.square(
                                  dimension: tt.iconSize,
                                  child:
                                      const CircularProgressIndicator.adaptive(
                                        strokeWidth: 2,
                                      ),
                                )
                              : Text(l10n.inviteAcceptedSetupSave),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
