import 'dart:async';
import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';

import 'package:tentura/domain/capability/person_capability_cues.dart';
import 'package:tentura/domain/port/capability_repository_port.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/utils/ui_utils.dart';

import 'package:tentura/features/capability/ui/widget/capability_chip_set.dart';

/// Bottom-sheet modal for editing the viewer's subjective capability view of
/// [subjectId]. Shows all capability slugs currently visible to the viewer,
/// with automatically-acquired slugs (commit roles, forwards, close-acks)
/// rendered in a secondary color. The viewer may add or remove any slug;
/// removals create tombstone records that suppress the slug only for this viewer.
class EditCapabilitiesDialog extends StatefulWidget {
  const EditCapabilitiesDialog._({
    required this.subjectId,
    required this.initialSlugs,
    required this.automaticSlugs,
    required this.onSaved,
  });

  final String subjectId;
  final Set<String> initialSlugs;
  final Set<String> automaticSlugs;
  final void Function(List<String> slugs, Set<String> automaticSlugs) onSaved;

  static Future<void> show(
    BuildContext context, {
    required String subjectId,
    required List<CapabilityWithSource> currentVisible,
    required void Function(List<String>, Set<String>) onSaved,
  }) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => EditCapabilitiesDialog._(
        subjectId: subjectId,
        initialSlugs: currentVisible.map((c) => c.slug).toSet(),
        automaticSlugs:
            currentVisible.where((c) => !c.hasManualLabel).map((c) => c.slug).toSet(),
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

  @override
  void initState() {
    super.initState();
    _selected = Set.from(widget.initialSlugs);
  }

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
        showSnackBar(context, text: e.toString(), isError: true);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.75,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      builder: (_, scrollController) => Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    l10n.capabilityEditCapabilities,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                FilledButton(
                  onPressed: _saving ? null : _save,
                  child: _saving
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(l10n.buttonSave),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              controller: scrollController,
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
              children: [
                CapabilityChipSet(
                  selectedSlugs: _selected,
                  automaticSlugs: widget.automaticSlugs,
                  onChanged: (s) => setState(() => _selected = s),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
