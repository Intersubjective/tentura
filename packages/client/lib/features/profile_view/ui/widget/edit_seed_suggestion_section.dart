import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/capability/capability_tag.dart';
import 'package:tentura/domain/capability/invite_seed_prompt_state.dart';
import 'package:tentura/domain/capability/prompt_state_value.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/domain/port/capability_repository_port.dart';
import 'package:tentura/features/capability/ui/widget/capability_chip_set.dart';
import 'package:tentura/ui/l10n/l10n.dart';

enum _LoadPhase { loading, ready, hidden }

/// Inviter-side edit/withdraw for invite seed routing on the invitee's profile.
class EditSeedSuggestionSection extends StatefulWidget {
  const EditSeedSuggestionSection({required this.profile, super.key});

  final Profile profile;

  @override
  State<EditSeedSuggestionSection> createState() =>
      _EditSeedSuggestionSectionState();
}

class _EditSeedSuggestionSectionState extends State<EditSeedSuggestionSection> {
  static const _maxSeedSelections = 3;

  _LoadPhase _phase = _LoadPhase.loading;
  InviteSeedPromptState? _promptState;
  Set<String> _selectedSlugs = {};
  bool _submitting = false;
  bool _withdrawing = false;

  @override
  void initState() {
    super.initState();
    unawaited(_loadPromptState());
  }

  Future<void> _loadPromptState() async {
    try {
      final promptState = await GetIt.I<CapabilityRepositoryPort>()
          .fetchInviteSeedPromptState(widget.profile.id);
      if (!mounted) return;
      final applicable = switch (promptState.state) {
        PromptStateValue.pending => false,
        PromptStateValue.answered => true,
        PromptStateValue.skipped => true,
      };
      setState(() {
        _promptState = promptState;
        _selectedSlugs = {
          for (final slug in promptState.slugs)
            if (CapabilityTag.fromSlug(slug) != null) slug,
        };
        _phase = applicable ? _LoadPhase.ready : _LoadPhase.hidden;
      });
    } on Object {
      if (mounted) setState(() => _phase = _LoadPhase.hidden);
    }
  }

  bool get _showWithdraw => _selectedSlugs.isNotEmpty;

  Future<void> _save() async {
    if (_selectedSlugs.isEmpty || _submitting) return;
    setState(() => _submitting = true);
    try {
      await GetIt.I<CapabilityRepositoryPort>().seedRoutingAttestation(
        subjectId: widget.profile.id,
        slugs: _selectedSlugs.toList(),
      );
      if (!mounted) return;
      setState(() => _submitting = false);
    } on Object {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _withdraw() async {
    if (_submitting || _withdrawing) return;
    setState(() => _withdrawing = true);
    try {
      await GetIt.I<CapabilityRepositoryPort>().seedRoutingAttestation(
        subjectId: widget.profile.id,
        slugs: const [],
      );
      if (!mounted) return;
      setState(() {
        _withdrawing = false;
        _selectedSlugs = {};
      });
    } on Object {
      if (mounted) setState(() => _withdrawing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_phase != _LoadPhase.ready) return const SizedBox.shrink();

    final l10n = L10n.of(context)!;
    final tt = context.tt;
    final colors = Theme.of(context).colorScheme;
    final displayName = widget.profile.displayLabel(l10n.unknownPerson);
    final isAddCopy =
        _promptState?.state == PromptStateValue.skipped &&
        _selectedSlugs.isEmpty;
    final promptCopy = isAddCopy
        ? l10n.profileSeedSuggestionAddPrompt(displayName)
        : l10n.profileSeedSuggestionEditPrompt(displayName);

    return Padding(
      padding: EdgeInsets.only(
        left: tt.screenHPadding,
        right: tt.screenHPadding,
        top: tt.tightGap,
        bottom: tt.cardPadding.bottom,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            promptCopy,
            style: TenturaText.body(colors.onSurface),
          ),
          SizedBox(height: tt.rowGap),
          CapabilityChipSet(
            selectedSlugs: _selectedSlugs,
            maxSelection: _maxSeedSelections,
            onChanged: (slugs) => setState(() => _selectedSlugs = slugs),
          ),
          SizedBox(height: tt.rowGap),
          Wrap(
            spacing: tt.tightGap,
            runSpacing: tt.tightGap,
            children: [
              FilledButton(
                onPressed:
                    _selectedSlugs.isEmpty || _submitting || _withdrawing
                    ? null
                    : _save,
                child: _submitting
                    ? SizedBox.square(
                        dimension: tt.iconSize * 0.75,
                        child: const CircularProgressIndicator.adaptive(
                          strokeWidth: 2,
                        ),
                      )
                    : Text(l10n.profileSeedSuggestionSave),
              ),
              if (_showWithdraw)
                OutlinedButton(
                  onPressed: _submitting || _withdrawing ? null : _withdraw,
                  child: _withdrawing
                      ? SizedBox.square(
                          dimension: tt.iconSize * 0.75,
                          child: const CircularProgressIndicator.adaptive(
                            strokeWidth: 2,
                          ),
                        )
                      : Text(l10n.profileSeedSuggestionWithdraw),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
