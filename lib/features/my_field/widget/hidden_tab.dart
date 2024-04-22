import 'package:tentura/ui/utils/ui_consts.dart';
import 'package:tentura/ui/utils/ferry_utils.dart';
import 'package:tentura/ui/widget/empty_list_scroll_view.dart';

import 'package:tentura/features/beacon/widget/beacon_tile.dart';
import 'package:tentura/features/auth/ui/bloc/auth_cubit.dart';
import 'package:tentura/features/beacon/data/_g/beacon_unhide_by_id.req.gql.dart';

import '../data/_g/beacon_fetch_hidden_by_user_id.req.gql.dart';

class HiddenTab extends StatelessWidget {
  static const _requestId = 'BeaconFetchHidden';

  const HiddenTab({super.key});

  @override
  Widget build(BuildContext context) {
    final client = GetIt.I<Client>();
    final myId = GetIt.I<AuthCubit>().state.currentAccount;
    return Operation(
      client: client,
      operationRequest: GBeaconFetchHiddenByUserIdReq(
        (b) => b
          ..requestId = _requestId
          ..vars.user_id = myId,
      ),
      builder: (context, response, error) =>
          showLoaderOrErrorOr(response, error) ??
          RefreshIndicator.adaptive(
            onRefresh: () async =>
                client.requestController.add(GBeaconFetchHiddenByUserIdReq(
              (b) => b
                ..requestId = _requestId
                ..vars.user_id = myId,
            )),
            child: response?.data?.beacon_hidden.isEmpty ?? false
                ? const EmptyListScrollView()
                : ListView.separated(
                    padding: paddingAll20,
                    itemCount: response!.data!.beacon_hidden.length,
                    separatorBuilder: (_, __) => const Divider(),
                    itemBuilder: (context, i) {
                      final beacon = response.data!.beacon_hidden[i].beacon;
                      return Dismissible(
                        key: ValueKey(beacon),
                        background: const Align(
                          alignment: Alignment.centerLeft,
                          child: Text('Unhide'),
                        ),
                        direction: DismissDirection.startToEnd,
                        child: BeaconTile(beacon: beacon),
                        confirmDismiss: (_) => doRequest(
                          context: context,
                          request: GBeaconUnhideByIdReq(
                            (b) => b
                              ..vars.user_id = myId
                              ..vars.beacon_id = beacon.id,
                          ),
                        ).then((value) => value.hasNoErrors),
                      );
                    },
                  ),
          ),
    );
  }
}
