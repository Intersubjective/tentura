import 'package:flutter/material.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/profile/ui/bloc/profile_cubit.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/widget/self_user_highlight.dart';

import 'forward_input_decoration.dart';

/// Single-row personalized note field (same layout as the former panel entries).
class PerRecipientNoteInput extends StatelessWidget {
  const PerRecipientNoteInput({
    required this.profile,
    required this.controller,
    required this.onChanged,
    super.key,
  });

  final Profile profile;
  final TextEditingController controller;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final tt = context.tt;
    return Padding(
      padding: EdgeInsets.symmetric(vertical: tt.rowGap),
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
    );
  }
}
