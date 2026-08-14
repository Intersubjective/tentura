import 'package:flutter/material.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/profile/ui/bloc/profile_cubit.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/widget/self_user_highlight.dart';

import 'forward_input_decoration.dart';

/// Single-row personalized note field with optional explicit skip / restore.
class PerRecipientNoteInput extends StatelessWidget {
  const PerRecipientNoteInput({
    required this.profile,
    required this.controller,
    required this.onChanged,
    this.isSkipped = false,
    this.onSkip,
    this.onRestore,
    super.key,
  });

  final Profile profile;
  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final bool isSkipped;
  final VoidCallback? onSkip;
  final VoidCallback? onRestore;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final tt = context.tt;

    if (isSkipped) {
      return Padding(
        padding: EdgeInsets.symmetric(vertical: tt.rowGap),
        child: Align(
          alignment: Alignment.centerLeft,
          child: IconButton(
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(
              minWidth: 44,
              minHeight: 44,
            ),
            tooltip: l10n.forwardRestorePersonalNote,
            onPressed: onRestore,
            icon: Icon(
              Icons.add_comment_outlined,
              size: tt.iconSize,
              color: tt.textMuted,
            ),
          ),
        ),
      );
    }

    return Padding(
      padding: EdgeInsets.symmetric(vertical: tt.rowGap),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: BlocBuilder<ProfileCubit, ProfileState>(
              buildWhen: (p, c) => p.profile.id != c.profile.id,
              builder: (context, state) {
                return TextField(
                  controller: controller,
                  onChanged: onChanged,
                  style: TenturaText.body(tt.text),
                  cursorColor: tt.info,
                  decoration: forwardNoteInputDecoration(
                    context,
                    hintText: l10n.forwardRecipientNoteHint(
                      SelfUserHighlight.displayName(
                        l10n,
                        profile,
                        state.profile.id,
                      ),
                    ),
                  ),
                  maxLines: 2,
                );
              },
            ),
          ),
          if (onSkip != null) ...[
            SizedBox(width: tt.iconTextGap),
            IconButton(
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(
                minWidth: 44,
                minHeight: 44,
              ),
              tooltip: l10n.forwardSkipPersonalNote,
              onPressed: onSkip,
              icon: Icon(
                Icons.do_not_disturb_on_outlined,
                size: tt.iconSize,
                color: tt.textMuted,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
