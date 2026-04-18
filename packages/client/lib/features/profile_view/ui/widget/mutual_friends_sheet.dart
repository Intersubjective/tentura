import 'dart:async' show unawaited;

import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';

import 'package:tentura/consts.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/profile/ui/bloc/profile_cubit.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/utils/profile_presence_line.dart';
import 'package:tentura/ui/widget/self_aware_profile_avatar.dart';
import 'package:tentura/ui/widget/self_user_highlight.dart';

/// Full-height-ish sheet listing mutual friends (same order as mini-avatars).
Future<void> showMutualFriendsSheet(
  BuildContext context,
  List<Profile> profiles,
) async {
  final l10n = L10n.of(context)!;
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    useSafeArea: true,
    builder: (ctx) {
      return DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.6,
        minChildSize: 0.3,
        maxChildSize: 0.95,
        builder: (context, scrollController) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                child: Text(
                  l10n.mutualFriendsTitle,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              Expanded(
                child: ListView.separated(
                  controller: scrollController,
                  padding: const EdgeInsets.only(bottom: 16),
                  itemCount: profiles.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final profile = profiles[index];
                    final presenceText = profilePresenceDisplayLine(
                      l10n: l10n,
                      locale: Localizations.localeOf(context),
                      status: profile.presenceStatus,
                      lastSeenAt: profile.presenceLastSeenAt,
                    );
                    return ListTile(
                      leading: SelfAwareAvatar(profile: profile),
                      title: BlocBuilder<ProfileCubit, ProfileState>(
                        buildWhen: (p, c) => p.profile.id != c.profile.id,
                        builder: (context, state) {
                          return Text(
                            SelfUserHighlight.displayName(
                              l10n,
                              profile,
                              state.profile.id,
                            ),
                            style: SelfUserHighlight.nameStyle(
                              Theme.of(context),
                              Theme.of(context).textTheme.bodyLarge,
                              SelfUserHighlight.profileIsSelf(
                                profile,
                                state.profile.id,
                              ),
                            ),
                          );
                        },
                      ),
                      subtitle: presenceText.isEmpty
                          ? null
                          : Text(
                              presenceText,
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.onSurfaceVariant,
                                  ),
                            ),
                      onTap: () {
                        final router = context.router;
                        final path = '$kPathProfileView/${profile.id}';
                        Navigator.of(context).pop();
                        unawaited(router.pushPath(path));
                      },
                    );
                  },
                ),
              ),
            ],
          );
        },
      );
    },
  );
}
