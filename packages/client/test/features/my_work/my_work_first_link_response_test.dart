// #999: My Work repositories use firstLinkResponse so a stream that completes
// without a Link response throws GraphQLNoDataException, not StateError.

import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/data/service/remote_api_client/exception.dart';
import 'package:tentura/data/service/remote_api_service.dart';
import 'package:tentura/features/my_work/data/gql/_g/my_work_fetch.data.gql.dart';
import 'package:tentura/features/my_work/data/gql/_g/my_work_fetch.req.gql.dart';
import 'package:tentura/features/my_work/data/gql/_g/my_work_fetch.var.gql.dart';

void main() {
  final request = GMyWorkInitReq(
    (b) => b..vars.userId = 'Uauthor000001',
  );

  test('MyWorkInit stream accepts Link after Cache', () async {
    final cached = OperationResponse<GMyWorkInitData, GMyWorkInitVars>(
      operationRequest: request,
      dataSource: DataSource.Cache,
    );
    final network = OperationResponse<GMyWorkInitData, GMyWorkInitVars>(
      operationRequest: request,
      dataSource: DataSource.Link,
    );
    expect(
      await Stream.fromIterable([cached, network]).firstLinkResponse(
        label: 'MyWork',
      ),
      same(network),
    );
  });

  test(
    'MyWorkInit empty stream throws GraphQLNoDataException (#999)',
    () async {
      await expectLater(
        const Stream<
              OperationResponse<GMyWorkInitData, GMyWorkInitVars>
            >.empty()
            .firstLinkResponse(label: 'MyWork'),
        throwsA(isA<GraphQLNoDataException>()),
      );
    },
  );
}
