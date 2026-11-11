// The production route wrapper, Ferry mappers, repositories and cubits stay
// in path. Only HTTP and the invitation repository are replaced.
import 'dart:async';
import 'dart:convert';

import 'package:ferry/ferry.dart';
import 'package:logging/logging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mockito/mockito.dart';
import 'package:tentura_root/domain/enums.dart';

import 'package:tentura/app/router/root_router.dart';
import 'package:tentura/data/repository/clipboard_image_repository.dart';
import 'package:tentura/data/repository/image_repository.dart';
import 'package:tentura/data/service/remote_api_client/build_client.dart';
import 'package:tentura/data/service/remote_api_client/remote_request_client.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/invitation_entity.dart';
import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/domain/use_case/beacon_create_case.dart';
import 'package:tentura/domain/use_case/post_publish_case.dart';
import 'package:tentura/features/beacon/data/repository/beacon_repository.dart';
import 'package:tentura/features/beacon/data/repository/post_publish_repository.dart';
import 'package:tentura/features/beacon_create/ui/bloc/beacon_create_cubit.dart';
import 'package:tentura/features/beacon_create/ui/screen/post_create_screen.dart';
import 'package:tentura/features/context/ui/bloc/context_cubit.dart';
import 'package:tentura/features/forward/data/repository/forward_repository.dart';
import 'package:tentura/features/forward/domain/use_case/forward_case.dart';
import 'package:tentura/features/forward/ui/bloc/forward_cubit.dart';
import 'package:tentura/features/forward/ui/widget/forward_invite_bar.dart';
import 'package:tentura/features/forward/ui/widget/forward_recipient_picker.dart';
import 'package:tentura/features/invitation/data/repository/invitation_repository.dart';
import 'package:tentura/features/profile/ui/bloc/profile_cubit.dart';
import 'package:tentura/ui/bloc/presence_cubit.dart';
import 'package:tentura/ui/bloc/screen_cubit.dart';
import 'package:tentura/ui/dialog/share_code_dialog.dart';
import 'package:tentura/ui/effect/ui_effect.dart';
import 'package:tentura/ui/effect/ui_effect_port.dart';
import 'package:tentura/ui/effect/ui_effect_handler.dart';
import 'package:tentura/ui/utils/ui_utils.dart' show snackbarKey;
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/test_ids.dart';

import '../../support/post_draft_wire.dart';
import '../../support/test_forward_case.dart';
import '../../support/fake_app_navigator.dart';
import '../../support/test_realtime_sync.dart';
import '../../ui/effect/fake_ui_effect_port.dart';
import '../beacon_create/fake_beacon_ports.dart';

const _postId = postDraftWireDraftId;
const _person = 'Urecipient001';

class _Remote implements RemoteRequestClient {
  _Remote(this.client);
  final Client client;
  @override
  Stream<OperationResponse<T, V>> request<T, V>(
    OperationRequest<T, V> request, [
    Stream<OperationResponse<T, V>> Function(OperationRequest<T, V>)? forward,
  ]) => client.request(request);
}

class _Profile extends Mock implements ProfileCubit {
  @override
  ProfileState get state => const ProfileState(
    profile: Profile(id: 'Uviewer000001', displayName: 'Олег'),
  );
  @override
  Stream<ProfileState> get stream => const Stream.empty();
}

class _Presence extends Mock implements PresenceCubit {
  @override
  Map<String, UserPresenceStatus> get state => const {};
  @override
  Stream<Map<String, UserPresenceStatus>> get stream => const Stream.empty();
}

class _Context extends Mock implements ContextCubit {
  @override
  ContextState get state => const ContextState();
  @override
  Stream<ContextState> get stream => const Stream.empty();
}

class _Router extends Fake implements StackRouter {
  final opened = <PageRouteInfo>[];
  @override
  void pop<T extends Object?>([T? result]) {}
  @override
  String get currentUrl => '/post/new';
  @override
  void markUrlStateForReplace() {}
  @override
  PagelessRoutesObserver get pagelessRoutesObserver => PagelessRoutesObserver();
  @override
  bool canPop({
    bool ignoreChildRoutes = false,
    bool ignoreParentRoutes = false,
    bool ignorePagelessRoutes = false,
  }) => false;
  @override
  void popUntilRouteWithName(String name, {bool scoped = true}) {}
  @override
  Future<T?> push<T extends Object?>(
    PageRouteInfo route, {
    OnNavigationFailure? onFailure,
  }) async {
    opened.add(route);
    return null;
  }

