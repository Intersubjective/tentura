import 'package:flutter/material.dart';

import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/profile/ui/bloc/profile_cubit.dart';
import 'package:tentura/ui/bloc/screen_cubit.dart';
import 'package:tentura/ui/l10n/l10n.dart';

import '../utils/ui_utils.dart';
import 'self_aware_profile_avatar.dart';
import 'self_user_highlight.dart';

class AuthorInfo extends StatelessWidget {
  const AuthorInfo({
    required this.author,
    super.key,
  });

  final Profile author;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = L10n.of(context)!;
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: () => context.read<ScreenCubit>().showProfile(author.id),
      child: Row(
        children: [
          Padding(
            padding: kPaddingAllS,
            child: SelfAwareAvatar(profile: author),
          ),
          Expanded(
            child: BlocBuilder<ProfileCubit, ProfileState>(
              buildWhen: (p, c) => p.profile.id != c.profile.id,
              builder: (context, state) {
                final isSelf =
                    SelfUserHighlight.profileIsSelf(author, state.profile.id);
                return Text(
                  SelfUserHighlight.displayName(l10n, author, state.profile.id),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: SelfUserHighlight.nameStyle(
                    theme,
                    theme.textTheme.headlineMedium?.copyWith(
                      decoration:
                          isSelf ? null : TextDecoration.underline,
                    ),
                    isSelf,
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
