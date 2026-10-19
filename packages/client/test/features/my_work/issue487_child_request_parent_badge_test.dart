// #487 — on the Requests list a child Request ("Child: borrow moving straps")
// read as a third, unrelated card beside its parent ("Need a hand moving a
// couch"). The room-context batch every card already reads now carries the
// guarded parent link (`parentBeaconId`, `parentTitle`; the server sends
// them only when the viewer may read the parent), the card view model keeps
// it, and the child card says what it is part of. A top-level Request says
// nothing of the kind.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';
import 'package:mockito/mockito.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';

import 'package:tentura/data/repository/mock/client_repository_mocks.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/attention/offer_accepted_dismissals.dart';
import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/beacon/data/repository/beacon_repository.dart';
import 'package:tentura/features/closure/data/repository/closure_repository.dart';
import 'package:tentura/features/inbox/data/gql/_g/inbox_room_context_batch.data.gql.dart';
import 'package:tentura/features/inbox/domain/entity/inbox_room_card_hints.dart';
import 'package:tentura/features/my_work/ui/bloc/my_work_cubit.dart';
import 'package:tentura/features/my_work/ui/widget/my_work_cards.dart';
import 'package:tentura/features/profile/ui/bloc/profile_cubit.dart';
import 'package:tentura/ui/bloc/screen_cubit.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/l10n/l10n_en.dart';
import 'package:tentura/ui/l10n/l10n_ru.dart';

import 'my_work_test_support.dart';

const _viewerId = 'author-487';
const _parentId = 'b-couch';
const _childId = 'b-straps';
const _parentTitle = 'Need a hand moving a couch';
const _childTitle = 'Child: borrow moving straps';

final class _TestProfileCubit extends Mock implements ProfileCubit {
  @override
  ProfileState get state => const ProfileState(
    profile: Profile(id: _viewerId, displayName: 'Me'),
  );

  @override
  Stream<ProfileState> get stream =>
      Stream<ProfileState>.value(state).asBroadcastStream();
}

final class _NoDismissals implements OfferAcceptedDismissalPort {
  @override
  Future<Set<String>> load({required String viewerId}) async => {};

  @override
  Future<Set<String>> dismiss({
    required String viewerId,
    required String beaconId,
  }) async => {};
}

Beacon _beacon(String id, String title, DateTime updatedAt) =>
    Beacon.empty.copyWith(
      id: id,
      title: title,
      status: BeaconStatus.open,
      updatedAt: updatedAt,
      author: const Profile(id: _viewerId, displayName: 'Me'),
    );

final _parent = _beacon(_parentId, _parentTitle, DateTime(2026, 10));
final _child = _beacon(_childId, _childTitle, DateTime(2026, 10, 2));

FakeMyWorkRepository _repo() => FakeMyWorkRepository()
  ..initResult = (
    authoredNonArchived: [_parent, _child],
    helpOfferedNonArchived: const [],
    obligationBeacons: const [],
    archivedCountHint: 0,
  );

FakeRoomHints _hints({bool childIsRoomMember = true}) => FakeRoomHints()
  ..hintsByBeaconId = {
    _parentId: const InboxRoomCardHints(isRoomMember: true, roomUnreadCount: 0),
    _childId: InboxRoomCardHints(
      isRoomMember: childIsRoomMember,
      roomUnreadCount: 0,
      parentBeaconId: _parentId,
      parentTitle: _parentTitle,
    ),
  };

