import 'package:sentry/sentry.dart';
import 'package:shelf_plus/shelf_plus.dart';

import 'package:tentura_server/consts.dart';
import 'package:tentura_server/domain/entity/jwt_entity.dart';

import 'sentry_benign_filter.dart';

/// Per-request Sentry state stored in [Request.context].
final class SentryRequestContext {
  SentryRequestContext({
    required this.hub,
    required this.transaction,
    required this.sentryRequest,
  });

  final Hub hub;
  final ISentrySpan transaction;
  final SentryRequest sentryRequest;

  String? _graphqlOperationName;

  String? get graphqlOperationName => _graphqlOperationName;

  static SentryRequestContext? from(Request request) =>
      request.context[kSentryRequestContextKey] as SentryRequestContext?;

  Future<void> enrichFromRequest(Request request) async {
    final jwt = request.context[kContextJwtKey] as JwtEntity?;
    if (jwt == null || jwt.sub.isEmpty) {
      return;
    }
    await hub.configureScope((scope) async {
      final existing = scope.user;
      await scope.setUser(
        SentryUser(
          id: jwt.sub,
          ipAddress: existing?.ipAddress,
        ),
      );
    });
  }

  void renameGraphqlOperation(String? operationName) {
    if (operationName == null || operationName.isEmpty) {
      return;
    }
    _graphqlOperationName = operationName;
    final name = 'graphql $operationName';
    transaction.setTag('graphql.operation', operationName);
    hub.configureScope((scope) {
      scope.transaction = name;
    });
  }

  Future<SentryId> captureException(
    Object throwable, {
    StackTrace? stackTrace,
    Map<String, String>? tags,
  }) {
    if (isBenignServerThrowable(throwable)) {
      return Future.value(SentryId.empty());
    }
    final transactionName = _transactionName();
    return hub.captureException(
      throwable,
      stackTrace: stackTrace,
      withScope: (scope) {
        scope.transaction = transactionName;
        tags?.forEach(scope.setTag);
      },
    );
  }

  String _transactionName() {
    if (_graphqlOperationName != null && _graphqlOperationName!.isNotEmpty) {
      return 'graphql ${_graphqlOperationName!}';
    }
    return sentryRequest.method != null && sentryRequest.url != null
        ? '${sentryRequest.method} ${Uri.parse(sentryRequest.url!).path}'
        : 'http.server';
  }
}
