import 'dart:async';
import 'package:get_it/get_it.dart';
import 'package:flutter/material.dart';
import 'package:auto_route/auto_route.dart';

import 'package:tentura/consts.dart';
import 'package:tentura/ui/bloc/screen_cubit.dart';
import 'package:tentura/ui/dialog/share_code_dialog.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/utils/ui_utils.dart';
import 'package:tentura/ui/widget/linear_pi_active.dart';

import '../bloc/invitation_cubit.dart';
import '../dialog/invitation_remove_dialog.dart';

@RoutePage()
class InvitationScreen extends StatelessWidget implements AutoRouteWrapper {
  const InvitationScreen({super.key});

  @override
  Widget wrappedRoute(BuildContext context) => MultiBlocProvider(
    providers: [
      BlocProvider.value(
        value: GetIt.I<ScreenCubit>(),
      ),
      BlocProvider(
        // ignore: discarded_futures //
        create: (_) => InvitationCubit()..fetch(),
      ),
    ],
    child: MultiBlocListener(
      listeners: const [
        BlocListener<ScreenCubit, ScreenState>(
          listener: commonScreenBlocListener,
        ),
        BlocListener<InvitationCubit, InvitationState>(
          listener: commonScreenBlocListener,
        ),
      ],
      child: this,
    ),
  );

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final invitationCubit = context.read<InvitationCubit>();
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.invitationScreenTitle),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: kSpacingSmall),
            child: IconButton(
              onPressed: () async {
                final invitation = await invitationCubit.createInvitation();
                if (invitation != null && context.mounted) {
                  await ShareCodeDialog.show(
                    context,
                    header: l10n.labelInvitationCode,
                    link: Uri.parse(kServerName).replace(
                      path: kPathAppLinkView,
                      queryParameters: {'id': invitation.id},
                    ),
                  );
                }
              },
              icon: const Icon(Icons.person_add_alt_1),
            ),
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(4),
          child: BlocSelector<InvitationCubit, InvitationState, bool>(
            key: Key('Loader:${invitationCubit.hashCode}'),
            selector: (state) => state.isLoading,
            builder: LinearPiActive.builder,
            bloc: invitationCubit,
          ),
        ),
      ),
      body: RefreshIndicator.adaptive(
        onRefresh: invitationCubit.fetch,
        child: BlocBuilder<InvitationCubit, InvitationState>(
          key: Key('Body:${invitationCubit.hashCode}'),
          bloc: invitationCubit,
          buildWhen: (_, c) => c.isSuccess,
          builder: (_, state) {
            return ListView.separated(
              itemCount: state.invitations.length,
              itemBuilder: (_, i) {
                final invitation = state.invitations[i];
                if (state.invitations.length > kFetchListOffset &&
                    state.invitations.length == i + 1) {
                  unawaited(invitationCubit.fetch(clear: false));
                }
                final createdAt = invitation.createdAt.toLocal();
                return ListTile(
                  key: ValueKey(invitation),
                  title: Text(invitation.id),
                  subtitle: Text(
                    '${dateFormatYMD(createdAt)}  ${timeFormatHm(createdAt)}',
                  ),
                  trailing: IconButton(
                    onPressed: () async {
                      if (await InvitationRemoveDialog.show(context) ?? false) {
                        await invitationCubit.deleteInvitationById(
                          invitation.id,
                        );
                      }
                    },
                    icon: Icon(
                      Icons.delete_outline_rounded,
                      color: Colors.red[300],
                    ),
                  ),
                  onTap: () => ShareCodeDialog.show(
                    context,
                    header: l10n.labelInvitationCode,
                    link: Uri.parse(kServerName).replace(
                      path: kPathAppLinkView,
                      queryParameters: {'id': invitation.id},
                    ),
                  ),
                );
              },
              separatorBuilder: separatorBuilder,
            );
          },
        ),
      ),
    );
  }
}
