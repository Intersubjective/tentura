import 'package:flutter/material.dart';

import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/profile/ui/bloc/profile_cubit.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/widget/self_aware_profile_avatar.dart';
import 'package:tentura/ui/widget/self_user_highlight.dart';

/// Author row under beacon title (inbox / My Work cards): small avatar + name.
class BeaconCardAuthorSubline extends StatelessWidget {
  const BeaconCardAuthorSubline({
    required this.author,
    this.avatarSize = 22,
    this.trailing,
    super.key,
  });

  final Profile author;
  final double avatarSize;

  /// Placed immediately after the display name (e.g. deadline pill on inbox cards).
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final l10n = L10n.of(context)!;
    return BlocBuilder<ProfileCubit, ProfileState>(
      buildWhen: (p, c) => p.profile.id != c.profile.id,
      builder: (context, state) {
        final isSelf = SelfUserHighlight.profileIsSelf(author, state.profile.id);
        final name = SelfUserHighlight.displayName(l10n, author, state.profile.id);
        final nameStyle = SelfUserHighlight.nameStyle(
          theme,
          theme.textTheme.labelSmall?.copyWith(
            color: scheme.onSurfaceVariant,
          ),
          isSelf,
        );
        final tail = trailing;
        return Row(
          children: [
            SelfAwareAvatar(
              profile: author,
              size: avatarSize,
              withRating: false,
            ),
            const SizedBox(width: 6),
            Expanded(
              child: tail == null
                  ? Text(
                      name,
                      style: nameStyle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    )
                  : Row(
                      children: [
                        Flexible(
                          child: Text(
                            name,
                            style: nameStyle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 6),
                        tail,
                      ],
                    ),
            ),
          ],
        );
      },
    );
  }
}
