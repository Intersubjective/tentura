import 'package:flutter/material.dart';
import 'package:auto_route/auto_route.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/ui/bloc/screen_cubit.dart';
import 'package:tentura/ui/dialog/qr_scan_dialog.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/utils/ui_utils.dart';

import '../bloc/auth_cubit.dart';
import '../widget/account_list_tile.dart';

@RoutePage()
class AuthLoginScreen extends StatelessWidget implements AutoRouteWrapper {
  const AuthLoginScreen({super.key});

  @override
  Widget wrappedRoute(BuildContext context) => this;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final authCubit = GetIt.I<AuthCubit>();
    return BlocBuilder<AuthCubit, AuthState>(
      bloc: authCubit,
      buildWhen: (_, c) => c.isSuccess,
      builder: (context, state) {
        final tt = context.tt;
        return Scaffold(
          appBar: TenturaTopBar.of(
            context,
            centerTitle: true,
            title: Text(l10n.chooseAccount),
            progress: BlocSelector<AuthCubit, AuthState, bool>(
              key: Key('Loader:${authCubit.hashCode}'),
              selector: (state) => state.isLoading,
              builder: TenturaTopBar.loadingBar,
              bloc: authCubit,
            ),
          ),
          body: SafeArea(
            child: TenturaContentColumn(
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: tt.screenHPadding),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      child: state.accounts.isEmpty
                          ? Padding(
                              padding: tt.cardPadding,
                              child: Center(
                                child: Text(
                                  l10n.alreadyHaveAccount,
                                  textAlign: TextAlign.center,
                                  style: TenturaText.bodyMedium(
                                    Theme.of(
                                      context,
                                    ).colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ),
                            )
                          : ListView.separated(
                              itemCount: state.accounts.length,
                              itemBuilder: (_, i) {
                                final account = state.accounts[i];
                                return AccountListTile(
                                  key: ValueKey(account),
                                  account: account,
                                );
                              },
                              separatorBuilder: separatorBuilder,
                            ),
                    ),

                    // Recover from seed (QR)
                    Padding(
                      padding: tt.cardPadding,
                      child: OutlinedButton(
                        onPressed: () async => authCubit.addAccount(
                          await QRScanDialog.show(context),
                        ),
                        child: Text(l10n.recoverFromQR),
                      ),
                    ),

                    // Recover from seed (clipboard)
                    Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: tt.screenHPadding,
                      ),
                      child: OutlinedButton(
                        onPressed: authCubit.getSeedFromClipboard,
                        child: Text(l10n.recoverFromClipboard),
                      ),
                    ),

                    // Info for new users
                    Padding(
                      padding: tt.cardPadding,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            l10n.firstTimeHerePrefix,
                            textAlign: TextAlign.center,
                            style: TenturaText.bodyMedium(
                              Theme.of(context).colorScheme.onSurface,
                            ),
                          ),
                          TextButton(
                            onPressed: authCubit.openInviteEmailUrl,
                            child: Text(authCubit.inviteEmail),
                          ),
                          Text(
                            l10n.firstTimeHereSuffix,
                            textAlign: TextAlign.center,
                            style: TenturaText.bodyMedium(
                              Theme.of(context).colorScheme.onSurface,
                            ),
                          ),
                        ],
                      ),
                    ),

                    // Create new account
                    Padding(
                      padding: EdgeInsets.all(tt.screenHPadding),
                      child: FilledButton(
                        onPressed: context
                            .read<ScreenCubit>()
                            .showProfileCreator,
                        child: Text(l10n.createNewAccount),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
