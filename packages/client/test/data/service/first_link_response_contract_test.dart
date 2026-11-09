// #1173 split: repositories await the authoritative Link response through
// firstLinkResponse(label:). A request stream that closes before any Link
// response (e.g. a cache-only answer, or a request finished by disposal)
// throws GraphQLNoDataException carrying the repository's label, not the
// bare StateError ("No element") that `firstWhere` threw.

import 'package:ferry/ferry.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/data/repository/attention_repository.dart';
import 'package:tentura/data/service/remote_api_client/exception.dart';
import 'package:tentura/data/service/remote_api_client/remote_request_client.dart';
import 'package:tentura/data/service/remote_api_service.dart' show LinkResponse;
import 'package:tentura/features/attention/data/gql/_g/attention_mark_seen.data.gql.dart';
import 'package:tentura/features/attention/data/gql/_g/attention_mark_seen.req.gql.dart';
import 'package:tentura/features/attention/data/gql/_g/attention_mark_seen.var.gql.dart';

/// Answers each request with nothing, or a single Cache response, and then
/// closes the stream: no Link response ever arrives.
class _ClosingRemoteClient implements RemoteRequestClient {
  _ClosingRemoteClient({required this.cacheOnly});

  final bool cacheOnly;
  int requests = 0;

  @override
  Stream<OperationResponse<TData, TVars>> request<TData, TVars>(
    OperationRequest<TData, TVars> request, [
    Stream<OperationResponse<TData, TVars>> Function(
      OperationRequest<TData, TVars>,
    )?
    forward,
  ]) {
    requests++;
    return cacheOnly
        ? Stream.value(
            OperationResponse<TData, TVars>(
              operationRequest: request,
              dataSource: DataSource.Cache,
            ),
          )
        : const Stream.empty();
  }
}

Matcher _noData(String label) => throwsA(
  isA<GraphQLNoDataException>().having((e) => e.label, 'label', label),
);

void main() {
  group('firstLinkResponse helper', () {
    final request = GAttentionMarkSeenReq((r) => r.vars.ids.add('r-1'));

    test('a stream closing before any response throws '
        'GraphQLNoDataException with the label, not StateError', () async {
      final pending =
          const Stream<
                OperationResponse<
                  GAttentionMarkSeenData,
                  GAttentionMarkSeenVars
                >
              >.empty()
              .firstLinkResponse(label: 'Probe');
      await expectLater(pending, _noData('Probe'));
      await expectLater(
        const Stream<int>.empty().firstWhere((_) => true),
        throwsStateError,
        reason: 'the old firstWhere form threw StateError here',
      );
    });

    test('a cache-only stream is not an authoritative answer', () async {
      await expectLater(
        Stream.value(
          OperationResponse<GAttentionMarkSeenData, GAttentionMarkSeenVars>(
            operationRequest: request,
            dataSource: DataSource.Cache,
          ),
        ).firstLinkResponse(label: 'Probe'),
        _noData('Probe'),
      );
    });
  });

  group('through AttentionRepository', () {
    for (final cacheOnly in [false, true]) {
      test(
        'markSeen on a stream that closes without a Link response '
        '(cacheOnly: $cacheOnly) throws GraphQLNoDataException(Attention)',
        () async {
          final remote = _ClosingRemoteClient(cacheOnly: cacheOnly);
          final repository = AttentionRepository(remote);

          await expectLater(repository.markSeen(['r-1']), _noData('Attention'));
          expect(remote.requests, 1);
        },
      );
    }
  });
}
