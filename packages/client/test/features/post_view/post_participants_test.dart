// The Post participants list (a section of «О посте») lists who is in the
// conversation («В ПОСТЕ») and who has not opened it yet («ЕЩЁ НЕ
// ОТКРЫЛИ»), shows who brought a member in from server attribution, opens a
// profile on tap, offers «Позвать» to a member who may forward and links to
// the forwarding graph. Rows are located by what they show and where they sit,
// not by keys, so any layout that renders the M5 mockup passes.
// UI copy is asserted verbatim in Russian (docs/plans/post-ux-mockups.md, M5).

import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';

import 'package:tentura/app/router/root_router.gr.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/beacon_participant.dart';
import 'package:tentura/domain/entity/beacon_room_consts.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/forward/domain/entity/forward_edge.dart';
import 'package:tentura/features/post_view/ui/widget/post_participants_list.dart';
import 'package:tentura/ui/bloc/screen_cubit.dart';
import 'package:tentura/ui/l10n/l10n.dart';

import '../../support/phone_surface.dart';
import '../../ui/effect/fake_ui_effect_port.dart';

const _postId = 'Bpostparticipants01';
const _viewerId = 'Uviewer';
const _viewer = Profile(id: _viewerId, displayName: 'Ольга');
const _aliceViewerId = 'Ualice';

final _createdAt = DateTime.utc(2026, 10, 2, 12);
final _seenAt = DateTime.utc(2026, 10, 2, 13);

BeaconParticipant _participant(
  String userId,
  String name, {
  int role = BeaconParticipantRoleBits.addressee,
  int roomAccess = RoomAccessBits.admitted,
  DateTime? lastSeenRoomAt,
  bool? opened,
  String? broughtByName,
  String? broughtHow,
  String? broughtById,
}) => BeaconParticipant(
  id: 'P-$userId',
  beaconId: _postId,
  userId: userId,
  userTitle: name,
  role: role,
  status: 0,
  roomAccess: roomAccess,
  createdAt: _createdAt,
  updatedAt: _createdAt,
  lastSeenRoomAt: lastSeenRoomAt,
  opened: opened ?? lastSeenRoomAt != null,
  broughtByName: broughtByName,
  broughtHow: broughtHow,
  broughtById: broughtById,
);

/// The M5 mockup: five in the conversation (author, a contact, a stranger,
/// someone Мария brought in, the viewer), two who have not opened it yet, and
/// one member who left and must not be listed anywhere.
List<BeaconParticipant> _participants() => [
  _participant(
    'Uauthor',
    'Олег',
    role: BeaconParticipantRoleBits.author,
  ),
  _participant('Umaria', 'Мария', lastSeenRoomAt: _seenAt),
  _participant('Udima', 'Дима', lastSeenRoomAt: _seenAt),
  _participant(
    'Usveta',
    'Света',
    lastSeenRoomAt: _seenAt,
    broughtByName: 'Мария',
    broughtHow: BeaconParticipantBroughtHow.forward,
  ),
  _participant(_viewerId, _viewer.displayName, lastSeenRoomAt: _seenAt),
  _participant('Ukatya', 'Катя'),
  _participant('Upavel', 'Павел'),
  _participant(
    'Uleft',
    'Игорь',
    roomAccess: RoomAccessBits.left,
    lastSeenRoomAt: _seenAt,
  ),
];

List<ForwardEdge> _edges() => const [];

/// Records pushed routes; `root` is the router itself.
class _RecordingRouter extends Mock implements RootStackRouter {
  final List<PageRouteInfo> pushed = [];

  @override
  RootStackRouter get root => this;

  @override
  PagelessRoutesObserver get pagelessRoutesObserver => PagelessRoutesObserver();

  @override
  Future<T?> push<T extends Object?>(
    PageRouteInfo route, {
    OnNavigationFailure? onFailure,
  }) async {
    pushed.add(route);
    return null;
  }

