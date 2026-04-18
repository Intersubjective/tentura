import 'package:flutter/material.dart';

import 'package:tentura/consts.dart';
import 'package:tentura/features/profile/ui/bloc/profile_cubit.dart';
import 'package:tentura/ui/dialog/show_seed_dialog.dart';
import 'package:tentura/ui/dialog/share_code_dialog.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/widget/self_aware_profile_avatar.dart';
import 'package:tentura/ui/widget/self_user_highlight.dart';

import '../../domain/entity/account_entity.dart';
import '../../domain/use_case/account_case.dart';
import '../bloc/auth_cubit.dart';
import '../dialog/account_remove_dialog.dart';

class AccountListTile extends StatelessWidget {
  const AccountListTile({
    required this.account,
    super.key,
  });

  final AccountEntity account;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final profile = AccountCase.fromAccountEntity(account);
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: SelfAwareAvatar.small(
        profile: profile,
        withRating: false,
      ),
      title: BlocBuilder<ProfileCubit, ProfileState>(
        buildWhen: (p, c) => p.profile.id != c.profile.id,
        builder: (context, state) {
          return Text(
            SelfUserHighlight.displayName(l10n, profile, state.profile.id),
            style: SelfUserHighlight.nameStyle(
              Theme.of(context),
              Theme.of(context).textTheme.bodyLarge,
              SelfUserHighlight.profileIsSelf(profile, state.profile.id),
            ),
          );
        },
      ),
      trailing: PopupMenuButton(
        itemBuilder: (context) => <PopupMenuEntry<void>>[
          //
          // Share account code
          PopupMenuItem<void>(
            child: Text(l10n.shareAccount),
            onTap: () => ShareCodeDialog.show(
              context,
              header: account.id,
              link: Uri.parse(kServerName).replace(
                path: kPathAppLinkView,
                queryParameters: {'id': account.id},
              ),
            ),
          ),
          const PopupMenuDivider(),

          // Share account seed
          PopupMenuItem<void>(
            child: Text(l10n.showSeed),
            onTap: () async {
              final seed = await GetIt.I<AuthCubit>().getSeedByAccountId(
                account.id,
              );
              if (context.mounted) {
                await ShowSeedDialog.show(context, seed: seed);
              }
            },
          ),
          const PopupMenuDivider(),

          // Remove account
          PopupMenuItem<void>(
            child: Text(l10n.removeFromList),
            onTap: () => AccountRemoveDialog.show(context, id: account.id),
          ),
        ],
      ),

      // Log in
      onTap: () => GetIt.I<AuthCubit>().signIn(account.id),
    );
  }
}
