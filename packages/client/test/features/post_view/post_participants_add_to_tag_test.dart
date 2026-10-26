// A Post participant row offers "Add to tag…" through a visible overflow
// button, a touch long press and a mouse secondary tap; the entry opens the
// add-to-tag sheet of that row's person. The viewer's own row and every row
// while the people-tags feature is off offer nothing.

import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:mockito/mockito.dart';

import 'package:tentura/app/router/root_router.gr.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/beacon_participant.dart';
import 'package:tentura/domain/entity/beacon_room_consts.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/forward/domain/entity/forward_edge.dart';
import 'package:tentura/features/people_tags/domain/use_case/people_tags_case.dart';
import 'package:tentura/features/post_view/ui/widget/post_participants_list.dart';
import 'package:tentura/features/profile_view/ui/bloc/profile_view_cubit.dart';
import 'package:tentura/ui/bloc/screen_cubit.dart';
import 'package:tentura/ui/l10n/l10n.dart';

import '../../support/add_to_tag_sheet_probe.dart';
import '../../support/fake_people_tags_repository.dart';
import '../../support/optional_gate_call.dart';
import '../../support/person_menu_open_way.dart';

const _postId = 'Bpostparticipantstags';
const _viewerId = 'U-viewer';
const _peerId = 'U-peer';

final _t = DateTime.utc(2026, 10, 2, 12);

BeaconParticipant _participant(
  String userId,
  String name, {
  int role = BeaconParticipantRoleBits.addressee,
  DateTime? lastSeenRoomAt,
}) => BeaconParticipant(
  id: 'P-$userId',
  beaconId: _postId,
  userId: userId,
  userTitle: name,
  role: role,
  status: 0,
  roomAccess: RoomAccessBits.admitted,
  createdAt: _t,
  updatedAt: _t,
  lastSeenRoomAt: lastSeenRoomAt,
);

/// Stands in for the per-person [ProfileViewCubit] behind the trust toggle.
class _FakeProfileViewCubit extends Mock implements ProfileViewCubit {
  _FakeProfileViewCubit(String id)
    : _state = ProfileViewState(profile: Profile(id: id));

  final ProfileViewState _state;

  @override
  ProfileViewState get state => _state;

  @override
  Stream<ProfileViewState> get stream => const Stream.empty();

  @override
  bool get isClosed => false;

  @override
  Future<void> close() async {}
}