  @override
  bool canPop({
    bool ignoreChildRoutes = false,
    bool ignoreParentRoutes = false,
    bool ignorePagelessRoutes = false,
  }) => false;
}

class _Harness {
  _Harness({
    required this.tester,
    required this.router,
    required this.effects,
  });

  final WidgetTester tester;
  final _RecordingRouter router;
  final FakeUiEffectPort effects;

  int graphTaps = 0;
  int inviteTaps = 0;

  Rect _rect(Element e) {
    final box = e.renderObject! as RenderBox;
    return box.localToGlobal(Offset.zero) & box.size;
  }

  List<Element> beside(String name, Finder label) {
    final nameRect = tester.getRect(find.text(name));
    return label.evaluate().where((e) {
      final r = _rect(e);
      return (r.center.dy - nameRect.center.dy).abs() < nameRect.height;
    }).toList();
  }

  bool hasBeside(String name, Finder label) => beside(name, label).isNotEmpty;

  double top(Finder f) => tester.getRect(f).top;
}

Future<_Harness> _pump(
  WidgetTester tester, {
  String viewerId = _viewerId,
  Locale locale = const Locale('ru'),
  List<BeaconParticipant>? participants,
  List<ForwardEdge>? forwardEdges,
  bool canInvite = true,
  Size surface = const Size(420, 1000),
}) async {
  final router = _RecordingRouter();
  final effects = FakeUiEffectPort();
  final harness = _Harness(
    tester: tester,
    router: router,
    effects: effects,
  );

  await tester.binding.setSurfaceSize(surface);
  addTearDown(() => tester.binding.setSurfaceSize(null));

  await tester.pumpWidget(
    StackRouterScope(
      controller: router,
      stateHash: 0,
      child: MaterialApp(
        theme: TenturaTheme.light(),
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        locale: locale,
        home: MediaQuery(
          data: MediaQueryData(size: surface),
          child: TenturaResponsiveScope(
            child: BlocProvider<ScreenCubit>(
              create: (_) => ScreenCubit(effects),
              child: Scaffold(
                body: SingleChildScrollView(
                  child: PostParticipantsList(
                    viewerId: viewerId,
                    participants: participants ?? _participants(),
                    forwardEdges: forwardEdges ?? _edges(),
                    onForwardsGraph: () => harness.graphTaps++,
                    onInvite: canInvite ? () => harness.inviteTaps++ : null,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump(const Duration(milliseconds: 100));
  return harness;
}

void main() {
  group('Post participants screen', () {
    testWidgets('titles the screen with everyone who is in or invited', (
      tester,
    ) async {
      await _pump(tester);

      expect(find.text('Участники · 7'), findsOneWidget);
    });

    testWidgets('counts and lists the members in the conversation', (
      tester,
    ) async {
      await _pump(tester);

      expect(find.text('В ПОСТЕ · 5'), findsOneWidget);
      for (final name in ['Олег', 'Мария', 'Дима', 'Света', 'Вы']) {
        expect(find.text(name), findsOneWidget, reason: name);
      }
    });

    testWidgets('marks the author and shows the viewer as «Вы»', (
      tester,
    ) async {
      final h = await _pump(tester);

      expect(h.hasBeside('Олег', find.text('автор')), isTrue);
      expect(find.text('Вы'), findsOneWidget);
      expect(find.text(_viewer.displayName), findsNothing);
    });

    testWidgets('counts the members who have not opened the Post yet', (
      tester,
    ) async {
      await _pump(tester);

      expect(find.text('ЕЩЁ НЕ ОТКРЫЛИ · 2'), findsOneWidget);
    });

    testWidgets('lists the names of the members who have not opened it '
        'under the unopened heading', (tester) async {
      final h = await _pump(tester);

      final heading = h.top(find.text('ЕЩЁ НЕ ОТКРЫЛИ · 2'));
      expect(h.top(find.text('Катя')), greaterThan(heading));
      expect(h.top(find.text('Павел')), greaterThan(heading));
    });

    testWidgets('keeps members who have opened the Post out of the '
        'unopened section', (tester) async {
      final h = await _pump(tester);

      final conversation = h.top(find.text('В ПОСТЕ · 5'));
      final unopened = h.top(find.text('ЕЩЁ НЕ ОТКРЫЛИ · 2'));
      for (final name in ['Олег', 'Мария', 'Дима', 'Света', 'Вы']) {
        final y = h.top(find.text(name));
        expect(y, greaterThan(conversation), reason: name);
        expect(y, lessThan(unopened), reason: name);
      }
    });

    testWidgets('a single unopened member is the only one under the '
        'unopened heading', (tester) async {
      final h = await _pump(
        tester,
        participants: [
          _participant(
            'Uauthor',
            'Олег',
            role: BeaconParticipantRoleBits.author,
          ),
          _participant('Umaria', 'Мария', lastSeenRoomAt: _seenAt),
          _participant('Udima', 'Дима', lastSeenRoomAt: _seenAt),
          _participant(
            _viewerId,
            _viewer.displayName,
            lastSeenRoomAt: _seenAt,
          ),
          _participant('Ukatya', 'Катя'),
        ],
      );

      expect(find.text('В ПОСТЕ · 4'), findsOneWidget);
      expect(find.text('ЕЩЁ НЕ ОТКРЫЛИ · 1'), findsOneWidget);
      final heading = h.top(find.text('ЕЩЁ НЕ ОТКРЫЛИ · 1'));
      expect(h.top(find.text('Катя')), greaterThan(heading));
      expect(h.top(find.text('Дима')), lessThan(heading));
      expect(h.top(find.text('Мария')), lessThan(heading));
    });

    testWidgets('lists a member who left in neither section', (tester) async {
      await _pump(tester);

      expect(find.text('Игорь'), findsNothing);
    });

    testWidgets('omits the unopened section when everyone has opened it', (
      tester,
    ) async {
      await _pump(
        tester,
        participants: [
          _participant(
            'Uauthor',
            'Олег',
            role: BeaconParticipantRoleBits.author,
          ),
          _participant(
            _viewerId,
            _viewer.displayName,
            lastSeenRoomAt: _seenAt,
          ),
        ],
      );

      expect(find.text('В ПОСТЕ · 2'), findsOneWidget);
      expect(find.textContaining('ЕЩЁ НЕ ОТКРЫЛИ'), findsNothing);
    });

    testWidgets('names who brought a member in, from server attribution', (
      tester,
    ) async {
      final h = await _pump(tester);

      expect(h.hasBeside('Света', find.text('через Мария')), isTrue);
    });

    testWidgets('participant rows offer no inline trust control', (
      tester,
    ) async {
      await _pump(tester);

      expect(find.byType(Switch), findsNothing);
      expect(find.byType(SwitchListTile), findsNothing);
    });

    testWidgets('tapping a person opens their profile', (tester) async {
      final h = await _pump(tester);

      await tester.tap(find.text('Дима'));
      await tester.pump();

      expect(h.router.pushed, hasLength(1));
      final route = h.router.pushed.single;
      expect(route, isA<ProfileViewRoute>());
      expect((route.args! as ProfileViewRouteArgs).id, 'Udima');
    });

    testWidgets('tapping a member who has not opened the Post opens the '
        'profile too', (tester) async {
      final h = await _pump(tester);

      await tester.tap(find.text('Катя'));
      await tester.pump();

      expect(h.router.pushed, hasLength(1));
      expect(
        (h.router.pushed.single.args! as ProfileViewRouteArgs).id,
        'Ukatya',
      );
    });

    testWidgets('«Как пост дошёл до людей» opens the forwarding graph', (
      tester,
    ) async {
      final h = await _pump(tester);

      await tester.tap(find.textContaining('Как пост дошёл до людей'));
      await tester.pump();

      expect(h.graphTaps, 1);
    });

    testWidgets('offers «Позвать» to a member who may forward', (
      tester,
    ) async {
      final h = await _pump(tester);

      await tester.tap(find.textContaining('Позвать'));
      await tester.pump();

      expect(h.inviteTaps, 1);
    });

    // #723: the button was announced as a bare «Invite», the same word the
    // rows use for «invited by …».
    testWidgets('«Позвать» has its own screen reader name', (tester) async {
      final semantics = tester.ensureSemantics();
      final h = await _pump(tester);

      final invite = find.semantics.byLabel('Позвать кого-нибудь в этот пост');
      expect(invite, findsOne);
      expect(
        invite.evaluate().single,
        isSemantics(isButton: true, hasTapAction: true),
      );
      expect(find.semantics.byLabel('Позвать'), findsNothing);

      tester.semantics.tap(invite);
      await tester.pump();
      expect(h.inviteTaps, 1);
      semantics.dispose();
    });

    testWidgets('offers no «Позвать» to a member who may not forward', (
      tester,
    ) async {
      await _pump(tester, canInvite: false);

      expect(find.textContaining('Позвать'), findsNothing);
    });

    testWidgets(
      '375×667 RU: headings and brought-by line fit without overflow',
      (
        tester,
      ) async {
        await usePhoneSurface(tester);
        await _pump(tester, surface: kPhoneSurface);

        expect(tester.takeException(), isNull);
        expect(find.text('Участники · 7'), findsOneWidget);
        expect(find.text('В ПОСТЕ · 5'), findsOneWidget);
        expect(find.text('через Мария'), findsOneWidget);
        expect(find.byType(Switch), findsNothing);
      },
    );
  });

  group('Post participant arrival note (broughtBy / broughtHow)', () {
    testWidgets('invite: shows invited-by from server, not forward edges', (
      tester,
    ) async {
      final h = await _pump(
        tester,
        locale: const Locale('en'),
        viewerId: _aliceViewerId,
        forwardEdges: const [],
        participants: [
          _participant(
            'Uauthor',
            'Author',
            role: BeaconParticipantRoleBits.author,
            lastSeenRoomAt: _seenAt,
          ),
          _participant(
            _aliceViewerId,
            'Alice',
            lastSeenRoomAt: _seenAt,
          ),
          _participant(
            'Usam',
            'Sam',
            lastSeenRoomAt: _seenAt,
            broughtByName: 'Bob GQ',
            broughtHow: BeaconParticipantBroughtHow.invite,
          ),
        ],
      );

      expect(h.hasBeside('Sam', find.text('invited by Bob GQ')), isTrue);
    });

    testWidgets('forward: shows via from server', (tester) async {
      final h = await _pump(
        tester,
        locale: const Locale('en'),
        viewerId: _aliceViewerId,
        forwardEdges: const [],
        participants: [
          _participant(
            'Uauthor',
            'Author',
            role: BeaconParticipantRoleBits.author,
            lastSeenRoomAt: _seenAt,
          ),
          _participant(
            _aliceViewerId,
            'Alice',
            lastSeenRoomAt: _seenAt,
          ),
          _participant(
            'Usam',
            'Sam',
            lastSeenRoomAt: _seenAt,
            broughtByName: 'Bob GQ',
            broughtHow: BeaconParticipantBroughtHow.forward,
          ),
        ],
      );

      expect(h.hasBeside('Sam', find.text('via Bob GQ')), isTrue);
    });

    testWidgets('omits a line when broughtBy is null', (tester) async {
      await _pump(
        tester,
        locale: const Locale('en'),
        viewerId: _aliceViewerId,
        forwardEdges: const [],
        participants: [
          _participant(
            'Uauthor',
            'Author',
            role: BeaconParticipantRoleBits.author,
            lastSeenRoomAt: _seenAt,
          ),
          _participant(
            _aliceViewerId,
            'Alice',
            lastSeenRoomAt: _seenAt,
          ),
          _participant('Usam', 'Sam', lastSeenRoomAt: _seenAt),
        ],
      );

      expect(find.textContaining('invited by'), findsNothing);
      expect(find.textContaining('via '), findsNothing);
    });
  });
}
