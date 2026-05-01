import 'dart:async';
import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';

import 'package:tentura/domain/port/capability_repository_port.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/utils/ui_utils.dart';

import 'package:tentura/features/capability/ui/widget/capability_chip_set.dart';

/// Bottom-sheet modal to view and edit private labels for [subjectId].
///
/// Opens imperatively — not a separate AutoRoute.
class EditPrivateLabelsDialog extends StatefulWidget {
  const EditPrivateLabelsDialog._({
    required this.subjectId,
    required this.initialSlugs,
  });

  final String subjectId;
  final Set<String> initialSlugs;

  static Future<void> show(
    BuildContext context, {
    required String subjectId,
  }) async {
    final repo = GetIt.I<CapabilityRepositoryPort>();
    final existing = await repo.fetchMyPrivateLabelsForUser(subjectId);
    if (!context.mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => EditPrivateLabelsDialog._(
        subjectId: subjectId,
        initialSlugs: existing.toSet(),
      ),
    );
  }

  @override
  State<EditPrivateLabelsDialog> createState() =>
      _EditPrivateLabelsDialogState();
}

class _EditPrivateLabelsDialogState extends State<EditPrivateLabelsDialog> {
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
      await GetIt.I<CapabilityRepositoryPort>().setPrivateLabels(
        subjectId: widget.subjectId,
        slugs: _selected.toList(),
      );
      if (mounted) Navigator.of(context).pop();
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
                    l10n.capabilityEditPrivateLabels,
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
