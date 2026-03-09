import 'dart:async';
import 'package:flutter/material.dart';
import 'package:auto_route/auto_route.dart';

import 'package:tentura/consts.dart';
import 'package:tentura/ui/bloc/screen_cubit.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/utils/ui_utils.dart';
import 'package:tentura/ui/widget/bottom_text_input.dart';

import 'package:tentura/features/opinion/ui/bloc/opinion_cubit.dart';
import 'package:tentura/features/opinion/ui/widget/opinion_list.dart';
import 'package:tentura/features/profile/ui/bloc/profile_cubit.dart';

import '../bloc/profile_view_cubit.dart';
import '../dialog/opinion_publish_dialog.dart';
import '../widget/profile_view_app_bar.dart';
import '../widget/profile_view_body.dart';

@RoutePage()
class ProfileViewScreen extends StatelessWidget implements AutoRouteWrapper {
  const ProfileViewScreen({
    @PathParam('id') this.id = '',
    @QueryParam(kQueryIsDeepLink) this.isDeepLink,
    super.key,
  });

  final String id;

  final String? isDeepLink;

  @override
  Widget wrappedRoute(BuildContext context) => MultiBlocProvider(
    providers: [
      BlocProvider(
        create: (_) => ScreenCubit(),
      ),
      BlocProvider(
        create: (_) => ProfileViewCubit(id: id),
      ),
      BlocProvider(
        create: (_) => OpinionCubit.resolveId(
          myProfile: GetIt.I<ProfileCubit>().state.profile,
          objectId: id,
        ),
      ),
    ],
    child: MultiBlocListener(
      listeners: const [
        BlocListener<ProfileViewCubit, ProfileViewState>(
          listener: commonScreenBlocListener,
        ),
        BlocListener<OpinionCubit, OpinionState>(
          listener: commonScreenBlocListener,
        ),
        BlocListener<ScreenCubit, ScreenState>(
          listener: commonScreenBlocListener,
        ),
      ],
      child: this,
    ),
  );

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final opinionCubit = context.read<OpinionCubit>();
    return Scaffold(
      body: RefreshIndicator.adaptive(
        onRefresh: () => Future.wait([
          context.read<ProfileViewCubit>().fetch(),
          opinionCubit.fetch(preserve: false),
        ]),
        child: CustomScrollView(
          slivers: [
            // Header
            ProfileViewAppBar(
              key: const Key('ProfileViewScreen:AppBar'),
              isFromDeepLink: isDeepLink == 'true',
            ),

            // Body
            const SliverPadding(
              padding: kPaddingAll,
              sliver: ProfileViewBody(),
            ),

            // Opinions
            SliverPadding(
              padding: kPaddingBottomTextInput,
              sliver: OpinionList(key: ValueKey(id)),
            ),
          ],
        ),
      ),

      // Text Input
      bottomSheet: BlocSelector<OpinionCubit, OpinionState, bool>(
        key: const Key('ProfileViewScreen:BottomTextInput'),
        bloc: opinionCubit,
        selector: (state) => state.hasMyOpinion,
        builder: (_, hasMyOpinion) => hasMyOpinion
            // Blocked input
            ? BottomTextInput(hintText: l10n.onlyOneOpinion)
            // Normal input
            : BottomTextInput(
                hintText: l10n.writeOpinion,
                onSend: (text) async => opinionCubit.addOpinion(
                  amount: await OpinionPublishDialog.show(context),
                  text: text,
                ),
              ),
      ),
    );
  }
}