void main() {
  test('the batch row carries the parent link from the wire', () {
    final row = GInboxRoomContextBatchData_InboxRoomContextBatch.fromJson({
      '__typename': 'v2_InboxRoomContextRow',
      'beaconId': _childId,
      'isRoomMember': true,
      'roomUnreadCount': 0,
      'parentBeaconId': _parentId,
      'parentTitle': _parentTitle,
    });
    expect(row!.parentBeaconId, _parentId);
    expect(row.parentTitle, _parentTitle);
  });

  test('MyWorkCase puts the parent link on the child card only', () async {
    final case_ = buildTestMyWorkCase(repo: _repo(), roomHints: _hints());

    final cards = (await case_.loadDeskInit(
      userId: _viewerId,
    )).nonArchivedCards;
    final byId = {for (final c in cards) c.beaconId: c};

    expect(byId[_childId]!.parentBeaconId, _parentId);
    expect(byId[_childId]!.parentTitle, _parentTitle);
    // Guard: the top-level parent card carries no parent.
    expect(byId[_parentId]!.parentBeaconId, isEmpty);
    expect(byId[_parentId]!.parentTitle, isEmpty);
  });

  test('the parent link is kept when the viewer is not in the room', () async {
    // Room-only hints (latest line, next step, …) are dropped for a
    // non-member; the parent link is not a room detail and stays.
    final case_ = buildTestMyWorkCase(
      repo: _repo(),
      roomHints: _hints(childIsRoomMember: false),
    );

    final cards = (await case_.loadDeskInit(
      userId: _viewerId,
    )).nonArchivedCards;
    final child = cards.singleWhere((c) => c.beaconId == _childId);

    expect(child.parentBeaconId, _parentId);
    expect(child.parentTitle, _parentTitle);
  });

  test('"Part of" copy names the parent in every locale', () {
    final en = L10nEn().myWorkPartOfParent(_parentTitle);
    final ru = L10nRu().myWorkPartOfParent(_parentTitle);
    expect(en, contains(_parentTitle));
    expect(ru, contains(_parentTitle));
    expect(ru, isNot(en));
  });

  group('Requests card', () {
    setUp(() {
      if (!GetIt.I.isRegistered<Logger>()) {
        GetIt.I.registerSingleton<Logger>(Logger('issue487'));
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

    tearDown(() {
      for (final unregister in <void Function()>[
        if (GetIt.I.isRegistered<BeaconRepository>())
          GetIt.I.unregister<BeaconRepository>,
        if (GetIt.I.isRegistered<ClosureRepository>())
          GetIt.I.unregister<ClosureRepository>,
        if (GetIt.I.isRegistered<OfferAcceptedDismissals>())
          GetIt.I.unregister<OfferAcceptedDismissals>,
      ]) {
        unregister();
      }
    });

    testWidgets('the child card says which Request it is part of', (
      tester,
    ) async {
      final cubit = MyWorkCubit(
        userId: _viewerId,
        myWorkCase: buildTestMyWorkCase(repo: _repo(), roomHints: _hints()),
      );
      addTearDown(cubit.close);
      await cubit.stream.firstWhere((s) => s.isSuccess);

      tester.view
        ..physicalSize = const Size(400, 2400)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      late L10n l10n;
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('en'),
          theme: TenturaTheme.light(),
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          home: TenturaResponsiveScope(
            child: MultiBlocProvider(
              providers: [
                BlocProvider<MyWorkCubit>.value(value: cubit),
                BlocProvider<ProfileCubit>.value(value: _TestProfileCubit()),
                BlocProvider<ScreenCubit>(create: (_) => ScreenCubit.local()),
              ],
              child: Scaffold(
                body: BlocBuilder<MyWorkCubit, MyWorkState>(
                  builder: (context, state) {
                    l10n = L10n.of(context)!;
                    return ListView(
                      children: [
                        for (final vm in state.nonArchivedCards)
                          MyWorkCardRouter(key: ValueKey(vm.beaconId), vm: vm),
                      ],
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final badge = l10n.myWorkPartOfParent(_parentTitle);
      final childCard = find.byKey(const ValueKey(_childId));
      final parentCard = find.byKey(const ValueKey(_parentId));
      expect(childCard, findsOneWidget);
      expect(parentCard, findsOneWidget);

      expect(
        find.descendant(of: childCard, matching: find.textContaining(badge)),
        findsOneWidget,
      );
      // Guard: the parent card is not badged as part of anything.
      expect(
        find.descendant(
          of: parentCard,
          matching: find.textContaining(l10n.myWorkPartOfParent('')),
        ),
        findsNothing,
      );
      expect(find.textContaining(badge), findsOneWidget);
    });
  });
}
