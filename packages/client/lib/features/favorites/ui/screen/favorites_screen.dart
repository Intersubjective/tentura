import 'package:get_it/get_it.dart';
import 'package:flutter/material.dart';
import 'package:auto_route/auto_route.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/ui/l10n/l10n.dart';

import 'package:tentura/features/beacon/ui/widget/beacon_tile.dart';

import '../bloc/favorites_cubit.dart';

@RoutePage()
class FavoritesScreen extends StatelessWidget {
  const FavoritesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final favoritesCubit = GetIt.I<FavoritesCubit>();
    final theme = Theme.of(context);
    final tt = context.tt;
    final l10n = L10n.of(context)!;
    return SafeArea(
      minimum: EdgeInsets.symmetric(horizontal: tt.rowGap),
      child: Semantics(
        label: l10n.favorites,
        explicitChildNodes: true,
        child: BlocBuilder<FavoritesCubit, FavoritesState>(
          bloc: favoritesCubit,
          buildWhen: (_, c) => c.isSuccess,
          builder: (_, state) => state.isLoading
              ? const Center(
                  child: CircularProgressIndicator.adaptive(),
                )
              : RefreshIndicator.adaptive(
                  onRefresh: favoritesCubit.fetch,
                  child: state.beacons.isEmpty
                      ? ListView(
                          physics: const AlwaysScrollableScrollPhysics(),
                          children: [
                            SizedBox(
                              height: MediaQuery.sizeOf(context).height * 0.5,
                              child: Center(
                                child: Text(
                                  l10n.labelNothingHere,
                                  style: theme.textTheme.displaySmall,
                                  textAlign: TextAlign.center,
                                ),
                              ),
                            ),
                          ],
                        )
                      : ListView.builder(
                          key: const PageStorageKey('FavoritesListView'),
                          physics: const AlwaysScrollableScrollPhysics(),
                          itemCount: state.beacons.length,
                          itemBuilder: (_, i) {
                            final beacon = state.beacons[i];
                            return Padding(
                              padding: EdgeInsets.symmetric(
                                vertical: tt.rowGap,
                              ),
                              child: BeaconTile(
                                key: ValueKey(beacon),
                                beacon: beacon,
                                isMine: false,
                              ),
                            );
                          },
                        ),
                ),
        ),
      ),
    );
  }
}
