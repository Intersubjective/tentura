import 'package:flutter/material.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/utils/ui_utils.dart';

import '../bloc/forward_cubit.dart';
import 'forward_recipient_row.dart';
import 'per_recipient_note_input.dart';

/// Full-screen recipient search (query ignores active scope tab; MR-sorted).
class ForwardSearchOverlay extends StatefulWidget {
  const ForwardSearchOverlay({
    required this.onClose,
    required this.recipientNoteControllers,
    required this.onRecipientNoteChanged,
    required this.personalizedNoteEditorOpenIds,
    required this.onTogglePersonalizedNoteEditor,
    super.key,
  });

  final VoidCallback onClose;
  final Map<String, TextEditingController> recipientNoteControllers;
  final void Function(String userId, String text) onRecipientNoteChanged;
  final Set<String> personalizedNoteEditorOpenIds;
  final void Function(String userId) onTogglePersonalizedNoteEditor;

  @override
  State<ForwardSearchOverlay> createState() => _ForwardSearchOverlayState();
}

class _ForwardSearchOverlayState extends State<ForwardSearchOverlay> {
  final _controller = TextEditingController();
  final _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _controller.addListener(() => setState(() {}));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focus.requestFocus();
    });
  }

  @override
  void dispose() {
    _focus.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tt = context.tt;
    final l10n = L10n.of(context)!;
    final mat = MaterialLocalizations.of(context);

    return Material(
      color: tt.bg,
      child: SafeArea(
        child: BlocBuilder<ForwardCubit, ForwardState>(
          builder: (context, state) {
            final filtered = ForwardState.filterCandidatesByQuery(
              state.candidates,
              _controller.text,
            );

            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: EdgeInsets.only(left: 4, right: tt.screenHPadding),
                  child: SizedBox(
                    height: 48,
                    child: Row(
                      children: [
                        IconButton(
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(
                            minWidth: 44,
                            minHeight: 44,
                          ),
                          icon: Icon(Icons.arrow_back, size: 22, color: tt.text),
                          tooltip: mat.backButtonTooltip,
                          onPressed: widget.onClose,
                        ),
                        Icon(Icons.search, size: 20, color: tt.textMuted),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextField(
                            controller: _controller,
                            focusNode: _focus,
                            style: TenturaText.body(tt.text),
                            decoration: InputDecoration.collapsed(
                              hintText: l10n.forwardOverlaySearchHint,
                              hintStyle: TenturaText.bodySmall(tt.textFaint),
                            ),
                          ),
                        ),
                        if (_controller.text.isNotEmpty)
                          IconButton(
                            icon: Icon(Icons.clear, size: 20, color: tt.textMuted),
                            tooltip: mat.cancelButtonLabel,
                            onPressed: _controller.clear,
                          ),
                      ],
                    ),
                  ),
                ),
                const TenturaHairlineDivider(),
                Expanded(
                  child: filtered.isEmpty
                      ? Center(
                          child: Padding(
                            padding: kPaddingH,
                            child: Text(
                              l10n.labelNothingHere,
                              textAlign: TextAlign.center,
                              style: TenturaText.bodySmall(tt.textMuted),
                            ),
                          ),
                        )
                      : ListView(
                          padding: const EdgeInsets.only(bottom: 8),
                          children: [
                            for (var i = 0; i < filtered.length; i++) ...[
                              if (i > 0) const TenturaHairlineDivider(),
                              ForwardRecipientRow(
                                candidate: filtered[i],
                                isSelected: state.selectedIds
                                    .contains(filtered[i].id),
                                onToggle: () => context
                                    .read<ForwardCubit>()
                                    .toggleSelection(filtered[i].id),
                                personalizedNoteEditorOpen: widget
                                    .personalizedNoteEditorOpenIds
                                    .contains(filtered[i].id),
                                onTogglePersonalizedNoteEditor: () => widget
                                    .onTogglePersonalizedNoteEditor(
                                  filtered[i].id,
                                ),
                              ),
                              if (state.selectedIds
                                      .contains(filtered[i].id) &&
                                  widget.personalizedNoteEditorOpenIds
                                      .contains(filtered[i].id))
                                Padding(
                                  padding: EdgeInsets.symmetric(
                                    horizontal: tt.screenHPadding,
                                  ),
                                  child: PerRecipientNoteInput(
                                    profile: filtered[i].profile,
                                    controller: widget.recipientNoteControllers[
                                        filtered[i].id]!,
                                    onChanged: (t) => widget
                                        .onRecipientNoteChanged(
                                      filtered[i].id,
                                      t,
                                    ),
                                  ),
                                ),
                            ],
                          ],
                        ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
