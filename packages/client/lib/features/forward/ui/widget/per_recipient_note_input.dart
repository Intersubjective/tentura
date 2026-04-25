import 'package:flutter/material.dart';

import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/profile/ui/bloc/profile_cubit.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/utils/ui_utils.dart';
import 'package:tentura/ui/widget/self_aware_profile_avatar.dart';
import 'package:tentura/ui/widget/self_user_highlight.dart';

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
    return Padding(
      padding: kPaddingSmallV,
      child: BlocBuilder<ProfileCubit, ProfileState>(
        buildWhen: (p, c) => p.profile.id != c.profile.id,
        builder: (context, state) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SelfAwareAvatar(
                profile: profile,
                size: 24,
              ),
              const SizedBox(width: kSpacingSmall),
              Expanded(
                child: TextField(
                  controller: controller,
                  onChanged: onChanged,
                  decoration: InputDecoration(
                    hintText: l10n.forwardRecipientNoteHint(
                      SelfUserHighlight.displayName(
                        l10n,
                        profile,
                        state.profile.id,
                      ),
                    ),
                    border: const OutlineInputBorder(),
                    isDense: true,
                  ),
                  maxLines: 2,
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
