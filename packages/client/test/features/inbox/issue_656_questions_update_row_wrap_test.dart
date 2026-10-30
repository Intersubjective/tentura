import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';
import 'package:mockito/mockito.dart';

import 'package:tentura/app/router/root_router.dart';
import 'package:tentura/data/repository/mock/client_repository_mocks.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/attention/entity/attention_feed.dart';
import 'package:tentura/domain/attention/entity/attention_receipt.dart';
import 'package:tentura/domain/attention/entity/my_work_beacon_attention.dart';
import 'package:tentura/domain/attention/offer_accepted_dismissals.dart';
import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/beacon/data/repository/beacon_repository.dart';
import 'package:tentura/features/closure/data/repository/closure_repository.dart';
import 'package:tentura/features/inbox/ui/widget/attention_mini_card.dart';
import 'package:tentura/features/my_work/ui/bloc/my_work_cubit.dart';
import 'package:tentura/features/my_work/ui/widget/my_work_cards.dart';
import 'package:tentura/features/profile/ui/bloc/profile_cubit.dart';
import 'package:tentura/ui/bloc/screen_cubit.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/widget/relative_timestamp_ticker.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';

import '../my_work/my_work_test_support.dart';

const _viewerId = 'alice';
const _beaconId = 'request-1';
final _now = DateTime(2026, 10, 30, 12);

final class _TestProfileCubit extends Mock implements ProfileCubit {
  @override
  ProfileState get state => const ProfileState(
    profile: Profile(id: _viewerId, displayName: 'Alice'),
  );

  @override
  Stream<ProfileState> get stream =>
      Stream<ProfileState>.value(state).asBroadcastStream();
}

final class _StubRouter extends Mock implements StackRouter {}

final class _NoDismissals implements OfferAcceptedDismissalPort {
  @override
  Future<Set<String>> load({required String viewerId}) async => {};

  @override
  Future<Set<String>> dismiss({
    required String viewerId,
    required String beaconId,
  }) async => {};
}

AttentionReceipt _questionsMessage(String asker) => AttentionReceipt(
  id: 'question-$asker',
  category: 'room',
  kind: 'roomActivityLowPriority',
  priority: 'normal',
  title: asker,
  body: 'New message in Questions',
  actionUrl: '/#/beacon/lobby/$_beaconId',
  createdAt: _now,
  collapsedCount: 1,
  presentationKey: 'room_message_posted',
  presentationPayloadJson: jsonEncode({
    'eventType': 'roomMessagePosted',
    'beaconId': _beaconId,
    'coordinationItemId': 'questions-1',
    'actorUserId': asker.toLowerCase(),
    'actorName': asker,
  }),
  surface: AttentionSurface.myWork,
  beaconId: _beaconId,
  actorUserId: asker.toLowerCase(),
  targetEntityId: 'message-$asker',
  destinationKind: 'beacon_room_message',
  coordinationItemId: 'questions-1',
);

Future<void> _pumpAuthorCard(WidgetTester tester) async {
  final beacon = Beacon.empty.copyWith(
    id: _beaconId,
    title: 'Move the garden shed',
    updatedAt: DateTime(2026, 10, 28),
    status: BeaconStatus.open,
    author: const Profile(id: _viewerId, displayName: 'Alice'),
  );
  final repo = FakeMyWorkRepository()
    ..initResult = (
      authoredNonArchived: [beacon],
      helpOfferedNonArchived: const [],
      obligationBeacons: const [],
      archivedCountHint: 0,
    );
  final attention = StubAttentionRepository()
    ..myWorkAttentionResult = [
      MyWorkBeaconAttention(
        beaconId: _beaconId,
        unseenCount: 1,
        latestUnseen: _questionsMessage('Carol R8'),
      ),
    ];
  final cubit = MyWorkCubit(
    userId: _viewerId,
    myWorkCase: buildTestMyWorkCase(repo: repo, attentionRepository: attention),
  );
  addTearDown(cubit.close);
  await cubit.stream.firstWhere((s) => s.isSuccess && s.attentionLoaded);

  final router = _StubRouter();
  tester.view
    ..physicalSize = const Size(375, 667)
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MaterialApp(
      locale: const Locale('ru'),
      theme: TenturaTheme.light(),
      localizationsDelegates: L10n.localizationsDelegates,
      supportedLocales: L10n.supportedLocales,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: TextScaler.noScaling,
        ),
        child: child!,
      ),
      home: TenturaResponsiveScope(
        child: MultiBlocProvider(
          providers: [
            BlocProvider<MyWorkCubit>.value(value: cubit),
            BlocProvider<ProfileCubit>.value(value: _TestProfileCubit()),
            BlocProvider<ScreenCubit>(create: (_) => ScreenCubit.local()),
          ],
          child: RouterScope(
            controller: router,
            stateHash: 0,
            inheritableObserversBuilder: () => const [],
            child: StackRouterScope(
              controller: router,
              stateHash: 0,
              child: Scaffold(
                body: BlocBuilder<MyWorkCubit, MyWorkState>(
                  builder: (context, state) => SafeArea(
                    minimum: EdgeInsets.symmetric(
                      horizontal: context.tt.screenHPadding,
                    ),
                    child: ListView(
                      children: [
                        for (final vm in state.nonArchivedCards)
                          MyWorkCardRouter(vm: vm),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  setUp(() {
    if (!GetIt.I.isRegistered<Logger>()) {
      GetIt.I.registerSingleton<Logger>(Logger('issue-656-wrap'));
    }
    if (!GetIt.I.isRegistered<BeaconRepository>()) {
      GetIt.I.registerSingleton<BeaconRepository>(FakeBeaconRepository());
    }
    if (!GetIt.I.isRegistered<ClosureRepository>()) {
      GetIt.I.registerSingleton<ClosureRepository>(ClosureRepositoryMock());
    }
    if (!GetIt.I.isRegistered<OfferAcceptedDismissals>()) {
      GetIt.I.registerSingleton<OfferAcceptedDismissals>(
        OfferAcceptedDismissals(_NoDismissals()),
      );
    }
  });

  tearDown(() async {
    await GetIt.I.reset();
  });

  testWidgets(
    'Questions update row on the Request card paints the full RU headline at 375 px',
    (tester) async {
      RelativeTimestampTicker.debugClock = () => _now;
      addTearDown(() => RelativeTimestampTicker.debugClock = null);

      await _pumpAuthorCard(tester);

      final row = find.byType(AttentionMiniCard);
      expect(row, findsOneWidget);

      final headline =
          'Carol R8 · ${lookupL10n(const Locale('ru')).updatesQuestionsMessage}';
      final headlineFinder = find.descendant(
        of: row,
        matching: find.textContaining(headline),
      );
      expect(headlineFinder, findsOneWidget);

      final richText = find.descendant(
        of: headlineFinder,
        matching: find.byType(RichText),
      );
      expect(richText, findsOneWidget);
      final paragraph = tester.renderObject<RenderParagraph>(richText);
      expect(paragraph.didExceedMaxLines, isFalse);
      expect(
        paragraph.maxLines,
        anyOf(isNull, greaterThanOrEqualTo(3)),
        reason: 'Questions updates must not cap the event line at two lines',
      );
    },
  );
}
