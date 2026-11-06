// #1046: ConstellationFieldSearchRepository relies on firstLinkResponse — same
// behaviour as other operations (cache-only completes are not authoritative).

import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/data/service/remote_api_client/exception.dart';
import 'package:tentura/data/service/remote_api_service.dart';
import 'package:tentura/features/constellation/data/gql/_g/field_search.data.gql.dart';
import 'package:tentura/features/constellation/data/gql/_g/field_search.req.gql.dart';
import 'package:tentura/features/constellation/data/gql/_g/field_search.var.gql.dart';

void main() {
  final request = GFieldSearchReq(
    (b) => b
      ..vars.query = 'ab'
      ..vars.context = 'ctx',
  );

  test('FieldSearch stream accepts Link after Cache', () async {
    final cached = OperationResponse<GFieldSearchData, GFieldSearchVars>(
      operationRequest: request,
      dataSource: DataSource.Cache,
    );
    final network = OperationResponse<GFieldSearchData, GFieldSearchVars>(
      operationRequest: request,
      dataSource: DataSource.Link,
    );
    expect(
      await Stream.fromIterable([cached, network]).firstLinkResponse(
        label: 'FieldSearch',
      ),
      same(network),
    );
  });

  test(
    'FieldSearch cache-only completion throws GraphQLNoDataException',
    () async {
      final cached = OperationResponse<GFieldSearchData, GFieldSearchVars>(
        operationRequest: request,
        dataSource: DataSource.Cache,
      );
      await expectLater(
        Stream.value(cached).firstLinkResponse(label: 'FieldSearch'),
        throwsA(isA<GraphQLNoDataException>()),
      );
    },
  );
}
