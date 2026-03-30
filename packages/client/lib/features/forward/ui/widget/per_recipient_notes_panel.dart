import 'package:flutter/material.dart';

import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/utils/ui_utils.dart';
import 'package:tentura/ui/widget/avatar_rated.dart';

class PerRecipientNotesPanel extends StatefulWidget {
  const PerRecipientNotesPanel({
    required this.selectedIds,
    required this.profilesById,
    required this.notes,
    required this.onNoteChanged,
    super.key,
  });

  final Set<String> selectedIds;
  final Map<String, Profile> profilesById;
  final Map<String, String> notes;
  final void Function(String userId, String text) onNoteChanged;

  @override
  State<PerRecipientNotesPanel> createState() => _PerRecipientNotesPanelState();
}

class _PerRecipientNotesPanelState extends State<PerRecipientNotesPanel> {
  bool _expanded = false;
  final _controllers = <String, TextEditingController>{};

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  void _syncControllers() {
    final ids = widget.selectedIds;
    for (final id in _controllers.keys.toList()) {
      if (!ids.contains(id)) {
        _controllers.remove(id)?.dispose();
      }
    }
    for (final id in ids) {
      _controllers.putIfAbsent(
        id,
        () => TextEditingController(text: widget.notes[id] ?? ''),
      );
    }
  }

  @override
  void didUpdateWidget(covariant PerRecipientNotesPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncControllers();
  }

  @override
  void initState() {
    super.initState();
    _syncControllers();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final count = widget.selectedIds.length;
    if (count == 0) {
      return const SizedBox.shrink();
    }
    _syncControllers();
    final sortedIds = widget.selectedIds.toList()..sort();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        TextButton(
          onPressed: () => setState(() => _expanded = !_expanded),
          child: Text(
            _expanded
                ? l10n.forwardHidePersonalizedNotes
                : l10n.forwardPersonalizeNotes(count),
          ),
        ),
        if (_expanded)
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 200),
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: sortedIds.length,
              itemBuilder: (_, i) {
                final id = sortedIds[i];
                final profile = widget.profilesById[id];
                final controller = _controllers[id];
                if (profile == null || controller == null) {
                  return const SizedBox.shrink();
                }
                return Padding(
                  padding: kPaddingSmallV,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      AvatarRated(
                        profile: profile,
                        size: 24,
                      ),
                      const SizedBox(width: kSpacingSmall),
                      Expanded(
                        child: TextField(
                          controller: controller,
                          onChanged: (t) => widget.onNoteChanged(id, t),
                          decoration: InputDecoration(
                            hintText: l10n.forwardRecipientNoteHint(
                              profile.title,
                            ),
                            border: const OutlineInputBorder(),
                            isDense: true,
                          ),
                          maxLines: 2,
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
      ],
    );
  }
}
