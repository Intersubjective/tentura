import 'package:flutter/material.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/utils/ui_utils.dart';

import '../bloc/forward_cubit.dart';
import '../../domain/entity/forward_candidate.dart';
import '../model/forward_recipient_row_host.dart';
import 'forward_recipient_row.dart';
import 'per_recipient_note_input.dart';

/// Full-screen recipient search scoped to the active tab (MR-sorted).
class ForwardSearchOverlay extends StatefulWidget {
  const ForwardSearchOverlay({
    required this.onClose,
    required this.recipientNoteControllers,
    required this.onRecipientNoteChanged,
    super.key,
  });

  final VoidCallback onClose;
  final Map<String, TextEditingController> recipientNoteControllers;
  final void Function(String userId, String text) onRecipientNoteChanged;

  @override
  State<ForwardSearchOverlay> createState() => _ForwardSearchOverlayState();
}

class _ForwardSearchOverlayState extends State<ForwardSearchOverlay> {
  final _controller = TextEditingController();
  final _focus = FocusNode();
  String? _focusedCandidateId;

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

  void _focusCandidate(String id) {
    if (_focusedCandidateId == id) return;
    setState(() => _focusedCandidateId = id);
  }

  void _syncFocusedCandidate(List<ForwardCandidate> filtered) {
    final nextFocus = filtered.isEmpty
        ? null
        : filtered.any((c) => c.id == _focusedCandidateId)
        ? _focusedCandidateId
        : filtered.first.id;
    if (_focusedCandidateId == nextFocus) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() => _focusedCandidateId = nextFocus);
    });
  }

  Widget _buildSearchHeader({
    required TenturaTokens tt,
    required L10n l10n,
    required MaterialLocalizations mat,
  }) {
    return Padding(
      padding: EdgeInsets.only(
        left: tt.tightGap * 2,
        right: tt.screenHPadding,
      ),
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
            SizedBox(width: tt.iconTextGap),
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
    );
  }

  Widget _buildCandidateList({
    required BuildContext context,
    required ForwardState state,
    required List<ForwardCandidate> filtered,
    required TenturaTokens tt,
    required L10n l10n,
    required bool showInlineNotes,
    void Function(String id)? onCandidateFocused,
  }) {
    if (filtered.isEmpty) {
      return Center(
        child: Padding(
          padding: kPaddingH,
          child: Text(
            l10n.labelNothingHere,
            textAlign: TextAlign.center,
            style: TenturaText.bodySmall(tt.textMuted),
          ),
        ),
      );
    }

    final cubit = context.read<ForwardCubit>();

    return ListView(
      padding: EdgeInsets.only(bottom: tt.rowGap / 2),
      children: [
        for (var i = 0; i < filtered.length; i++) ...[
          if (i > 0) const TenturaHairlineDivider(),
          Material(
            color:
                onCandidateFocused != null &&
                    _focusedCandidateId == filtered[i].id
                ? Theme.of(context).colorScheme.surfaceContainerHighest
                : Colors.transparent,
            child: InkWell(
              onTap: onCandidateFocused == null
                  ? null
                  : () => onCandidateFocused(filtered[i].id),
              child: ForwardRecipientRow(
                host: ForwardRecipientRowHost.pickerSearch,
                candidate: filtered[i],
                requiredCapabilitySlugs: state.beacon?.needs ?? const {},
                isSelected: state.selectedIds.contains(filtered[i].id),
                onToggle: () {
                  onCandidateFocused?.call(filtered[i].id);
                  cubit.toggleSelection(filtered[i].id);
                },
                isPersonalNoteSkipped: state.skippedPersonalNoteIds.contains(
                  filtered[i].id,
                ),
                onSkipPersonalNote: () =>
                    cubit.skipPersonalNote(filtered[i].id),
                onRestorePersonalNote: () =>
                    cubit.restorePersonalNote(filtered[i].id),
              ),
            ),
          ),
          if (showInlineNotes &&
              state.selectedIds.contains(filtered[i].id) &&
              !state.skippedPersonalNoteIds.contains(filtered[i].id))
            Padding(
              padding: EdgeInsets.symmetric(horizontal: tt.screenHPadding),
              child: PerRecipientNoteInput(
                profile: filtered[i].profile,
                controller: widget.recipientNoteControllers[filtered[i].id]!,
                onChanged: (t) =>
                    widget.onRecipientNoteChanged(filtered[i].id, t),
              ),
            ),
        ],
      ],
    );
  }

  Widget _buildDetailPane({
    required ForwardState state,
    required List<ForwardCandidate> filtered,
    required TenturaTokens tt,
    required L10n l10n,
  }) {
    final focusedId = _focusedCandidateId;
    if (focusedId == null) {
      return Center(
        child: Padding(
          padding: kPaddingH,
          child: Text(
            l10n.selectRecipients,
            textAlign: TextAlign.center,
            style: TenturaText.bodySmall(tt.textMuted),
          ),
        ),
      );
    }

    final candidateIndex = filtered.indexWhere((c) => c.id == focusedId);
    if (candidateIndex < 0) {
      return Center(
        child: Padding(
          padding: kPaddingH,
          child: Text(
            l10n.labelNothingHere,
            textAlign: TextAlign.center,
            style: TenturaText.bodySmall(tt.textMuted),
          ),
        ),
      );
    }

    final candidate = filtered[candidateIndex];
    final isSelected = state.selectedIds.contains(candidate.id);
    final isSkipped = state.skippedPersonalNoteIds.contains(candidate.id);
    final cubit = context.read<ForwardCubit>();

    return SingleChildScrollView(
      padding: EdgeInsets.all(tt.screenHPadding),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ForwardRecipientRow(
            host: ForwardRecipientRowHost.pickerSearch,
            candidate: candidate,
            requiredCapabilitySlugs: state.beacon?.needs ?? const {},
            isSelected: isSelected,
            onToggle: () => cubit.toggleSelection(candidate.id),
            isPersonalNoteSkipped: isSkipped,
            onSkipPersonalNote: () => cubit.skipPersonalNote(candidate.id),
            onRestorePersonalNote: () =>
                cubit.restorePersonalNote(candidate.id),
          ),
          if (isSelected && !isSkipped) ...[
            SizedBox(height: tt.rowGap),
            PerRecipientNoteInput(
              profile: candidate.profile,
              controller: widget.recipientNoteControllers[candidate.id]!,
              onChanged: (t) => widget.onRecipientNoteChanged(candidate.id, t),
            ),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tt = context.tt;
    final l10n = L10n.of(context)!;
    final mat = MaterialLocalizations.of(context);

    return Material(
      color: tt.bg,
      child: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final windowClass = windowClassForWidth(constraints.maxWidth);
            final useSplit = windowClass != WindowClass.compact;
            final masterWidth = useSplit
                ? (constraints.maxWidth * 0.4).clamp(320.0, 420.0)
                : constraints.maxWidth;

            return BlocBuilder<ForwardCubit, ForwardState>(
              builder: (context, state) {
                final filtered = ForwardState.filterCandidatesByQuery(
                  state.visibleRecipients,
                  _controller.text,
                );
                if (useSplit) {
                  _syncFocusedCandidate(filtered);
                }

                if (!useSplit) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _buildSearchHeader(tt: tt, l10n: l10n, mat: mat),
                      const TenturaHairlineDivider(),
                      Expanded(
                        child: _buildCandidateList(
                          context: context,
                          state: state,
                          filtered: filtered,
                          tt: tt,
                          l10n: l10n,
                          showInlineNotes: true,
                        ),
                      ),
                    ],
                  );
                }

                return Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(
                      width: masterWidth,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _buildSearchHeader(tt: tt, l10n: l10n, mat: mat),
                          const TenturaHairlineDivider(),
                          Expanded(
                            child: _buildCandidateList(
                              context: context,
                              state: state,
                              filtered: filtered,
                              tt: tt,
                              l10n: l10n,
                              showInlineNotes: false,
                              onCandidateFocused: _focusCandidate,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const VerticalDivider(width: 1),
                    Expanded(
                      child: _buildDetailPane(
                        state: state,
                        filtered: filtered,
                        tt: tt,
                        l10n: l10n,
                      ),
                    ),
                  ],
                );
              },
            );
          },
        ),
      ),
    );
  }
}
