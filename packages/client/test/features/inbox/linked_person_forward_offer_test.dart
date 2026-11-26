@TestOn('vm')
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gql/ast.dart';
import 'package:gql/language.dart';
import 'package:logging/logging.dart';
import 'package:mockito/mockito.dart';

import 'package:tentura/data/repository/attention_repository.dart';
import 'package:tentura/data/service/remote_api_client/remote_request_client.dart';
import 'package:tentura/data/service/remote_api_service.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/attention/attention_case.dart';
import 'package:tentura/domain/attention/entity/attention_feed.dart';
import 'package:tentura/domain/attention/feed_session_registry.dart';
import 'package:tentura/domain/attention/port/attention_account_port.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/beacon/data/repository/beacon_repository.dart';
import 'package:tentura/features/forward/data/repository/forward_repository.dart';
import 'package:tentura/features/forward/domain/use_case/forward_case.dart';
import 'package:tentura/features/inbox/ui/bloc/activity_offers_cubit.dart';
import 'package:tentura/features/inbox/ui/bloc/inbox_cubit.dart';
import 'package:tentura/features/inbox/ui/widget/activity_stream_view.dart';
import 'package:tentura/features/phantoms/data/repository/phantom_repository.dart';
import 'package:tentura/features/phantoms/domain/port/phantom_repository_port.dart';
import 'package:tentura/features/profile/ui/bloc/profile_cubit.dart';
import 'package:tentura/features/updates/ui/bloc/updates_feed_cubit.dart';
import 'package:tentura/ui/bloc/screen_cubit.dart';
import 'package:tentura/ui/effect/ui_effect_port.dart';
import 'package:tentura/ui/l10n/l10n.dart';

import '../../support/attention_case_factory.dart';
import '../../support/fake_app_navigator.dart';
import '../../support/noop_attention_actor_profiles.dart';
import '../../support/phone_surface.dart';
import '../../support/remote_wire_harness.dart';
import '../../support/test_forward_case.dart';
import '../../support/test_realtime_sync.dart';
import '../../ui/effect/fake_ui_effect_port.dart';
import '../block/support/controllable_block_case.dart';
import '../updates/support/noop_invite_setup_port.dart';
import 'inbox_case_test.dart'
    show FakeInboxRepository, buildTestBeaconThreadsCase, buildTestInboxCase;

const _owner = Profile(id: 'Uviewer000001', displayName: 'Sender');
const _requestId = 'B000000000042';
const _requestTitle = 'Fix the bike';
const _recipient = 'Anna';
const _annaId = 'U000000000088';
const _offerId = 'PF000000000011';
const _mergeId = 'PM000000000021';
const _ordinaryForwardField = 'beaconForward';
const _confirmField = 'phantomForwardConfirm';
const _placeholderForwardField = 'beaconForwardToPhantom';
const _enQuestion = 'Forward «$_requestTitle» to $_recipient now?';
final _ruQuestion = RegExp(r'^Переслать .*Fix the bike.*Anna.*\?$');

