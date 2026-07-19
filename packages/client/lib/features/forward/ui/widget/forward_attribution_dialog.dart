import 'package:flutter/material.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/features/forward/domain/entity/forward_inbound_source.dart';
import 'package:tentura/ui/l10n/l10n.dart';

/// Skippable first-forward attribution prompt. Returns selected parent edge ids,
/// or `null` when the user skips / is unsure.
Future<List<String>?> showForwardAttributionDialog({
  required BuildContext context,
  required List<ForwardInboundSource> sources,
}) async {
  if (sources.length <= 1) return null;

  final l10n = L10n.of(context)!;

  final suggested = sources.where((s) => s.isSuggestedSource).toList();
  String? selectedEdgeId = suggested.isNotEmpty ? suggested.first.edgeId : null;
  var multiSelect = false;
  final selectedIds = <String>{};

  return showDialog<List<String>?>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) => AlertDialog(
        title: Text(l10n.forwardAttributionTitle),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (!multiSelect)
                ...sources.map(
                  (source) => RadioListTile<String>(
                    value: source.edgeId,
                    groupValue: selectedEdgeId,
                    onChanged: (value) => setState(() => selectedEdgeId = value),
                    title: Text(source.senderName),
                    contentPadding: EdgeInsets.zero,
                  ),
                )
              else
                ...sources.map(
                  (source) => CheckboxListTile(
                    value: selectedIds.contains(source.edgeId),
                    onChanged: (checked) {
                      setState(() {
                        if (checked == true) {
                          selectedIds.add(source.edgeId);
                        } else {
                          selectedIds.remove(source.edgeId);
                        }
                      });
                    },
                    title: Text(source.senderName),
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                  ),
                ),
              TextButton(
                onPressed: () => setState(() {
                  multiSelect = !multiSelect;
                  selectedIds.clear();
                  if (!multiSelect && suggested.isNotEmpty) {
                    selectedEdgeId = suggested.first.edgeId;
                  }
                }),
                child: Text(l10n.forwardAttributionMultiple),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(null),
            child: Text(l10n.forwardAttributionNotSure),
          ),
          FilledButton(
            onPressed: () {
              if (multiSelect) {
                Navigator.of(ctx).pop(
                  selectedIds.isEmpty ? null : selectedIds.toList(),
                );
                return;
              }
              Navigator.of(ctx).pop(
                selectedEdgeId == null ? null : [selectedEdgeId!],
              );
            },
            child: Text(l10n.buttonOk),
          ),
        ],
      ),
    ),
  );
}
