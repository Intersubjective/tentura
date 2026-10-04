// The Post participants screen lists who is in the conversation («В РАЗГОВОРЕ»)
// and who has not opened it yet («ЕЩЁ НЕ ОТКРЫЛИ»), marks contacts, offers a
// trust toggle (was «[+ В контакты]») shortcut that reuses `ProfileViewCubit.addFriend`, shows who
// brought a member in from the forward edges, opens a profile on tap, shows
// the «Можно пересылать» + «Позвать» row and links to the
// forwarding graph. Rows are located by what they show and where they sit, not
// by keys, so any layout that renders the M5 mockup passes.
// UI copy is asserted verbatim in Russian (docs/plans/post-ux-mockups.md, M5).

import 'dart:async';

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
import 'package:tentura/features/post_view/ui/screen/post_participants_screen.dart';
import 'package:tentura/features/profile_view/ui/bloc/profile_view_cubit.dart';
import 'package:tentura/ui/bloc/screen_cubit.dart';
import 'package:tentura/ui/effect/ui_effect.dart';
import 'package:tentura/ui/l10n/l10n.dart';

import '../../ui/effect/fake_ui_effect_port.dart';

const _postId = 'Bpostparticipants01';
const _viewer = Profile(id: 'Uviewer', displayName: 'Ольга');

final _createdAt = DateTime.utc(2026, 10, 2, 12);
final _seenAt = DateTime.utc(2026, 10, 2, 13);

BeaconParticipant _participant(
  String userId,
  String name, {
  int role = BeaconParticipantRoleBits.addressee,
  int roomAccess = RoomAccessBits.admitted,
  DateTime? lastSeenRoomAt,
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
  _participant('Usveta', 'Света', lastSeenRoomAt: _seenAt),
  _participant(_viewer.id, _viewer.displayName, lastSeenRoomAt: _seenAt),
  _participant('Ukatya', 'Катя'),
  _participant('Upavel', 'Павел'),
  _participant(
    'Uleft',
    'Игорь',
    roomAccess: RoomAccessBits.left,
    lastSeenRoomAt: _seenAt,
  ),
];

List<ForwardEdge> _edges() => [
  ForwardEdge(
    id: 'E-maria-sveta',
    beaconId: _postId,
    createdAt: _createdAt,
    sender: const Profile(id: 'Umaria', displayName: 'Мария'),
    recipient: const Profile(id: 'Usveta', displayName: 'Света'),
  ),
];

/// Stands in for the per-person [ProfileViewCubit]: holds a fixed profile and
/// records `addFriend`, which flips the profile to a contact like the real one.
class _FakeProfileViewCubit extends Mock implements ProfileViewCubit {
  _FakeProfileViewCubit(this.id, {required bool isFriend})
    : _state = ProfileViewState(
        profile: Profile(id: id, myVote: isFriend ? 1 : 0),
      );

  final String id;
  final _controller = StreamController<ProfileViewState>.broadcast();
  ProfileViewState _state;
  int addFriendCalls = 0;
  bool _closed = false;

  @override
  ProfileViewState get state => _state;

  @override
  Stream<ProfileViewState> get stream => _controller.stream;

  @override
  bool get isClosed => _closed;

  @override
  Future<void> addFriend() async {
    addFriendCalls++;
    _state = ProfileViewState(profile: _state.profile.copyWith(myVote: 1));
    _controller.add(_state);
  }

  @override
  Future<void> close() async {
    _closed = true;
    await _controller.close();
  }
}

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
    required this.cubits,
  });

  final WidgetTester tester;
  final _RecordingRouter router;
  final FakeUiEffectPort effects;

  /// Profile cubits created by the screen, by user id.
  final Map<String, _FakeProfileViewCubit> cubits;

  Rect _rect(Element e) {
    final box = e.renderObject! as RenderBox;
    return box.localToGlobal(Offset.zero) & box.size;
  }

  /// The widgets matching [label] drawn on the same line as the person [name].
  List<Element> beside(String name, Finder label) {
    final nameRect = tester.getRect(find.text(name));
    return label.evaluate().where((e) {
      final r = _rect(e);
      return (r.center.dy - nameRect.center.dy).abs() < nameRect.height;
    }).toList();
  }

  bool hasBeside(String name, Finder label) => beside(name, label).isNotEmpty;

  Future<void> tapBeside(String name, Finder label) async {
    final matches = beside(name, label);
    expect(matches, hasLength(1), reason: '$label beside $name');
    await tester.tapAt(_rect(matches.single).center);
    await tester.pump();
  }

  double top(Finder f) => tester.getRect(f).top;
}

