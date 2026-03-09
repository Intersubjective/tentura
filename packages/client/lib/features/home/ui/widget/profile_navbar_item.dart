import 'dart:async';
import 'package:flutter/material.dart';

import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/ui/widget/avatar_rated.dart';
import 'package:tentura/ui/utils/ui_utils.dart';

import 'package:tentura/features/auth/domain/use_case/account_case.dart';
import 'package:tentura/features/auth/ui/bloc/auth_cubit.dart';
import 'package:tentura/features/profile/ui/bloc/profile_cubit.dart';

class ProfileNavBarItem extends StatelessWidget {
  const ProfileNavBarItem({super.key});

  @override
  Widget build(BuildContext context) {
    final authCubit = GetIt.I<AuthCubit>();
    return BlocBuilder<AuthCubit, AuthState>(
      bloc: authCubit,
      builder: (context, state) {
        final menuController = MenuController();
        return MenuAnchor(
          controller: menuController,
          menuChildren: [
            for (final account in authCubit.state.accounts)
              _AccountMenuItem(
                key: ValueKey(account),
                isMe: account.id == state.currentAccountId,
                profile: AccountCase.fromAccountEntity(account),
                onTap: () {
                  menuController.close();
                  unawaited(authCubit.signIn(account.id));
                },
              ),
          ],
          child: GestureDetector(
            key: Key('ProfileNavbarItem:${state.currentAccount}'),
            onLongPress: state.accounts.length > 1 ? menuController.open : null,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: BlocBuilder<ProfileCubit, ProfileState>(
                bloc: GetIt.I<ProfileCubit>(),
                buildWhen: (p, c) =>
                    p.profile.hasAvatar != c.profile.hasAvatar ||
                    p.profile.image?.blurHash != c.profile.image?.blurHash,
                builder: (context, state) {
                  return AvatarRated(
                    profile: state.profile,
                    withRating: false,
                    size: 36,
                  );
                },
              ),
            ),
          ),
        );
      },
    );
  }
}

class _AccountMenuItem extends StatelessWidget {
  const _AccountMenuItem({
    required this.profile,
    required this.isMe,
    this.onTap,
    super.key,
  });

  final bool isMe;
  final Profile profile;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Row(
      children: [
        Padding(
          padding: kPaddingAllS,
          child: AvatarRated.small(
            profile: profile,
            withRating: false,
          ),
        ),
        Padding(
          padding: kPaddingAllS,
          child: Text(
            profile.title,
            maxLines: 1,
            softWrap: false,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        if (isMe)
          const Padding(
            padding: kPaddingAllS,
            child: Icon(Icons.check),
          ),
      ],
    ),
  );
}
