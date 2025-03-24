import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';

import 'package:tentura/features/opinion/ui/bloc/opinion_cubit.dart';
import 'package:tentura/features/opinion/ui/widget/opinion_list.dart';
import 'package:tentura/features/profile/ui/bloc/profile_cubit.dart';
import 'package:localization/localization.dart';

import 'package:tentura/ui/bloc/screen_cubit.dart';
import 'package:tentura/ui/utils/ui_utils.dart';
import 'package:tentura/ui/widget/bottom_text_input.dart';

import '../bloc/profile_view_cubit.dart';
import '../dialog/opinion_publish_dialog.dart';
import '../widget/profile_view_app_bar.dart';
import '../widget/profile_view_body.dart';

@RoutePage()
class ProfileViewScreen extends StatelessWidget implements AutoRouteWrapper {
  const ProfileViewScreen({@queryParam this.id = '', super.key});

  final String id;

  @override
  Widget wrappedRoute(BuildContext context) => MultiBlocProvider(
    providers: [
      BlocProvider.value(value: GetIt.I<ScreenCubit>()),
      BlocProvider(create: (_) => ProfileViewCubit(id: id)),
      BlocProvider(
        create: (_) {
          return OpinionCubit(
            objectId: id,
            myProfile: GetIt.I<ProfileCubit>().state.profile,
          );
        },
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
    final opinionCubit = context.read<OpinionCubit>();
    final profileViewCubit = context.read<ProfileViewCubit>();
    return Scaffold(
      body: RefreshIndicator.adaptive(
        onRefresh: () async {
          await Future.wait([profileViewCubit.fetch(), opinionCubit.fetch()]);
        },
        child: CustomScrollView(
          slivers: [
            // Header
            const ProfileViewAppBar(),

            // Body
            const SliverPadding(
              padding: kPaddingAll,
              sliver: ProfileViewBody(),
            ),

            // Opinions
            SliverPadding(
              padding: kPaddingH,
              sliver: OpinionList(key: ValueKey(id)),
            ),
          ],
        ),
      ),

      // Text Input
      bottomSheet: BlocSelector<OpinionCubit, OpinionState, bool>(
        selector: (state) => state.hasMyOpinion,
        bloc: opinionCubit,
        builder: (_, hasMyOpinion) {
          return hasMyOpinion
              ? BottomTextInput(hintText: AppLocalizations.of(context)!.onlyOneOpinion)
              : BottomTextInput(
                hintText: AppLocalizations.of(context)!.writeOpinion,
                onSend: (text) async {
                  await opinionCubit.addOpinion(
                    amount: await OpinionPublishDialog.show(context),
                    text: text,
                  );
                },
              );
        },
      ),
    );
  }
}