Future<_Harness> _pump(
  WidgetTester tester, {
  Set<String> contactIds = const {'Umaria'},
  List<BeaconParticipant>? participants,
  List<ForwardEdge>? forwardEdges,
}) async {
  final router = _RecordingRouter();
  final effects = FakeUiEffectPort();
  final cubits = <String, _FakeProfileViewCubit>{};

  await tester.binding.setSurfaceSize(const Size(420, 1000));
  addTearDown(() => tester.binding.setSurfaceSize(null));

  await tester.pumpWidget(
    StackRouterScope(
      controller: router,
      stateHash: 0,
      child: MaterialApp(
        theme: TenturaTheme.light(),
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        locale: const Locale('ru'),
        home: MediaQuery(
          data: const MediaQueryData(size: Size(420, 1000)),
          child: TenturaResponsiveScope(
            child: BlocProvider<ScreenCubit>(
              create: (_) => ScreenCubit(effects),
              child: Scaffold(
                body: PostParticipantsScreen(
                  beaconId: _postId,
                  viewerId: _viewer.id,
                  participants: participants ?? _participants(),
                  forwardEdges: forwardEdges ?? _edges(),
                  profileViewCubitFactory: (id) =>
                      cubits[id] ??= _FakeProfileViewCubit(
                        id,
                        isFriend: contactIds.contains(id),
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
  return _Harness(
    tester: tester,
    router: router,
    effects: effects,
    cubits: cubits,
  );
}

/// The trust toggle in the off position (its tooltip offers trust, #140).
final _addToContacts = find.byTooltip('Доверять этому пользователю');

/// The trust toggle in the on position.
final _inContacts = find.byTooltip('Перестать доверять');

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

      expect(find.text('В РАЗГОВОРЕ · 5'), findsOneWidget);
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

      final conversation = h.top(find.text('В РАЗГОВОРЕ · 5'));
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
            _viewer.id,
            _viewer.displayName,
            lastSeenRoomAt: _seenAt,
          ),
          _participant('Ukatya', 'Катя'),
        ],
      );

      expect(find.text('В РАЗГОВОРЕ · 4'), findsOneWidget);
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
            _viewer.id,
            _viewer.displayName,
            lastSeenRoomAt: _seenAt,
          ),
        ],
      );

      expect(find.text('В РАЗГОВОРЕ · 2'), findsOneWidget);
      expect(find.textContaining('ЕЩЁ НЕ ОТКРЫЛИ'), findsNothing);
    });

    testWidgets('shows the trust toggle on for a member who is a contact', (
      tester,
    ) async {
      final h = await _pump(tester);

      expect(h.hasBeside('Мария', _inContacts), isTrue);
      expect(h.hasBeside('Мария', _addToContacts), isFalse);
    });

    testWidgets('names who brought a member in, from the forward edges', (
      tester,
    ) async {
      final h = await _pump(tester);

      expect(
        h.hasBeside(
          'Света',
          find.textContaining(RegExp(r'^позвал[а]? Мария$')),
        ),
        isTrue,
      );
    });

    testWidgets(
      'offers the trust toggle off beside a member who is not a contact',
      (
        tester,
      ) async {
        final h = await _pump(tester);

        expect(h.hasBeside('Дима', _addToContacts), isTrue);
        expect(h.hasBeside('Света', _addToContacts), isTrue);
        expect(h.hasBeside('Вы', _addToContacts), isFalse);
      },
    );

    testWidgets('the trust toggle adds that member through the profile cubit', (
      tester,
    ) async {
      final h = await _pump(tester);
      expect(h.hasBeside('Дима', _addToContacts), isTrue);

      await h.tapBeside('Дима', _addToContacts);

      expect(h.cubits['Udima']!.addFriendCalls, 1);
      expect(
        h.cubits.entries
            .where((e) => e.key != 'Udima')
            .map((e) => e.value.addFriendCalls),
        everyElement(0),
      );
    });

    testWidgets('a member added from the list shows the toggle on', (
      tester,
    ) async {
      final h = await _pump(tester);

      await h.tapBeside('Дима', _addToContacts);
      await tester.pump();

      expect(h.hasBeside('Дима', _inContacts), isTrue);
      expect(h.hasBeside('Дима', _addToContacts), isFalse);
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

      expect(
        h.effects.emitted.whereType<NavigatePush>().map((e) => e.path),
        contains('/graph/forwards/$_postId'),
      );
    });

    testWidgets('shows «Можно пересылать» with «Позвать» when the Post is '
        'open to forwarding', (tester) async {
      await _pump(tester);

      expect(find.text('Можно пересылать'), findsOneWidget);
      expect(find.textContaining('Позвать'), findsOneWidget);
    });

    testWidgets('«Позвать» opens the forward flow for the Post', (
      tester,
    ) async {
      final h = await _pump(tester);

      await tester.tap(find.textContaining('Позвать'));
      await tester.pump();

      expect(h.router.pushed, hasLength(1));
      final route = h.router.pushed.single;
      expect(route, isA<ForwardBeaconRoute>());
      expect((route.args! as ForwardBeaconRouteArgs).beaconId, _postId);
    });
  });
}
