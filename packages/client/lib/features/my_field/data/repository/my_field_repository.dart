import 'package:injectable/injectable.dart';

// import 'package:tentura/consts.dart';
import 'package:tentura/data/model/beacon_model.dart';
import 'package:tentura/data/service/remote_api_service.dart';
import 'package:tentura/domain/entity/beacon.dart';

import '../gql/_g/my_field_fetch.req.gql.dart';

@lazySingleton
class MyFieldRepository {
  MyFieldRepository(this._remoteApiService);

  final RemoteApiService _remoteApiService;

  Future<Iterable<Beacon>> fetch({required String context}) => _remoteApiService
      .request(
        GMyFieldFetchReq(
          (r) => r
            // ..context = const Context().withEntry(
            //   HttpLinkHeaders(headers: {kHeaderQueryContext: context}),
            // )
            ..vars.context = context,
        ),
      )
      .firstWhere((e) => e.dataSource == DataSource.Link)
      .then((r) => r.dataOrThrow(label: _label).my_field.nonNulls)
      .then((v) => v.map((e) => (e.beacon! as BeaconModel).toEntity()));

  static const _label = 'MyField';
}