void main() {
  for (final (locale, confirm) in const [
    (Locale('en'), true),
    (Locale('en'), false),
    (Locale('ru'), true),
    (Locale('ru'), false),
  ]) {
    final language = locale.languageCode;
    testWidgets(
      confirm
          ? 'confirming the $language offer sends the saved Request to the linked account once'
          : 'declining the $language offer sends no Request to the linked account',
      (tester) async {
        if (language == 'ru') await usePhoneSurface(tester);
        await _withActivity(tester, locale, (wire) async {
          final questionPattern = language == 'ru'
              ? _ruQuestion
              : RegExp('^${RegExp.escape(_enQuestion)}\$');
          final question = find.textContaining(
            questionPattern,
            findRichText: true,
          );
          expect(question, findsOneWidget);
          expect(
            wire.forwardWrites,
            isEmpty,
            reason: 'Showing the offer sends nothing',
          );

          final l10n = lookupL10n(locale);
          final confirmAction = _label(
            language == 'ru'
                ? {l10n.buttonYes, 'Переслать', 'Переслать сейчас'}
                : {l10n.buttonYes, 'Forward', 'Forward now'},
          );
          expect(confirmAction, findsOneWidget);
          _expectLocalizedQuestion();

          final action = confirm
              ? confirmAction
              : _label(
                  language == 'ru'
                      ? {
                          l10n.buttonCancel,
                          l10n.buttonClose,
                          'Нет',
                          'Не сейчас',
                        }
                      : {
                          l10n.buttonCancel,
                          l10n.buttonClose,
                          'No',
                          'Not now',
                          'Decline',
                          'Dismiss',
                        },
                );
          expect(action, findsOneWidget);
          await tester.tap(action);
          await _frames(tester);
          expect(tester.takeException(), isNull);
          if (confirm) {
            expect(wire.forwardWrites, hasLength(1));
            final write = wire.forwardWrites.single;
            expect(write.field, _ordinaryForwardField);
            expect(write.requestId, _requestId);
            expect(write.recipientIds, [_annaId]);
          } else {
            expect(question, findsNothing, reason: 'The offer was declined');
            expect(wire.forwardWrites, isEmpty);
          }
        });
      },
    );
  }
}

Finder _label(Set<String> labels) {
  final exactLabels = labels.map(RegExp.escape).join('|');
  return find
      .textContaining(RegExp('^(?:$exactLabels)\$'), findRichText: true)
      .hitTestable();
}

void _expectLocalizedQuestion() {
  Map<String, Object?> catalog(String language) =>
      (jsonDecode(File('l10n/app_$language.arb').readAsStringSync()) as Map)
          .cast<String, Object?>();
  final en = catalog('en');
  final ru = catalog('ru');
  final forbidden = RegExp('phantom|фантом|beacon|маяк', caseSensitive: false);
  final placeholder = RegExp(r'\{\w+\}');

  Iterable<String> questions(Object? template) sync* {
    if (template is! String || forbidden.hasMatch(template)) return;
    if (placeholder.allMatches(template).length != 2) return;
    for (final values in const [
      [_requestTitle, _recipient],
      [_recipient, _requestTitle],
    ]) {
      var index = 0;
      yield template.replaceAllMapped(placeholder, (_) => values[index++]);
    }
  }

  expect(
    en.keys.any(
      (key) =>
          questions(en[key]).contains(_enQuestion) &&
          questions(ru[key]).any(_ruQuestion.hasMatch),
    ),
    isTrue,
    reason: 'Both ARB catalogs supply the question with a title and a name',
  );
}

class _Router extends Mock implements StackRouter {}

class _Accounts implements AttentionAccountPort {
  final changes = StreamController<String>.broadcast();

  @override
  Stream<String> get currentAccountChanges => changes.stream;
}

