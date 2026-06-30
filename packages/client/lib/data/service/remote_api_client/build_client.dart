import 'dart:developer';
import 'package:ferry/ferry.dart'
    show Client, FetchPolicy, Link, NextLink, OperationType;
import 'package:gql_exec/gql_exec.dart' show Request, Response;
import 'package:gql_http_link/gql_http_link.dart';
import 'package:gql_error_link/gql_error_link.dart';
import 'package:gql_dedupe_link/gql_dedupe_link.dart';
import 'package:http/http.dart' as http;
import 'package:sentry_flutter/sentry_flutter.dart';

import 'package:tentura/app/sentry/sentry_init.dart';
import 'package:tentura_root/consts.dart';

import 'auth_link.dart';
import 'auth_loss_classifier.dart';
import 'graphql_v2_exceptions.dart';
import 'v2_upload_multipart_link.dart';

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

  final hasuraHttpClient = _createGraphqlHttpClient();
  final tenturaV2HttpClient = _createGraphqlHttpClient();

  return Client(
    defaultFetchPolicies: {
      OperationType.query: FetchPolicy.NoCache,
      OperationType.mutation: FetchPolicy.NoCache,
      OperationType.subscription: FetchPolicy.NoCache,
    },
    link: Link.from([
      _HasuraSetofScalarFixLink(),

      DedupeLink(),

      AuthLink(getToken),

      ErrorLink(
        onException: (request, forward, exception) {
          log(exception.toString());
          // Classify the link/transport exception (ServerException carrying
          // GraphQL errors, HTTP status, parse failures, socket errors, …) so
          // the UI shows the real cause instead of a flattened, type-erased
          // `Exception` that always looked like "no internet".
          throw mapRemoteFailure(exception);
        },
        onGraphQLError: (request, forward, response) {
          log(response.errors.toString());
          final errs = response.errors;
          if (errs != null && errs.isNotEmpty) {
            final ext = errs.first.extensions;
            if (ext != null) {
              final code = int.tryParse(ext['code']?.toString() ?? '');
              final factId = ext['factCardId'] as String?;
              if (code == BeaconFactAlreadyPinnedRemoteException.codeNumber &&
                  factId != null &&
                  factId.isNotEmpty) {
                throw BeaconFactAlreadyPinnedRemoteException(
                  factCardId: factId,
                );
              }
            }
            throw mapRemoteFailure(errs);
          }
          throw Exception(response.errors.toString());
        },
      ),

      _V2RoutingLink(
        hasuraLink: HttpLink(
          params.apiEndpointUrl,
          defaultHeaders: defaultHeaders,
          httpClient: hasuraHttpClient,
        ),
        tenturaV2Link: Link.from([
          V2UploadMultipartLink(
            uri: Uri.parse(params.apiEndpointUrlV2),
            httpClient: tenturaV2HttpClient,
            defaultHeaders: defaultHeaders,
          ),
          HttpLink(
            params.apiEndpointUrlV2,
            defaultHeaders: defaultHeaders,
            httpClient: tenturaV2HttpClient,
          ),
        ]),
      ),
    ]),
  );
}

http.Client _createGraphqlHttpClient() {
  if (sentryDsn.isEmpty) {
    return http.Client();
  }
  return SentryHttpClient(
    client: http.Client(),
    captureFailedRequests: false,
  );
}

/// Routes each request to Hasura v1 or Tentura v2 by **operation name** only.
///
/// Operations implemented on Tentura V2 (`/api/v2/graphql`) **must** be
/// listed in [_tenturaDirectOperationNames] so the client calls V2 directly
/// instead of going through Hasura (which would proxy to V2 via remote schema,
/// adding latency and coupling V2 availability to Hasura).
///
/// When adding a new V2 query or mutation on the server:
/// 1. Add the operation name (as in the client `.graphql` file) to
///    [_tenturaDirectOperationNames].
/// 2. Ensure the client operation selects only fields/types V2 exposes (same
///    names as in Hasura-introspected `schema.graphql` where applicable).
/// 3. File uploads use multipart on V2; the server `GraphqlController`
///    accepts both JSON and multipart — no extra client routing is needed.
///
/// Operations not listed here use [hasuraLink] (Hasura `/api/v1/graphql`).
class _V2RoutingLink extends Link {
  _V2RoutingLink({
    required this.hasuraLink,
    required this.tenturaV2Link,
  });

  final Link hasuraLink;
  final Link tenturaV2Link;

