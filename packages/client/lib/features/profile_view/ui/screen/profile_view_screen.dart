import 'package:flutter/material.dart';
import 'package:auto_route/auto_route.dart';

import 'package:tentura/consts.dart';
import 'package:tentura/ui/bloc/screen_cubit.dart';
import 'package:tentura/ui/utils/ui_utils.dart';

import 'package:tentura/features/profile/ui/bloc/profile_cubit.dart';

import '../bloc/profile_shared_beacons_cubit.dart';
import '../bloc/profile_view_cubit.dart';
import '../widget/profile_shared_beacons_sliver.dart';
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
        create: (_) => ProfileSharedBeaconsCubit(
          meId: GetIt.I<ProfileCubit>().state.profile.id,
          targetId: id,
        ),
      ),
    ],
    child: MultiBlocListener(
      listeners: const [
        BlocListener<ProfileViewCubit, ProfileViewState>(
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
  Widget build(BuildContext context) => Scaffold(
        body: RefreshIndicator.adaptive(
          onRefresh: () => Future.wait([
            context.read<ProfileViewCubit>().fetch(),
            context.read<ProfileSharedBeaconsCubit>().fetch(),
          ]),
          child: const CustomScrollView(
            slivers: [
              // Header
              ProfileViewAppBar(
                key: Key('ProfileViewScreen:AppBar'),
              ),

              // Body
              SliverPadding(
                padding: kPaddingAll,
                sliver: ProfileViewBody(),
              ),

              // Shared beacons (forwarded + co-committed)
              ProfileSharedBeaconsSliver(),
            ],
          ),
        ),
      );
}