  @override
  Future<T?> popAndPush<T extends Object?, TO extends Object?>(
    PageRouteInfo route, {
    TO? result,
    OnNavigationFailure? onFailure,
  }) async {
    opened.add(route);
    return null;
  }
}

class _Invitations extends Fake implements InvitationRepository {
  final created = <String?>[];
  @override
  Stream<void> get changes => const Stream.empty();
  @override
  Future<InvitationsFetchResult> fetchMine({
    int pendingOffset = 0,
    int pendingLimit = 0,
    int acceptedOffset = 0,
    int acceptedLimit = 0,
  }) async => (
    pending: <InvitationEntity>[],
    accepted: <InvitationEntity>[],
    pendingCount: 0,
  );
  @override
  Future<int> fetchTtlHours() async => 48;
  @override
  Future<InvitationFetchByIdResult?> fetchById(String id) async => null;
  @override
  Future<InvitationEntity> create({
    required String addresseeName,
    String? beaconId,
  }) async {
    created.add(beaconId);
    return InvitationEntity(
      id: 'Iabc123def456',
      beaconId: beaconId,
      createdAt: DateTime.utc(2026, 11, 11),
      updatedAt: DateTime.utc(2026, 11, 11),
    );
  }

  @override
  Future<void> deleteById(String id) async {}
}

class _Wire extends PostDraftWire {
  bool live = false;
  bool noContacts = false;
  bool failCreate = false;
  bool failPublish = false;
  Completer<void>? createHold;

  @override
  Future<http.Response> respond(http.Request request) async {
    final payload = jsonDecode(request.body) as Map<String, dynamic>;
    final name = payload['operationName'];
    if (name == 'BeaconCreate') await createHold?.future;
    if ((name == 'BeaconCreate' && failCreate) ||
        (name == 'PostPublish' && failPublish)) {
      sent.add((
        operationName: name as String,
        variables: (payload['variables'] as Map).cast<String, dynamic>(),
      ));
      return http.Response(
        jsonEncode({
          'data': null,
          'errors': [
            {'message': 'Connection unavailable'},
          ],
        }),
        200,
        headers: {'content-type': 'application/json'},
      );
    }
    if (name == 'BeaconInvolvementData' ||
        (name == 'ForwardCandidatesFetch' && noContacts)) {
      sent.add((
        operationName: name as String,
        variables: (payload['variables'] as Map).cast<String, dynamic>(),
      ));
      return http.Response(
        jsonEncode({
          'data': name == 'ForwardCandidatesFetch'
              ? {'forwardCandidates': <Object>[]}
              : {
                  'beaconInvolvement': {
                    '__typename': 'v2_BeaconInvolvement',
                    for (final field in [
                      'forwardedToIds',
                      'helpOfferedIds',
                      'withdrawnIds',
                      'declinedOfferIds',
                      'rejectedIds',
                      'watchingIds',
                      'onwardForwarderIds',
                      'myForwardedRecipients',
                    ])
                      field: <Object>[],
                  },
                },
        }),
        200,
        headers: {'content-type': 'application/json'},
      );
    }
    final response = await super.respond(request);
    if (name == 'PostPublish') live = true;
    if ((name == 'BeaconFetchById' && live) || name == 'ForwardBeacon') {
      final result = jsonDecode(response.body) as Map<String, dynamic>;
      final data = result['data'] as Map<String, dynamic>;
      if (name == 'BeaconFetchById') {
        (data['beacon_by_pk'] as Map<String, dynamic>).addAll({
          'status': 0,
          'description': '',
          'post_lifetime_hours': null,
          'post_root_message_id': 'Mroot00000001',
          'viewer_can_forward': true,
          'expires_at': DateTime.now()
              .toUtc()
              .add(Duration(hours: lifetimeHours))
              .toIso8601String(),
        });
      } else {
        (data['beaconForward']
                as Map<String, dynamic>)['deliveredRecipientIds'] =
            (payload['variables'] as Map)['recipientIds'];
      }
      return http.Response(
        jsonEncode(result),
        200,
        headers: {'content-type': 'application/json'},
      );
    }
    return response;
  }
}

