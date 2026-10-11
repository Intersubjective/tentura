// The Post room side of budding (plan D2): the `childCreated` notice of a bud
// renders from its payload (budder, title snapshot, invite count) and is never
// folded into the source-message footer, and a closed Post renders its
// kind-5 notice.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:tentura_root/domain/entity/beacon_hierarchy_owner_summary.dart';
import 'package:tentura_root/domain/entity/beacon_hierarchy_summary.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';
import 'package:tentura_root/domain/enums.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/beacon_room_consts.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/domain/entity/room_message.dart';
import 'package:tentura/domain/use_case/beacon_create_case.dart';
import 'package:tentura/domain/use_case/beacon_hierarchy_case.dart';
import 'package:tentura/features/beacon_threads/domain/room_host.dart';
import 'package:tentura/features/beacon_threads/ui/widget/beacon_child_promotion_footer.dart';
import 'package:tentura/features/profile/ui/bloc/profile_cubit.dart';
import 'package:tentura/ui/bloc/presence_cubit.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/widget/basic_chat_body.dart';

import '../../domain/use_case/fake_beacon_hierarchy_ports.dart';
import '../beacon_create/fake_beacon_ports.dart';

class _TestProfileCubit extends Mock implements ProfileCubit {
  @override
  ProfileState get state => const ProfileState(
    profile: Profile(id: 'me', displayName: 'Me'),
  );

  @override
  Stream<ProfileState> get stream => Stream<ProfileState>.value(state);
}

class _TestPresenceCubit extends Mock implements PresenceCubit {
  @override
  Map<String, UserPresenceStatus> get state => const {};

  @override
  Stream<Map<String, UserPresenceStatus>> get stream =>
      Stream<Map<String, UserPresenceStatus>>.value(state);
}

const _me = Profile(id: 'me', displayName: 'Me');
const _maria = Profile(id: 'maria', displayName: 'Maria');
final _base = DateTime.utc(2026, 10, 11, 12);

RoomMessage _source() => RoomMessage(
  id: 'source-1',
  beaconId: 'post-1',
  authorId: _maria.id,
  author: _maria,
  body: 'Who can lend a ladder on Saturday?',
  createdAt: _base,
);

RoomMessage _budNotice({int invitedCount = 2}) => RoomMessage(
  id: 'notice-1',
  beaconId: 'post-1',
  authorId: _maria.id,
  author: _maria,
  body: '',
  createdAt: _base.add(const Duration(minutes: 1)),
  systemMessageKind: BeaconRoomSystemMessageKind.childCreated,
  systemPayloadJson: jsonEncode({
    'version': 1,
    'kind': 'childCreated',
    'childBeaconId': 'child-1',
    'sourceMessageId': 'source-1',
    'title': 'Ladder for Saturday',
    'invitedCount': invitedCount,
  }),
);

RoomMessage _closedNotice() => RoomMessage(
  id: 'closed-1',
  beaconId: 'post-1',
  authorId: '',
  body: '',
  createdAt: _base.add(const Duration(minutes: 1)),
  systemMessageKind: BeaconRoomSystemMessageKind.postClosed,
  systemPayloadJson: jsonEncode({
    'childBeaconId': 'child-1',
    'title': 'Ladder for Saturday',
  }),
);

void main() {
  setUp(() async {
    await GetIt.I.reset();
  });

  tearDown(() async {
    await GetIt.I.reset();
  });

  /// [readable] false: the viewer is not an observer of the child, so the
  /// child preview is unavailable.
  void registerHierarchy({required bool readable}) {
    final port = FakeBeaconHierarchyRepositoryPort();
    if (readable) {
      port.childPreviews['child-1'] = BeaconHierarchySummary(
        beaconId: 'child-1',
        title: 'Ladder for Saturday',
        owner: const BeaconHierarchyOwnerSummary(
          id: 'maria',
          displayName: 'Maria',
        ),
        status: BeaconStatus.open,
        publishedAt: _base,
        isTombstone: false,
      );
    }
    GetIt.I.registerSingleton<BeaconHierarchyCase>(
      buildBeaconHierarchyCaseForTest(
        port,
        createCase: BeaconCreateCase(
          FakeBeaconWritePort(),
          FakeBeaconImagePort(),
        ),
        beacons: FakeBeaconWritePort(),
        commandStore: InMemoryBeaconChildCommandStore(),
      ),
    );
  }

  Future<L10n> pumpChat(
    WidgetTester tester, {
    required List<RoomMessage> messages,
    Locale locale = const Locale('en'),
  }) async {
    await tester.binding.setSurfaceSize(const Size(400, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MultiBlocProvider(
        providers: [
          BlocProvider<ProfileCubit>.value(value: _TestProfileCubit()),
          BlocProvider<PresenceCubit>.value(value: _TestPresenceCubit()),
        ],
        child: MaterialApp(
          locale: locale,
          theme: TenturaTheme.light(),
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          home: MediaQuery(
            data: const MediaQueryData(size: Size(400, 800)),
            child: TenturaResponsiveScope(
              child: Scaffold(
                body: BasicChatBody(
                  messages: messages,
                  myProfile: _me,
                  participants: const [],
                  isLoading: false,
                  enableComposerAttachments: false,
                  capabilities: const RoomCapabilities.post(),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return L10n.delegate.load(locale);
  }

  test('a bud notice is never redundant, even beside its source', () {
    expect(
      isRedundantChildCreatedNotice(_budNotice(), {'source-1', 'notice-1'}),
      isFalse,
    );
  });

  testWidgets('the bud notice shows while its source message is loaded', (
    tester,
  ) async {
    registerHierarchy(readable: true);
    final l10n = await pumpChat(
      tester,
      messages: [_source(), _budNotice()],
    );

    expect(
      find.text(l10n.roomBudNotice('Maria', 'Ladder for Saturday', 2)),
      findsOneWidget,
    );
    // The source still carries the existing footer.
    expect(find.byType(BeaconChildPromotionFooter), findsOneWidget);
  });

  testWidgets('a non-observer sees the payload title', (tester) async {
    registerHierarchy(readable: false);
    final l10n = await pumpChat(tester, messages: [_budNotice()]);

    expect(
      find.text(l10n.roomBudNotice('Maria', 'Ladder for Saturday', 2)),
      findsOneWidget,
    );
  });

  testWidgets('no invites: the short notice', (tester) async {
    registerHierarchy(readable: false);
    final l10n = await pumpChat(
      tester,
      messages: [_source(), _budNotice(invitedCount: 0)],
    );

    expect(
      find.text(l10n.roomBudNoticeNoInvites('Maria', 'Ladder for Saturday')),
      findsOneWidget,
    );
  });

  testWidgets('Russian copy and plural', (tester) async {
    registerHierarchy(readable: false);
    await pumpChat(
      tester,
      messages: [_budNotice(invitedCount: 5)],
      locale: const Locale('ru'),
    );

    expect(
      find.text(
        'Maria оформил(а) запрос «Ladder for Saturday» и позвал(а) 5 человек',
      ),
      findsOneWidget,
    );
  });

  testWidgets('a closed Post renders the kind-5 notice', (tester) async {
    registerHierarchy(readable: false);
    final l10n = await pumpChat(tester, messages: [_source(), _closedNotice()]);

    expect(find.byKey(const Key('Room.PostClosedNotice')), findsOneWidget);
    expect(
      find.text(l10n.roomPostClosedNotice('Ladder for Saturday')),
      findsOneWidget,
    );
  });
}
