import 'dart:async';
import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/capability/person_capability_cues.dart';
import 'package:tentura/domain/port/capability_repository_port.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/utils/ui_utils.dart';

import 'package:tentura/features/capability/ui/widget/capability_chip_set.dart';
import 'package:tentura/features/capability/ui/widget/capability_search_field.dart';

/// Bottom-sheet modal for editing the viewer's private, subjective capability
/// view of [subjectId]. Shows all capability slugs currently visible to the viewer,
/// with automatically-acquired slugs (help offer roles, forwards, close-acks)
/// rendered in a secondary color. The viewer may add or remove any slug;
/// removals create tombstone records that suppress the slug only for this viewer.
class EditCapabilitiesDialog extends StatefulWidget {
  const EditCapabilitiesDialog._({
    required this.subjectId,
    required this.subjectName,
    required this.initialSlugs,
    required this.automaticSlugs,
    required this.onSaved,
  });

  final String subjectId;
  final String subjectName;
  final Set<String> initialSlugs;
  final Set<String> automaticSlugs;
  final void Function(List<String> slugs, Set<String> automaticSlugs) onSaved;

  static Future<void> show(
    BuildContext context, {
    required String subjectId,
    required String subjectName,
    required List<CapabilityWithSource> currentVisible,
    required void Function(List<String>, Set<String>) onSaved,
  }) async {
    await showTenturaAdaptiveSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: false,
      builder: (_) => EditCapabilitiesDialog._(
        subjectId: subjectId,
        subjectName: subjectName,
        initialSlugs: currentVisible.map((c) => c.slug).toSet(),
        automaticSlugs: currentVisible
            .where((c) => !c.hasManualLabel)
            .map((c) => c.slug)
            .toSet(),
        onSaved: onSaved,
      ),
    );
  }

  @override
  State<EditCapabilitiesDialog> createState() => _EditCapabilitiesDialogState();
}

class _EditCapabilitiesDialogState extends State<EditCapabilitiesDialog> {
  late Set<String> _selected;
  bool _saving = false;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _selected = Set.from(widget.initialSlugs);
  }

  bool get _isDirty =>
      _selected.length != widget.initialSlugs.length ||
      !_selected.containsAll(widget.initialSlugs);

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await GetIt.I<CapabilityRepositoryPort>().setViewerVisible(
        subjectId: widget.subjectId,
        slugs: _selected.toList(),
      );
      if (mounted) {
        widget.onSaved(_selected.toList(), widget.automaticSlugs);
        unawaited(
          Future.delayed(Duration.zero, () {
            if (mounted) Navigator.of(context).pop();
          }),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        showSnackBar(context, text: e.toString(), isError: true, error: e);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final theme = Theme.of(context);
    return TenturaSheetDismissGuard(
      isDirty: _isDirty,
      child: DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.75,
        minChildSize: 0.4,
        maxChildSize: 0.95,
        builder: (_, scrollController) {
          final tt = context.tt;
          return ListView(
            controller: scrollController,
            padding: EdgeInsets.fromLTRB(
              tt.screenHPadding,
              tt.sectionGap,
              tt.screenHPadding,
              tt.sectionGap * 2,
            ),
            children: [
              Text(
                l10n.profileYourTagsFor(widget.subjectName),
                style: theme.textTheme.titleMedium,
              ),
              SizedBox(height: tt.tightGap),
              Text(
                l10n.capabilityTagsDisclosure(widget.subjectName),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              SizedBox(height: tt.rowGap),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton(
                  onPressed: _saving ? null : _save,
                  child: _saving
                      ? SizedBox.square(
                          dimension: tt.iconSize,
                          child: const TenturaCircularProgress(strokeWidth: 2),
                        )
                      : Text(l10n.buttonSave),
                ),
              ),
              SizedBox(height: tt.sectionGap),
              CapabilitySearchField(
                onChanged: (q) => setState(() => _query = q),
              ),
              SizedBox(height: tt.rowGap),
              CapabilityChipSet(
                selectedSlugs: _selected,
                automaticSlugs: widget.automaticSlugs,
                query: _query,
                onChanged: (s) => setState(() => _selected = s),
              ),
            ],
          );
        },
      ),
    );
  }
}