class _RecordingRouter extends Mock implements RootStackRouter {
  final pushed = <PageRouteInfo>[];

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

void main() {
  late PeopleTagsTestRig rig;
  late _RecordingRouter router;

  setUp(() async {
    router = _RecordingRouter();
    rig = await PeopleTagsTestRig.create(addToTagProbeRepository(_peerId));
    GetIt.I.registerSingleton<PeopleTagsCase>(rig.peopleTags);
  });

  tearDown(() async {
    await GetIt.I.reset();
    await rig.dispose();
  });

  /// Replaces the people-tags rig with one whose probe tag holds [personId].
  Future<void> useRigFor(String personId) async {
    await GetIt.I.reset();
    await rig.dispose();
    rig = await PeopleTagsTestRig.create(addToTagProbeRepository(personId));
    GetIt.I.registerSingleton<PeopleTagsCase>(rig.peopleTags);
  }

  /// [peopleTagsEnabled] null leaves the list's own default (the gate).
  Future<void> pumpList(
    WidgetTester tester, {
    bool? peopleTagsEnabled,
  }) async {
    await tester.binding.setSurfaceSize(const Size(420, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final screenCubit = ScreenCubit.local();
    addTearDown(screenCubit.close);
    await tester.pumpWidget(
      StackRouterScope(
        controller: router,
        stateHash: 0,
        child: MaterialApp(
          theme: TenturaTheme.light(),
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          locale: const Locale('en'),
          home: MediaQuery(
            data: const MediaQueryData(size: Size(420, 1000)),
            child: TenturaResponsiveScope(
              child: BlocProvider<ScreenCubit>.value(
                value: screenCubit,
                child: Scaffold(
                  body: SingleChildScrollView(
                    child:
                        callWithPeopleTagsGate(
                              PostParticipantsList.new,
                              gate: peopleTagsEnabled,
                              named: {
                                #viewerId: _viewerId,
                                #participants: [
                                  _participant(
                                    'U-author',
                                    'Olga Author',
                                    role: BeaconParticipantRoleBits.author,
                                  ),
                                  _participant(
                                    _peerId,
                                    'Peer Person',
                                    lastSeenRoomAt: _t,
                                  ),
                                  _participant(
                                    _viewerId,
                                    'Viewer',
                                    lastSeenRoomAt: _t,
                                  ),
                                ],
                                #forwardEdges: const <ForwardEdge>[],
                                #onForwardsGraph: () {},
                                #profileViewCubitFactory:
                                    _FakeProfileViewCubit.new,
                              },
                            )!
                            as Widget,
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

  /// The overflow button drawn on the same line as the person [name].
  Finder overflowOf(WidgetTester tester, String name) {
    final nameRect = tester.getRect(find.text(name));
    return find.byElementPredicate((e) {
      if (e.widget is! Icon || (e.widget as Icon).icon != Icons.more_vert) {
        return false;
      }
      final box = e.renderObject! as RenderBox;
      final center = (box.localToGlobal(Offset.zero) & box.size).center;
      return (center.dy - nameRect.center.dy).abs() < nameRect.height;
    }, description: 'overflow button beside "$name"');
  }

  group('Post participants: add to tag', () {
    testWidgets('a plain tap on a row opens the profile, not the menu', (
      tester,
    ) async {
      await pumpList(tester, peopleTagsEnabled: true);

      await tester.tap(find.text('Peer Person'));
      await tester.pumpAndSettle();

      expect(find.text('Add to tag…'), findsNothing);
      expect(router.pushed.single, isA<ProfileViewRoute>());
    });

    for (final way in PersonMenuOpenWay.values) {
      testWidgets('"Add to tag…" opened by ${way.name} shows in the menu', (
        tester,
      ) async {
        await pumpList(tester, peopleTagsEnabled: true);
        expect(find.text('Add to tag…'), findsNothing);

        await way.open(
          tester,
          overflow: overflowOf(tester, 'Peer Person'),
          target: find.text('Peer Person'),
        );

        expect(find.text('Add to tag…'), findsOneWidget);
      });

      testWidgets(
        '"Add to tag…" opened by ${way.name} opens the sheet for that row\'s '
        'person',
        (tester) async {
          await pumpList(tester, peopleTagsEnabled: true);

          await way.open(
            tester,
            overflow: overflowOf(tester, 'Peer Person'),
            target: find.text('Peer Person'),
          );
          await tester.tap(find.text('Add to tag…'));

          await expectAddToTagSheetIsForPerson(
            tester,
            rig.repository,
            _peerId,
          );
        },
      );
    }

    testWidgets('the viewer row has no overflow button and no menu', (
      tester,
    ) async {
      await pumpList(tester, peopleTagsEnabled: true);

      expect(overflowOf(tester, 'You'), findsNothing);
      await expectNoPersonMenuFromGestures(
        tester,
        target: find.text('You'),
      );
    });

    testWidgets('is absent when the feature is switched off', (tester) async {
      await pumpList(tester, peopleTagsEnabled: false);

      expect(find.byIcon(Icons.more_vert), findsNothing);
      await expectNoPersonMenuFromGestures(
        tester,
        target: find.text('Peer Person'),
      );
    });

    testWidgets('is absent when phase 1 is explicitly disabled', (
      tester,
    ) async {
      await pumpList(tester, peopleTagsEnabled: false);

      expect(find.byIcon(Icons.more_vert), findsNothing);
      await expectNoPersonMenuFromGestures(
        tester,
        target: find.text('Peer Person'),
      );
    });
  });

  group('Post participants, author row: add to tag', () {
    setUp(() => useRigFor('U-author'));

    for (final way in PersonMenuOpenWay.values) {
      testWidgets(
        'the author row (not the viewer) opens the sheet for the author by '
        '${way.name}',
        (tester) async {
          await pumpList(tester, peopleTagsEnabled: true);

          await way.open(
            tester,
            overflow: overflowOf(tester, 'Olga Author'),
            target: find.text('Olga Author'),
          );
          await tester.tap(find.text('Add to tag…'));

          await expectAddToTagSheetIsForPerson(
            tester,
            rig.repository,
            'U-author',
          );
        },
      );
    }
  });
}