class _Inbox extends Cubit<InboxState> implements InboxCubit {
  _Inbox() : super(const InboxState());

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Profile extends Cubit<ProfileState> implements ProfileCubit {
  _Profile() : super(const ProfileState(profile: _owner));

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<void> _frames(WidgetTester tester) async {
  for (var frame = 0; frame < 12; frame++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> _withActivity(
  WidgetTester tester,
  Locale locale,
  Future<void> Function(_OfferWire) check,
) async {
  final wire = _OfferWire();
  await tester.runAsync(
    () => withRemoteWire(
      {},
      wire.sent,
      (remote) async {
        final accounts = _Accounts();
        final sync = buildTestRealtimeSync();
        final beacons = BeaconRepository(remote, sync.port);
        final forwards = ForwardRepository(remote, beacons, sync.port);
        final forwardCase = buildTestForwardCase(forwards);
        final profiles = buildNoopAttentionActorProfiles();
        final effects = FakeUiEffectPort();
        final logger = Logger('LinkedPersonForwardOfferTest');
        final attention = buildAttentionCase(
          repository: AttentionRepository(remote),
          accounts: accounts,
          realtimeSyncCase: sync.case_,
          blockCase: noopBlockCase(),
          feedSessions: FeedSessionRegistry(),
          logger: logger,
        );
        final stream = UpdatesFeedCubit(
          destinationId: AttentionFeedDestinationId.activityStream,
          attention: attention,
          actorProfiles: profiles,
          setup: NoopInviteAcceptedSetupPort(),
          realtime: sync.case_,
          logger: logger,
        );
        final inboxRepository = FakeInboxRepository();
        final offers = ActivityOffersCubit(
          userId: _owner.id,
          inboxCase: buildTestInboxCase(
            inboxRepository,
            buildTestBeaconThreadsCase(),
          ),
          attentionCase: attention,
          actorProfiles: profiles,
          effects: effects,
        );
        final screen = ScreenCubit(effects);
        final inbox = _Inbox();
        final profile = _Profile();
        GetIt.I.pushNewScope(
          init: (scope) {
            scope
              ..registerSingleton<AttentionCase>(attention)
              ..registerSingleton<ProfileCubit>(profile)
              ..registerSingleton<RemoteApiService>(remote)
              ..registerSingleton<RemoteRequestClient>(remote)
              ..registerSingleton<BeaconRepository>(beacons)
              ..registerSingleton<ForwardRepository>(forwards)
              ..registerSingleton<ForwardCase>(forwardCase)
              ..registerSingleton<PhantomRepositoryPort>(
                PhantomRepository(remote),
              )
              ..registerSingleton<UiEffectPort>(effects);
            registerFakeAppNavigator();
          },
        );
        accounts.changes.add(_owner.id);
        try {
          await offers.loadFirst();
          await stream.refresh();
          expect(offers.state.pageLoadError, isNull, reason: '${wire.sent}');
          expect(stream.state.refreshError, isNull, reason: '${wire.sent}');
          expect(
            wire.sent.map((call) => call.operationName),
            contains('AttentionFeed'),
          );

          await tester.pumpWidget(
            StackRouterScope(
              controller: _Router(),
              stateHash: 0,
              child: MultiBlocProvider(
                providers: [
                  BlocProvider<ActivityOffersCubit>.value(value: offers),
                  BlocProvider<UpdatesFeedCubit>.value(value: stream),
                  BlocProvider<InboxCubit>.value(value: inbox),
                  BlocProvider<ScreenCubit>.value(value: screen),
                ],
                child: MaterialApp(
                  locale: locale,
                  theme: TenturaTheme.light(),
                  localizationsDelegates: L10n.localizationsDelegates,
                  supportedLocales: L10n.supportedLocales,
                  home: const TenturaResponsiveScope(
                    child: Scaffold(body: ActivityStreamView()),
                  ),
                ),
              ),
            ),
          );
          await _frames(tester);
          expect(tester.takeException(), isNull);
          await check(wire);
        } finally {
          await tester.pumpWidget(const SizedBox.shrink());
          await offers.close();
          await stream.close();
          await screen.close();
          await inbox.close();
          await profile.close();
          await attention.dispose();
          await accounts.changes.close();
          await forwards.dispose();
          await beacons.dispose();
          await sync.port.dispose();
          await GetIt.I.popScope();
        }
      },
      responseFor: wire.respond,
      selectResponse: wire.selectResponse,
    ),
  );
}

class _OfferWire {
  final sent = <WireSent>[];
  final forwardWrites =
      <({String field, Object? requestId, Object? recipientIds})>[];
  bool _dismissed = false;

  Future<Map<String, dynamic>> respond(WireSent request) async {
    return switch (request.operationName) {
      'AttentionFeed' => {
        'attentionFeed': {
          '__typename': 'v2_AttentionFeed',
          'summary': {
            '__typename': 'v2_AttentionSummary',
            'unreadTotal': 1,
            'needsYouTotal': 0,
          },
          'page': {
            '__typename': 'v2_AttentionPage',
            'nextCursor': null,
            'items': [if (!_dismissed) _offer],
          },
        },
      },
      'ActivityOffersV2' => {
        'activityOffers': {
          '__typename': 'v2_ActivityOfferPage',
          'totalCount': 0,
          'nextCursor': null,
          'items': <Object?>[],
        },
      },
      'AttentionSurfaceSummary' => {
        'attentionSurfaceSummary': {
          '__typename': 'v2_AttentionSurfaceSummary',
          'unreadTotal': 1,
          'needsYouTotal': 0,
          'myDeskDot': false,
          'myDeskCount': 0,
          'forYouDot': true,
          'forYouSweepEligible': true,
          'forYouReceiptSweepEligible': true,
        },
      },
      'AttentionMarkers' => {
        'attentionMarkers': {'unreadBeaconIds': <String>[]},
      },
      'AttentionLiveObligations' => {'liveObligationBeacons': <String>[]},
      'AttentionMarkSeen' => {
        'attentionMarkSeen': _markSeen(request.variables['ids']),
      },
      _ => request.variables,
    };
  }

  int _markSeen(Object? ids) {
    _dismissed = ids is List && ids.contains('offer-receipt');
    return _dismissed ? 1 : 0;
  }

  Map<String, dynamic> selectResponse(
    String document,
    Map<String, dynamic> data,
  ) {
    final operation = parseString(
      document,
    ).definitions.whereType<OperationDefinitionNode>().single;
    if (operation.type != OperationType.mutation) {
      return {'__typename': 'query_root', ...data};
    }

    final response = <String, dynamic>{'__typename': 'mutation_root'};
    for (final field
        in operation.selectionSet.selections.whereType<FieldNode>()) {
      final fieldName = field.name.value;
      final key = field.alias?.value ?? fieldName;
      switch (fieldName) {
        case _ordinaryForwardField:
          forwardWrites.add((
            field: fieldName,
            requestId: _argument(field, 'id', data),
            recipientIds: _argument(field, 'recipientIds', data),
          ));
          response[key] = {
            '__typename': 'v2_ForwardDeliveryResult',
            'batchId': 'FB000000000001',
            'deliveredRecipientIds': [_annaId],
            'availabilitySkippedRecipientIds': <String>[],
            'alreadyForwardedRecipientIds': <String>[],
            'blockedSkippedRecipientIds': <String>[],
          };
        case _confirmField:
        case _placeholderForwardField:
          forwardWrites.add((
            field: fieldName,
            requestId: null,
            recipientIds: null,
          ));
          response[key] = fieldName == _confirmField
              ? true
              : '/invite/I000000000011?r=$_requestId';
        default:
          response[key] = data[key];
      }
    }
    return response;
  }

  Object? _argument(
    FieldNode field,
    String name,
    Map<String, dynamic> variables,
  ) => _value(
    field.arguments
        .where((argument) => argument.name.value == name)
        .firstOrNull
        ?.value,
    variables,
  );

  Object? _value(ValueNode? value, Map<String, dynamic> variables) =>
      switch (value) {
        VariableNode(:final name) => variables[name.value],
        StringValueNode(:final value) => value,
        ListValueNode(:final values) => [
          for (final item in values) _value(item, variables),
        ],
        _ => null,
      };
}

Map<String, Object?> get _offer => {
  '__typename': 'v2_AttentionReceipt',
  'id': 'offer-receipt',
  'category': 'connections',
  'kind': 'coordinationChanged',
  'priority': 'normal',
  'title': 'Forward request',
  'body': _enQuestion,
  'actionUrl': '/#/view?id=$_requestId',
  'createdAt': '2026-11-26T12:00:00Z',
  'collapsedCount': 1,
  'beaconId': _requestId,
  'beaconTitle': _requestTitle,
  'beaconKind': 0,
  'actorUserId': _owner.id,
  'sourceEventKey': 'requestForwardOffered:$_mergeId:$_offerId',
  'destinationKind': 'beacon',
  'targetEntityId': _offerId,
  'presentationKey': 'request_forward_offered',
  'presentationPayloadJson': jsonEncode({
    'mergeId': _mergeId,
    'displayName': _recipient,
    'recipientId': _annaId,
  }),
  'requiresAction': false,
  'surface': 'activity',
  'itemKind': 'receipt',
  'eventsPreview': <Object?>[],
};
