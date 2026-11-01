import 'package:flutter/material.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/features/forward/domain/entity/forward_candidate.dart';
import 'package:tentura/features/forward/domain/forward_target_profile.dart';

import '../bloc/forward_cubit.dart';
import '../model/forward_recipient_row_host.dart';
import 'forward_recipient_personal_note_slot.dart';
import 'forward_recipient_row.dart';
import 'per_recipient_note_input.dart';

/// One forward picker row: selection and note preview scoped with [BlocSelector].
///
/// Rebuild scope for #807: toggling a recipient rebuilds only this entry.
class ForwardRecipientPickerEntry extends StatelessWidget {
  const ForwardRecipientPickerEntry({
    required this.candidate,
    required this.host,
    required this.beacon,
    required this.profile,
    required this.viewerIsAuthor,
    required this.expandedPersonalNoteRecipientId,
    required this.onToggle,
    required this.onOpenDetails,
    required this.onEditReasons,
    required this.onEditForward,
    required this.onCancelForward,
    required this.onOpenPersonalNote,
    required this.onPersonalNoteCollapsed,
    required this.recipientNoteController,
    required this.onRecipientNoteChanged,
    this.recipientNoteHint,
    this.onBuild,
    super.key,
  });

  final ForwardCandidate candidate;
  final ForwardRecipientRowHost host;
  final Beacon? beacon;
  final ForwardTargetProfile profile;
  final bool viewerIsAuthor;
  final ValueNotifier<String?> expandedPersonalNoteRecipientId;
  final VoidCallback onToggle;
  final VoidCallback? onOpenDetails;
  final VoidCallback? onEditReasons;
  final VoidCallback? onEditForward;
  final VoidCallback? onCancelForward;
  final VoidCallback? onOpenPersonalNote;
  final VoidCallback onPersonalNoteCollapsed;
  final TextEditingController? recipientNoteController;
  final void Function(String text) onRecipientNoteChanged;
  final String? recipientNoteHint;

  /// Test hook: called on every row build.
  final VoidCallback? onBuild;

  @override
  Widget build(BuildContext context) {
    final id = candidate.id;
    final showsNotes = profile.showsPersonalNotes;

    return BlocSelector<ForwardCubit, ForwardState, _ForwardPickerRowView>(
      selector: (state) => _ForwardPickerRowView(
        isSelected: state.selectedIds.contains(id),
        reasonSlugs: profile.showsReasons
            ? state.recipientReasons[id] ?? const []
            : const [],
        personalNotePreview: state.perRecipientNotes[id],
      ),
      builder: (context, view) {
        onBuild?.call();
        Widget row({required bool isPersonalNoteExpanded}) =>
            ForwardRecipientRow(
              host: host,
              isPost: profile == ForwardTargetProfile.post,
              viewerIsAuthor: viewerIsAuthor,
              candidate: candidate,
              requiredCapabilitySlugs: beacon?.needs ?? const {},
              isSelected: view.isSelected,
              onToggle: onToggle,
              onOpenDetails: onOpenDetails,
              reasonSlugs: view.reasonSlugs,
              onEditReasons: onEditReasons,
              onEditForward: onEditForward,
              onCancelForward: onCancelForward,
              showsPersonalNoteSlot: showsNotes,
              personalNotePreview: view.personalNotePreview,
              isPersonalNoteExpanded: isPersonalNoteExpanded,
              onOpenPersonalNote: showsNotes && view.isSelected
                  ? onOpenPersonalNote
                  : null,
            );

        if (!showsNotes || !view.isSelected) {
          return row(isPersonalNoteExpanded: false);
        }

        return ListenableBuilder(
          listenable: expandedPersonalNoteRecipientId,
          builder: (context, _) {
            final expandedId = expandedPersonalNoteRecipientId.value;
            if (expandedId != id) {
              return row(isPersonalNoteExpanded: false);
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                row(isPersonalNoteExpanded: true),
                if (recipientNoteController != null)
                  Padding(
                    padding: EdgeInsets.symmetric(
                      horizontal: context.tt.screenHPadding,
                    ),
                    child: ForwardRecipientExpandedPersonalNote(
                      onCollapsed: onPersonalNoteCollapsed,
                      child: PerRecipientNoteInput(
                        profile: candidate.profile,
                        controller: recipientNoteController!,
                        onChanged: onRecipientNoteChanged,
                        hintText: recipientNoteHint,
                      ),
                    ),
                  ),
              ],
            );
          },
        );
      },
    );
  }
}

@immutable
class _ForwardPickerRowView {
  const _ForwardPickerRowView({
    required this.isSelected,
    required this.reasonSlugs,
    required this.personalNotePreview,
  });

  final bool isSelected;
  final List<String> reasonSlugs;
  final String? personalNotePreview;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is _ForwardPickerRowView &&
          isSelected == other.isSelected &&
          _listEq(reasonSlugs, other.reasonSlugs) &&
          personalNotePreview == other.personalNotePreview;

  @override
  int get hashCode => Object.hash(
    isSelected,
    Object.hashAll(reasonSlugs),
    personalNotePreview,
  );

  static bool _listEq(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
