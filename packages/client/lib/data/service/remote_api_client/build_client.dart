import 'dart:async';
import 'dart:developer';
import 'package:ferry/ferry.dart'
    show Client, FetchPolicy, Link, NextLink, OperationType;
import 'package:gql_exec/gql_exec.dart' show Request, Response;
import 'package:gql_http_link/gql_http_link.dart';
import 'package:gql_error_link/gql_error_link.dart';
import 'package:gql_dedupe_link/gql_dedupe_link.dart';
import 'package:http/http.dart' show MultipartFile;

import 'package:tentura_root/consts.dart';

import 'auth_link.dart';

typedef ClientParams = ({
  String apiEndpointUrl,
  String apiEndpointUrlV2,
  String userAgent,
  Duration requestTimeout,
});

Future<Client> buildClient({
  required ClientParams params,
  required Future<String?> Function() getToken,
}) async {
  final defaultHeaders = {
    kHeaderAccept: kContentApplicationJson,
    kHeaderUserAgent: params.userAgent,
  };

  return Client(
    defaultFetchPolicies: {
      OperationType.query: FetchPolicy.NoCache,
      OperationType.mutation: FetchPolicy.NoCache,
      OperationType.subscription: FetchPolicy.NoCache,
    },
    link: Link.from([
      DedupeLink(),

      AuthLink(getToken),

      ErrorLink(
        onException: (request, forward, exception) {
          log(exception.toString());
          return null;
        },
        onGraphQLError: (request, forward, response) {
          log(response.errors.toString());
          return null;
        },
      ),

      _FileRoutingLink(
        defaultLink: HttpLink(
          params.apiEndpointUrl,
          defaultHeaders: defaultHeaders,
        ),
        fileUploadLink: HttpLink(
          params.apiEndpointUrlV2,
          defaultHeaders: defaultHeaders,
        ),
      ),
    ]),
  );
}

/// Routes requests with file uploads or selected Tentura-only operations to
/// [fileUploadLink] (v2). Everything else goes to [defaultLink] (v1 / Hasura).
///
/// Mutations implemented only on Tentura must hit v2 directly: Hasura remote
/// schema forwarding can mangle list arguments (e.g. `beaconForward.recipientIds`).
/// Mirrors the content-type split that Caddy does in production between Hasura
/// (v1) and Tentura (v2).
class _FileRoutingLink extends Link {
  _FileRoutingLink({required this.defaultLink, required this.fileUploadLink});

  final Link defaultLink;
  final Link fileUploadLink;

  /// Operation names that must use Tentura's `/api/v2/graphql` (not Hasura v1).
  static const _tenturaDirectOperationNames = {'ForwardBeacon'};

  @override
  Stream<Response> request(Request request, [NextLink? forward]) {
    if (_hasFiles(request.variables) ||
        _tenturaDirectOperationNames.contains(request.operation.operationName)) {
      return fileUploadLink.request(request, forward);
    }
    return defaultLink.request(request, forward);
  }

  static bool _hasFiles(Map<String, dynamic> vars) {
    for (final value in vars.values) {
      if (_isOrContainsFile(value)) return true;
    }
    return false;
  }

  static bool _isOrContainsFile(dynamic value) {
    if (value is MultipartFile) return true;
    if (value is Map<String, dynamic>) return _hasFiles(value);
    if (value is List) return value.any(_isOrContainsFile);
    return false;
  }

  @override
  Future<void> dispose() async {
    await defaultLink.dispose();
    await fileUploadLink.dispose();
  }
}
