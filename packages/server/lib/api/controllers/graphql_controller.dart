import 'dart:convert';
import 'dart:typed_data';
import 'package:graphql_server2/graphql_server2.dart' show GraphQL;
import 'package:injectable/injectable.dart';
import 'package:meta/meta.dart';
import 'package:shelf_multipart/shelf_multipart.dart';

import 'package:tentura_server/app/sentry/sentry_error_classifier.dart';
import 'package:tentura_server/app/sentry/sentry_request_context.dart';
import 'package:tentura_server/consts.dart';
import 'package:tentura_server/data/service/main_db_scope_admission.dart';
import 'package:tentura_server/domain/entity/jwt_entity.dart';
import 'package:tentura_server/domain/request_context.dart';
import 'package:tentura_server/domain/exception.dart';

import 'graphql/input/_input_types.dart';
import 'graphql/schema.dart';
import 'graphql/unmapped_graphql_error.dart';
import '_base_controller.dart';

@Injectable(order: 3)
final class GraphqlController extends BaseController {
  const GraphqlController(
    super.env, {
    @ignoreParam @visibleForTesting GraphQL? schema,
  }) : _schemaOverride = schema;

  /// Test seam: a schema used in place of the app's.
  final GraphQL? _schemaOverride;

  @override
  Future<Response> handler(Request request) async {
    final requestJson = <String, dynamic>{};
    Stream<Uint8List>? fileBytes;

    if (request.formData() case final form?) {
      await for (final formData in form.formData) {
        switch (formData.name) {
          case 'operations':
            requestJson.addAll(
              jsonDecode(await formData.part.readString())
                  as Map<String, dynamic>,
            );

          case 'map':
            requestJson['filesMeta'] = jsonDecode(
              await formData.part.readString(),
            );

          case '0':
            fileBytes = formData.part.cast<Uint8List>();

          default:
            throw GraphQLException([
              GraphQLExceptionError(
                'Got unsupported part named [${formData.name}]',
              ),
            ]);
        }
      }
    } else {
      requestJson.addAll(await request.body.asJson as Map<String, dynamic>);
    }

    final sentryContext = SentryRequestContext.from(request);
    final operationName = requestJson['operationName'] as String?;
    if (sentryContext != null) {
      await sentryContext.enrichFromRequest(request);
      sentryContext.renameGraphqlOperation(operationName);
    }

    try {
      final jwt = request.context[kGlobalInputQueryJwt] as JwtEntity?;
      final context = RequestContext.current;
      context?.actor = jwt?.sub;
      if (operationName == 'ConstellationFieldFetch') {
        context?.classify(RequestOperationClass.full);
      } else if (const {
        'BeaconAddImage',
        'BeaconStageImage',
        'BeaconSetMedia',
      }.contains(operationName)) {
        context?.classify(RequestOperationClass.upload);
      }
      context?.check();
      final response = await MainDbWorkContext.run(
        () =>
            (_schemaOverride ??
                    (env.isDebugModeOn ? graphqlSchema : _graphqlSchema))
                .parseAndExecute(
                  operationName: requestJson['operationName'] as String?,
                  requestJson['query'] as String? ?? '',
                  variableValues:
                      (requestJson['variables'] as Map<String, dynamic>?) ?? {},
                  globalVariables: {
                    kGlobalInputQueryJwt: jwt,
                    kGlobalInputQueryContext:
                        request.headers[kHeaderQueryContext],
                    kGlobalInputQueryFile: fileBytes,
                  },
                ),
        actorUserId: jwt?.sub,
      );

      switch (response) {
        case final Map<String, dynamic> query:
          return Response.ok(jsonEncode({'data': query}));

        case final Stream<Map<String, dynamic>> _:
          throw UnimplementedError();

        default:
          throw Exception('Unexpected type');
      }
    } on GraphQLException catch (e) {
      return Response.ok(jsonEncode(e.toJson()));
    } on ExceptionBase catch (e, st) {
      if (isInternalFaultException(e)) {
        await sentryContext?.captureException(
          e,
          stackTrace: st,
          tags: {
            'graphql.operation': operationName ?? '',
            'exception.code': '${e.code.codeNumber}',
          },
        );
      }
      return Response.ok(
        jsonEncode({
          'errors': [e.toMap],
        }),
      );
    } catch (e, st) {
      await sentryContext?.captureException(
        e,
        stackTrace: st,
        tags: {
          'graphql.operation': operationName ?? '',
        },
      );
      return Response.ok(
        jsonEncode({
          'errors': [unmappedGraphqlError(e)],
        }),
      );
    }
  }

  static final _graphqlSchema = graphqlSchema;
}
