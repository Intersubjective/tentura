import 'package:gravity/data/auth_repository.dart';
import 'package:gravity/features/my_field/data/_g/beacon_fetch_pinned_by_user_id.req.gql.dart';

import 'package:gravity/ui/consts.dart';
import 'package:gravity/ui/ferry_utils.dart';
import 'package:gravity/features/beacon/widget/beacon_tile.dart';

class PinnedTab extends StatelessWidget {
  static const _requestId = 'BeaconFetchPinned';

  const PinnedTab({super.key});

  @override
  Widget build(BuildContext context) => Operation(
        client: GetIt.I<Client>(),
        operationRequest: GBeaconFetchPinnedByUserIdReq(
          (b) => b
            ..requestId = _requestId
            ..vars.user_id = GetIt.I<AuthRepository>().myId,
        ),
        builder: (context, response, error) =>
            showLoaderOrErrorOr(response, error) ??
            RefreshIndicator.adaptive(
              onRefresh: () async => GetIt.I<Client>()
                  .requestController
                  .add(GBeaconFetchPinnedByUserIdReq(
                    (b) => b
                      ..requestId = _requestId
                      ..fetchPolicy = FetchPolicy.NetworkOnly
                      ..vars.user_id = GetIt.I<AuthRepository>().myId,
                  )),
              child: response?.data?.beacon_pinned.isEmpty ?? false
                  ? const Center(child: Text('Nothing here yet'))
                  : ListView.separated(
                      cacheExtent: 5,
                      padding: paddingAll20,
                      itemCount: response!.data!.beacon_pinned.length,
                      separatorBuilder: (_, __) => const Divider(),
                      itemBuilder: (context, i) => BeaconTile(
                        beacon: response.data!.beacon_pinned[i].beacon,
                      ),
                    ),
            ),
      );
}