class _Harness {
  _Harness(this.wire, this.invitations, this.router, this.effects);
  final _Wire wire;
  final _Invitations invitations;
  final _Router router;
  final FakeUiEffectPort effects;
  BeaconCreateCubit create(WidgetTester tester) =>
      tester.element(find.byType(PostCreateScreen)).read<BeaconCreateCubit>();
  ForwardCubit forward(WidgetTester tester) =>
      tester.element(find.byType(ForwardRecipientPicker)).read<ForwardCubit>();
}

Future<void> _frames(WidgetTester tester) async {
  for (var i = 0; i < 12; i++) {
    await tester.pump(const Duration(milliseconds: 50));
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}

Future<void> _withComposer(
  WidgetTester tester,
  Locale locale,
  Size size,
  Future<void> Function(_Harness h) body, {
  required _Wire wire,
  String forwardToUserId = '',
  Set<String> initialRecipientIds = const {},
  String draftId = '',
}) async {
  tester.view
    ..physicalSize = size
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.runAsync(
    () => http.runWithClient(() async {
      final server = wire;
      final effects = FakeUiEffectPort();
      final invitations = _Invitations();
      final router = _Router();
      final remote = _Remote(
        await buildClient(
          params: (
            apiEndpointUrl: 'https://draft.test/api/v1/graphql',
            apiEndpointUrlV2: 'https://draft.test/api/v2/graphql',
            userAgent: 'post-picker-test',
            requestTimeout: const Duration(seconds: 3),
          ),
          getToken: () async => 'test-token',
        ),
      );
      final sync = buildTestRealtimeSync();
      final beacons = BeaconRepository(remote, sync.port);
      final forwards = ForwardRepository(remote, beacons, sync.port);
      await GetIt.I.reset();
      registerFakeAppNavigator();
      GetIt.I
        ..registerSingleton<Logger>(Logger('post-picker-test'))
        ..registerSingleton<UiEffectPort>(effects)
        ..registerSingleton<ImageRepository>(ImageRepository())
        ..registerSingleton<ClipboardImageRepository>(
          ClipboardImageRepository(),
        )
        ..registerSingleton<InvitationRepository>(invitations)
        ..registerSingleton<BeaconCreateCase>(
          BeaconCreateCase(beacons, FakeBeaconImagePort()),
        )
        ..registerSingleton<PostPublishCase>(
          PostPublishCase(PostPublishRepository(remote)),
        )
        ..registerSingleton<ForwardCase>(buildTestForwardCase(forwards));
      try {
        await tester.pumpWidget(
          MaterialApp(
            scaffoldMessengerKey: snackbarKey,
            builder: (_, child) =>
                UiEffectHandler(effects: effects, child: child!),
            locale: locale,
            localizationsDelegates: L10n.localizationsDelegates,
            supportedLocales: L10n.supportedLocales,
            theme: TenturaTheme.light(),
            home: RouterScope(
              controller: router,
              stateHash: 0,
              inheritableObserversBuilder: () => const [],
              child: StackRouterScope(
                controller: router,
                stateHash: 0,
                child: TenturaResponsiveScope(
                  child: MultiBlocProvider(
                    providers: [
                      BlocProvider<ProfileCubit>.value(value: _Profile()),
                      BlocProvider<PresenceCubit>.value(value: _Presence()),
                      BlocProvider<ContextCubit>.value(value: _Context()),
                      BlocProvider<ScreenCubit>(
                        create: (_) => ScreenCubit(effects),
                      ),
                    ],
                    child: Builder(
                      builder: (context) => PostCreateScreen(
                        draftId: draftId,
                        forwardToUserId: forwardToUserId,
                        initialRecipientIds: initialRecipientIds,
                      ).wrappedRoute(context),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await _frames(tester);
        await body(
          _Harness(server, invitations, router, effects),
        ).timeout(const Duration(seconds: 20));
      } finally {
        if (server.createHold case final hold? when !hold.isCompleted) {
          hold.complete();
        }
        await tester.pumpWidget(const SizedBox.shrink());
        await _frames(tester);
        await forwards.dispose();
        await beacons.dispose();
        await sync.port.dispose();
        await remote.client.dispose();
        await GetIt.I.reset();
      }
    }, () => MockClient((request) => wire.respond(request))),
  );
}

// A RenderFlex overflow is reported as a FlutterError; take it so the test
// fails naming the layout instead of passing silently.
void _expectNoLayoutOverflow(WidgetTester tester, String stage) {
  final error = tester.takeException();
  expect(
    error,
    isNull,
    reason: 'No layout overflow or other framework error $stage',
  );
}

Future<void> _typeAndNext(
  WidgetTester tester,
  _Harness h, {
  bool save = true,
}) async {
  await tester.enterText(
    find.byKey(PostCreateScreen.textFieldKey),
    'Hello friends',
  );
  if (save) {
    await h.create(tester).flushPostDraft().timeout(const Duration(seconds: 3));
    expect(
      h.create(tester).state.draftId,
      _postId,
      reason:
          'Fixture sanity: real HTTP response must map into the draft cubit',
    );
    expect(h.wire.calls('BeaconCreate'), hasLength(1));
    expect(h.wire.calls('PostUpdateDraft'), isNotEmpty);
  }
  await _frames(tester);
  await tester.tap(find.byKey(PostCreateScreen.nextButtonKey));
  await _frames(tester);
}

Future<void> _pick(WidgetTester tester, _Harness h) async {
  expect(
    find.text('Мария'),
    findsWidgets,
    reason: 'The real ForwardCandidatesFetch response must reach the picker',
  );
  await tester.tap(find.text('Мария').first);
  await _frames(tester);
  expect(h.forward(tester).state.selectedIds, {_person});
}

Future<void> _invite(
  WidgetTester tester, {
  required L10n l10n,
  bool empty = false,
  bool request = false,
}) async {
  final action = empty
      ? find.text(l10n.emptyInviteSomeoneAction)
      : find.byKey(TestIds.key(TestIds.forwardInviteNewPerson));
  expect(action, findsOneWidget);
  await tester.ensureVisible(action);
  await tester.tap(action);
  await _frames(tester);
  _expectPublishPrompt(subject: request ? 'Request draft' : 'Post draft');
}

// The invite chip stays on the bar after a pick; tap it like a user.
Future<void> _inviteWithContactPicked(WidgetTester tester) async {
  final chip = find.byKey(TestIds.key(TestIds.forwardInviteNewPerson));
  expect(
    chip,
    findsOneWidget,
    reason: 'Invite new person must stay tappable once a contact is picked',
  );
  expect(
    tester.widget<ForwardInviteBar>(find.byType(ForwardInviteBar)).hasSelection,
    isTrue,
  );
  await tester.ensureVisible(chip);
  await tester.tap(chip);
  await _frames(tester);
  _expectPublishPrompt(subject: 'Post draft');
}

void _expectPublishPrompt({required String subject}) {
  expect(
    find.byType(TenturaConfirmDialog),
    findsOneWidget,
    reason: 'Inviting from a $subject must first ask to publish it',
  );
  expect(find.byType(ShareCodeDialog), findsNothing);
}

Future<void> _cancelPrompt(WidgetTester tester) async {
  final context = tester.element(find.byType(TenturaConfirmDialog));
  await tester.tap(
    find.text(MaterialLocalizations.of(context).cancelButtonLabel),
  );
  await _frames(tester);
}

void _postWording(WidgetTester tester, Locale locale, L10n l10n) {
  final dialog = tester.widget<TenturaConfirmDialog>(
    find.byType(TenturaConfirmDialog),
  );
  // A whole word «пост»/«post» (not «постоянный»), never «запрос»/«request».
  final post = RegExp(
    locale.languageCode == 'ru'
        ? r'(^|[^а-яё])пост(а|у|ом|е|ы|ов)?([^а-яё]|$)'
        : r'\bposts?\b',
  );
  final request = locale.languageCode == 'ru' ? 'запрос' : 'request';
  for (final text in [dialog.title, dialog.content]) {
    expect(text.toLowerCase(), matches(post));
    expect(text.toLowerCase(), isNot(contains(request)));
  }
  expect(
    dialog.title,
    isNot(l10n.beaconCreateInviteMakeLiveConfirmTitle),
    reason: 'The Post title must be its own copy, not the Request one',
  );
  expect(
    dialog.content,
    isNot(l10n.beaconCreateInviteMakeLiveConfirmBody),
    reason: 'The Post body must be its own copy, not the Request one',
  );
  expect(find.text(l10n.beaconMakeLiveWithoutSending), findsOneWidget);
}

// Check the sibling Request surface after cancelling the Post dialog. Sharing
// the dialog must not change the Request's vocabulary when Post copy is added.
Future<void> _requestPrompt(
  WidgetTester tester,
  Locale locale,
  L10n l10n,
) async {
  final effects = FakeUiEffectPort();
  final create = BeaconCreateCubit(
    beaconCreateCase: fakeBeaconCreateCase(),
    effects: effects,
  );
  create.emit(create.state.copyWith(draftId: 'Brequest001'));
  final forward = ForwardCubit(
    beaconId: 'Brequest001',
    embedded: true,
    debugSkipInitialLoad: true,
    effects: effects,
    debugInitialState: ForwardState(
      beaconId: 'Brequest001',
      beacon: Beacon.empty.copyWith(id: 'Brequest001'),
      candidatesLoad: const ForwardCandidatesEmpty(),
    ),
  );
  try {
    await tester.pumpWidget(
      MaterialApp(
        locale: locale,
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        theme: TenturaTheme.light(),
        home: TenturaResponsiveScope(
          child: MultiBlocProvider(
            providers: [
              BlocProvider<BeaconCreateCubit>.value(value: create),
              BlocProvider<ForwardCubit>.value(value: forward),
              BlocProvider<ProfileCubit>.value(value: _Profile()),
              BlocProvider<ContextCubit>.value(value: _Context()),
            ],
            child: const Scaffold(
              body: ForwardRecipientPicker(
                beaconId: 'Brequest001',
                embedded: true,
              ),
            ),
          ),
        ),
      ),
    );
    await _frames(tester);
    await _invite(tester, l10n: l10n, empty: true, request: true);
    final dialog = tester.widget<TenturaConfirmDialog>(
      find.byType(TenturaConfirmDialog),
    );
    final word = locale.languageCode == 'ru' ? 'запрос' : 'request';
    for (final text in [dialog.title, dialog.content]) {
      expect(text.toLowerCase(), contains(word));
    }
    expect(dialog.title, l10n.beaconCreateInviteMakeLiveConfirmTitle);
    expect(dialog.content, l10n.beaconCreateInviteMakeLiveConfirmBody);
    final context = tester.element(find.byType(TenturaConfirmDialog));
    await tester.tap(
      find.text(MaterialLocalizations.of(context).cancelButtonLabel),
    );
    await _frames(tester);
    _expectNoLayoutOverflow(tester, 'at the end of the flow');
  } finally {
    await tester.pumpWidget(const SizedBox.shrink());
    await create.close();
    await forward.close();
  }
}

void main() {
  for (final layout in [
    (locale: const Locale('ru'), size: const Size(375, 667)),
    (locale: const Locale('en'), size: const Size(1280, 800)),
  ]) {
    final locale = layout.locale;
    final l10n = lookupL10n(locale);
    final tag =
        '${locale.languageCode} ${layout.size.width.toInt()}×${layout.size.height.toInt()}';
    Future<void> run(
      WidgetTester tester,
      Future<void> Function(_Harness) body, {
      _Wire? wire,
      String forwardToUserId = '',
      Set<String> initialRecipientIds = const {},
      String draftId = '',
    }) => _withComposer(
      tester,
      locale,
      layout.size,
      body,
      wire: wire ?? _Wire(),
      forwardToUserId: forwardToUserId,
      initialRecipientIds: initialRecipientIds,
      draftId: draftId,
    );

    testWidgets(
      '$tag recipients wait for the saved Post before showing the picker',
      (tester) async {
        final hold = Completer<void>();
        final wire = _Wire()..createHold = hold;
        await run(tester, (h) async {
          await _typeAndNext(tester, h, save: false);
          expect(find.text(l10n.beaconRecipientsPreparing), findsOneWidget);
          expect(find.byType(TenturaCircularProgress), findsWidgets);
          expect(find.byType(ForwardRecipientPicker), findsNothing);
          hold.complete();
          await tester.pump();
          await h
              .create(tester)
              .flushPostDraft()
              .timeout(const Duration(seconds: 3));
          await _frames(tester);
          expect(find.byType(ForwardRecipientPicker), findsOneWidget);
          expect(
            tester
                .widget<ForwardRecipientPicker>(
                  find.byType(ForwardRecipientPicker),
                )
                .beaconId,
            _postId,
          );
          _expectNoLayoutOverflow(tester, 'at the end of the flow');
        }, wire: wire);
      },
    );

    testWidgets('$tag recipients retry a failed Post draft creation', (
      tester,
    ) async {
      final wire = _Wire()..failCreate = true;
      await run(tester, (h) async {
        await _typeAndNext(tester, h, save: false);
        await h
            .create(tester)
            .flushPostDraft()
            .timeout(const Duration(seconds: 3));
        await _frames(tester);
        expect(find.text(l10n.beaconRecipientsPrepareFailed), findsOneWidget);
        expect(find.byType(ForwardRecipientPicker), findsNothing);
        wire.failCreate = false;
        await tester.tap(find.text(l10n.myWorkRetry));
        await _frames(tester);
        expect(h.create(tester).state.draftId, _postId);
        expect(
          tester
              .widget<ForwardRecipientPicker>(
                find.byType(ForwardRecipientPicker),
              )
              .beaconId,
          _postId,
        );
        _expectNoLayoutOverflow(tester, 'at the end of the flow');
      }, wire: wire);
    });

    testWidgets(
      '$tag saved Post keeps profile and map recipients when binding the picker',
      (tester) async {
        await run(
          tester,
          (h) async {
            await _typeAndNext(tester, h);
            final picker = tester.widget<ForwardRecipientPicker>(
              find.byType(ForwardRecipientPicker),
            );
            expect(picker.beaconId, _postId);
            expect(picker.isLive, isFalse);
            expect(h.forward(tester).state.beaconId, _postId);
            expect(h.forward(tester).state.selectedIds, {
              _person,
              'Urecipient002',
            });
            expect(find.text(l10n.postCreateSendToCount(2)), findsOneWidget);
            _expectNoLayoutOverflow(tester, 'at the end of the flow');
          },
          forwardToUserId: _person,
          initialRecipientIds: {'Urecipient002'},
        );
      },
    );

    testWidgets(
      '$tag cancelling the Post publication prompt keeps the draft unpublished and the contact picked',
      (tester) async {
        await run(tester, (h) async {
          await _typeAndNext(tester, h);
          await _pick(tester, h);
          await _inviteWithContactPicked(tester);
          _postWording(tester, locale, l10n);
          await _cancelPrompt(tester);
          expect(h.wire.calls('PostPublish'), isEmpty);
          expect(h.wire.calls('ForwardBeacon'), isEmpty);
          expect(h.invitations.created, isEmpty);
          expect(h.create(tester).state.isLive, isFalse);
          expect(find.byType(TenturaConfirmDialog), findsNothing);
          expect(find.byType(ShareCodeDialog), findsNothing);
          expect(find.byType(ForwardRecipientPicker), findsOneWidget);
          expect(h.forward(tester).state.selectedIds, {_person});
          _expectNoLayoutOverflow(tester, 'at the end of the flow');
        });
      },
    );

    testWidgets(
      '$tag the Request invite confirm keeps request wording',
      (tester) async {
        tester.view
          ..physicalSize = layout.size
          ..devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        GetIt.I.registerSingleton<InvitationRepository>(_Invitations());
        addTearDown(GetIt.I.reset);
        await tester.runAsync(() => _requestPrompt(tester, locale, l10n));
      },
    );

    testWidgets(
      '$tag inviting with a contact picked publishes without delivery then Send forwards the live Post to the contact',
      (tester) async {
        await run(tester, (h) async {
          await tester.enterText(
            find.byKey(PostCreateScreen.textFieldKey),
            'Hello friends',
          );
          final lifetime = find.text(l10n.postCreateLifetime24h);
          await tester.ensureVisible(lifetime);
          await tester.tap(lifetime);
          await _frames(tester);
          // The chosen lifetime is shown before anything is published.
          expect(
            find.text(
              l10n.postCreateReplyLifetimeHint(l10n.postCreateLifetime24h),
            ),
            findsOneWidget,
          );
          await _typeAndNext(tester, h);
          expect(h.create(tester).state.postLifetimeHours, 24);
          await _pick(tester, h);
          _expectNoLayoutOverflow(tester, 'after picking a contact');
          await _inviteWithContactPicked(tester);
          _postWording(tester, locale, l10n);
          _expectNoLayoutOverflow(tester, 'with the publish prompt open');
          await tester.tap(find.text(l10n.beaconMakeLiveWithoutSending));
          await _frames(tester);
          final published = h.wire.calls('PostPublish');
          expect(published, hasLength(1));
          expect(published.single.variables['id'], _postId);
          expect(published.single.variables['recipientIds'], isEmpty);
          expect(published.single.variables['lifetimeHours'], 24);
          expect(h.wire.calls('ForwardBeacon'), isEmpty);
          expect(h.create(tester).state.isLive, isTrue);
          expect(h.invitations.created, [_postId]);
          expect(find.byType(ShareCodeDialog), findsOneWidget);
          _expectNoLayoutOverflow(tester, 'with the invite dialog open');
          expect(
            tester
                .widget<ForwardRecipientPicker>(
                  find.byType(ForwardRecipientPicker),
                )
                .isLive,
            isTrue,
          );
          // Dismiss only the share dialog, retaining the live Post composer.
          Navigator.of(tester.element(find.byType(ShareCodeDialog))).pop(true);
          await _frames(tester);
          expect(
            h.forward(tester).state.selectedIds,
            {_person},
            reason: 'Publishing without delivery must keep the picked contact',
          );
          await tester.tap(find.text(l10n.postCreateSendToCount(1)));
          await _frames(tester);
          expect(h.wire.calls('PostPublish'), hasLength(1));
          final forwarded = h.wire.calls('ForwardBeacon');
          expect(forwarded, hasLength(1));
          expect(forwarded.single.variables['beaconId'], _postId);
          expect(forwarded.single.variables['recipientIds'], [_person]);
          expect(h.router.opened, hasLength(1));
          expect(h.router.opened.single, isA<BeaconViewRoute>());
          expect(
            (h.router.opened.single as BeaconViewRoute).args!.id,
            _postId,
          );
          _expectNoLayoutOverflow(tester, 'at the end of the flow');
        });
      },
    );

    testWidgets(
      '$tag a saved Post draft offers an enabled Invite new person action that asks to publish',
      (tester) async {
        await run(tester, (h) async {
          await _typeAndNext(tester, h);
          final action = find.byKey(
            TestIds.key(TestIds.forwardInviteNewPerson),
          );
          expect(
            action,
            findsOneWidget,
            reason: 'A saved Post draft must offer «Invite new person»',
          );
          expect(
            tester.widget<TenturaCommandButton>(action).onPressed,
            isNotNull,
            reason: 'The action must be enabled, not greyed out',
          );
          _expectNoLayoutOverflow(tester, 'on the Post recipients step');
          await _invite(tester, l10n: l10n);
          _postWording(tester, locale, l10n);
          _expectNoLayoutOverflow(tester, 'with the publish prompt open');
          await _cancelPrompt(tester);
          expect(h.wire.calls('PostPublish'), isEmpty);
          expect(h.invitations.created, isEmpty);
          expect(h.create(tester).state.isLive, isFalse);
          expect(find.byType(ShareCodeDialog), findsNothing);
          expect(action, findsOneWidget);
          _expectNoLayoutOverflow(tester, 'after cancelling the prompt');
        });
      },
    );

    testWidgets(
      '$tag tapping Invite new person publishes the Post without delivery, invites into it, then Send forwards to a contact picked afterwards',
      (tester) async {
        await run(tester, (h) async {
          await _typeAndNext(tester, h);
          await _invite(tester, l10n: l10n);
          _postWording(tester, locale, l10n);
          await tester.tap(find.text(l10n.beaconMakeLiveWithoutSending));
          await _frames(tester);
          final published = h.wire.calls('PostPublish');
          expect(published, hasLength(1));
          expect(published.single.variables['id'], _postId);
          expect(published.single.variables['recipientIds'], isEmpty);
          expect(h.invitations.created, [_postId]);
          expect(find.byType(ShareCodeDialog), findsOneWidget);
          _expectNoLayoutOverflow(tester, 'with the invite dialog open');
          Navigator.of(tester.element(find.byType(ShareCodeDialog))).pop(true);
          await _frames(tester);
          await _pick(tester, h);
          _expectNoLayoutOverflow(tester, 'after picking a contact');
          await tester.tap(find.text(l10n.postCreateSendToCount(1)));
          await _frames(tester);
          expect(h.wire.calls('PostPublish'), hasLength(1));
          final forwarded = h.wire.calls('ForwardBeacon');
          expect(forwarded, hasLength(1));
          expect(forwarded.single.variables['beaconId'], _postId);
          expect(forwarded.single.variables['recipientIds'], [_person]);
          expect(h.router.opened, hasLength(1));
          expect(h.router.opened.single, isA<BeaconViewRoute>());
          _expectNoLayoutOverflow(tester, 'after Send');
        });
      },
    );

    testWidgets(
      '$tag a reopened Post draft shows its saved lifetime and publishes with it',
      (tester) async {
        await run(
          tester,
          (h) async {
            await _frames(tester);
            expect(
              h.create(tester).state.draftId,
              _postId,
              reason: 'The saved draft must load from the real server response',
            );
            expect(
              find.text(
                l10n.postCreateReplyLifetimeHint(l10n.postCreateLifetime24h),
              ),
              findsOneWidget,
              reason: 'The saved lifetime must show before publishing',
            );
            await tester.tap(find.byKey(PostCreateScreen.nextButtonKey));
            await _frames(tester);
            expect(
              tester
                  .widget<ForwardRecipientPicker>(
                    find.byType(ForwardRecipientPicker),
                  )
                  .beaconId,
              _postId,
            );
            await _invite(tester, l10n: l10n);
            await tester.tap(find.text(l10n.beaconMakeLiveWithoutSending));
            await _frames(tester);
            expect(h.wire.calls('BeaconCreate'), isEmpty);
            final published = h.wire.calls('PostPublish');
            expect(published, hasLength(1));
            expect(published.single.variables['id'], _postId);
            expect(published.single.variables['lifetimeHours'], 24);
            expect(h.invitations.created, [_postId]);
            _expectNoLayoutOverflow(
              tester,
              'after publishing a reopened draft',
            );
          },
          wire: _Wire()..lifetimeHours = 24,
          draftId: _postId,
        );
      },
    );

    testWidgets(
      '$tag an empty contact list invites into the Post after publication',
      (tester) async {
        await run(tester, (h) async {
          await _typeAndNext(tester, h);
          expect(find.text(l10n.forwardEmptyNoContactsTitle), findsOneWidget);
          await _invite(tester, l10n: l10n, empty: true);
          _postWording(tester, locale, l10n);
          expect(h.invitations.created, isEmpty);
          await tester.tap(find.text(l10n.beaconMakeLiveWithoutSending));
          await _frames(tester);
          expect(h.wire.calls('PostPublish'), hasLength(1));
          expect(
            h.wire.calls('PostPublish').single.variables['recipientIds'],
            isEmpty,
          );
          expect(h.invitations.created, [_postId]);
          expect(find.byType(ShareCodeDialog), findsOneWidget);
          expect(find.text(l10n.labelInvitationCode), findsNothing);
          _expectNoLayoutOverflow(tester, 'at the end of the flow');
        }, wire: _Wire()..noContacts = true);
      },
    );

    testWidgets(
      '$tag failed publication keeps the Post draft, the picked contact and creates no invitation',
      (tester) async {
        await run(tester, (h) async {
          await _typeAndNext(tester, h);
          await _pick(tester, h);
          await _inviteWithContactPicked(tester);
          await tester.tap(find.text(l10n.beaconMakeLiveWithoutSending));
          await _frames(tester);
          expect(h.wire.calls('PostPublish'), hasLength(1));
          expect(h.invitations.created, isEmpty);
          expect(find.byType(ShareCodeDialog), findsNothing);
          expect(h.create(tester).state.isLive, isFalse);
          expect(find.byType(ForwardRecipientPicker), findsOneWidget);
          expect(h.forward(tester).state.selectedIds, {_person});
          final errors = h.effects.emitted.whereType<ShowError>();
          expect(errors, hasLength(1));
          expect(
            errors.single.error.toString(),
            contains('Connection unavailable'),
          );
          expect(find.byType(SnackBar), findsOneWidget);
          _expectNoLayoutOverflow(tester, 'at the end of the flow');
        }, wire: _Wire()..failPublish = true);
      },
    );
  }
}