  /// Client operation names whose resolvers live on Tentura V2.
  static const _tenturaDirectOperationNames = {
    'BeaconAddImage',
    'BeaconOfferHelp',
    'BeaconCreate',
    'BeaconFork',
    'BeaconLineageForwardSuggestions',
    'BeaconUpdate',
    'BeaconUpdateDraft',
    'BeaconForwardGraph',
    'BeaconHelpOffererForwardPath',
    'BeaconInvolvementData',
    'BeaconDeleteById',
    'BeaconRemoveImage',
    'BeaconReorderImages',
    'BeaconClose',
    'BeaconCancel',
    'BeaconExtendReview',
    'BeaconReopen',
    'BeaconCloseNow',
    'BeaconWithdraw',
    'HelpOffersWithCoordination',
    'SetCoordinationResponse',
    'SetBeaconStatus',
    'BeaconDisplayStatuses',
    'EvaluationParticipants',
    'EvaluationDraftParticipants',
    'ReviewWindowStatus',
    'EvaluationSummary',
    'EvaluationSubmit',
    'EvaluationFinalize',
    'EvaluationSkip',
    'EvaluationDraftSave',
    'CreateComplaint',
    'FcmRegisterToken',
    'FcmTokenDelete',
    'ForwardBeacon',
    'InvitationCreate',
    'InvitationUpdate',
    'InvitationAccept',
    'InvitationById',
    'InviteGenealogy',
    'InviteGenealogyBetween',
    'InvitationDeleteById',
    'MyContacts',
    'ContactSet',
    'ContactDelete',
    'MutualFriendsFetch',
    'PollingAct',
    'ProfileDelete',
    'ProfileUpdate',
    'SignIn',
    'SignOut',
    'SignUp',
    'UserVote',
    'trustForceRefreshAll',
    'trustForceRefreshStar',
    'RoomMessageList',
    'BeaconParticipantList',
    'RoomMessageCreate',
    'RoomMessageAttachmentAdd',
    'BeaconParticipantOfferHelp',
    'BeaconRoomAdmit',
    'BeaconStewardPromote',
    'RoomMessageReactionToggle',
    'BeaconRoomStateGet',
    'BeaconActivityEventList',
    'InboxRoomContextBatch',
    'RoomMessageEdit',
    'RoomMessageDelete',
    'BeaconParticipantRoomSeen',
    'MarkBeaconRoomSeen',
    'BeaconFactCardList',
    'BeaconFactCardPin',
    'BeaconFactCardCorrect',
    'BeaconFactCardRemove',
    'BeaconFactCardSetVisibility',
    'CapabilityPrivateLabelSet',
    'CapabilitySetViewerVisible',
    'MyPrivateLabelsForUser',
    'PersonCapabilityCues',
    'PersonFriendContextBatch',
    'PersonTopCapabilitiesBatch',
    'CoordinationItemList',
    'CoordinationItemMarkBlocker',
    'CoordinationItemResolveBlocker',
    'CoordinationItemCancelBlocker',
    'CoordinationItemMarkAsk',
    'CoordinationItemCreatePromise',
    'CoordinationItemCreateDraftPromise',
    'CoordinationItemPublishPromise',
    'CoordinationItemUpdateDraftPromise',
    'CoordinationItemDeleteDraftPromise',
    'CoordinationItemAcceptPromise',
    'CoordinationItemResolvePromise',
    'CoordinationItemCancelPromise',
    'CoordinationItemRedirectPromise',
    'CoordinationItemCreateDraftAsk',
    'CoordinationItemPublishAsk',
    'CoordinationItemUpdateDraftAsk',
    'CoordinationItemDeleteDraftAsk',
    'CoordinationItemCreateDraftBlocker',
    'CoordinationItemPublishBlocker',
    'CoordinationItemUpdateDraftBlocker',
    'CoordinationItemDeleteDraftBlocker',
    'CoordinationItemAcceptAsk',
    'CoordinationItemResolveAsk',
    'CoordinationItemCancelAsk',
    'CoordinationItemRedirectAsk',
    'CoordinationItemUpdate',
    'CoordinationItemUpdatePlan',
    'CoordinationItemAddPlanStep',
    'CoordinationItemResolvePlanStep',
    'CoordinationItemCreateResolution',
    'CoordinationItemAcceptResolution',
    'CoordinationItemRejectResolution',
    'CoordinationItemRemind',
    'CoordinationResponsibilityBatch',
    'CoordinationMyResponsibilityItems',
    'MarkBeaconItemsSeen',
    'MyWorkCoordinationItemActivity',
    'MyWorkLastActivityEvent',
    'BeaconPublish',
  };

  @override
  Stream<Response> request(Request request, [NextLink? forward]) {
    if (_tenturaDirectOperationNames.contains(
      request.operation.operationName,
    )) {
      return tenturaV2Link.request(request, forward);
    }
    return hasuraLink.request(request, forward);
  }

  @override
  Future<void> dispose() async {
    await hasuraLink.dispose();
    await tenturaV2Link.dispose();
  }
}

/// Normalizes Hasura `SETOF scalar` computed fields that are serialized as a
/// bare value instead of a JSON array when the result set contains exactly one
/// row.  See `packages/server/WORKAROUNDS.md` § 5.
class _HasuraSetofScalarFixLink extends Link {
  @override
  Stream<Response> request(Request request, [NextLink? forward]) {
    return forward!(request).map((response) {
      _wrapBareRejectedUserIds(response.data);
      return response;
    });
  }

  static void _wrapBareRejectedUserIds(Map<String, dynamic>? data) {
    if (data == null) return;
    final beacon = data['beacon_by_pk'];
    if (beacon is Map<String, dynamic>) {
      final val = beacon['rejected_user_ids'];
      if (val is String) {
        beacon['rejected_user_ids'] = <String>[val];
      }
    }
  }
}
