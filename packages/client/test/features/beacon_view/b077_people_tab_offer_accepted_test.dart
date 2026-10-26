// B077: the helper whose offer was accepted also sees the «offer accepted»
// event sub-card at the top of the Request screen's People tab. Dismissing it
// there or on the Requests tab is one remembered dismissal.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';

import 'package:tentura_root/domain/entity/beacon_access.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/attention/offer_accepted_dismissals.dart';
import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/beacon_participant.dart';
import 'package:tentura/domain/entity/beacon_room_consts.dart';
import 'package:tentura/domain/entity/coordination_response_type.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/beacon_view/ui/bloc/beacon_view_cubit.dart';
import 'package:tentura/features/beacon_view/ui/bloc/timeline_help_offer_mapping.dart';
import 'package:tentura/features/beacon_view/ui/widget/beacon_people_tab_body.dart';
import 'package:tentura/features/inbox/ui/widget/attention_mini_card.dart';
import 'package:tentura/features/profile/ui/bloc/profile_cubit.dart';
import 'package:tentura/ui/bloc/screen_cubit.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/widget/offer_accepted_event_subcard.dart';
import '../../support/people_tags_widget_harness.dart';

const _helper = Profile(id: 'h1', displayName: 'Helper');
const _author = Profile(id: 'auth', displayName: 'Author');
const _stewardId = 'stw';
final _t = DateTime.utc(2025);

class _MockProfileCubit extends Mock implements ProfileCubit {
  @override
  ProfileState get state => const ProfileState(profile: _helper);

  @override
  Stream<ProfileState> get stream => Stream<ProfileState>.value(state);
}

class _MockBeaconViewCubit extends Mock implements BeaconViewCubit {
  _MockBeaconViewCubit(this._state);

  final BeaconViewState _state;

  @override
  BeaconViewState get state => _state;

  @override
  Stream<BeaconViewState> get stream => Stream<BeaconViewState>.value(_state);

  @override
  Future<void> loadForwards() async {}
}

final class _RecordingPort implements OfferAcceptedDismissalPort {
  /// `viewerId:beaconId` keys, as the server would hold them per account.
  Set<String> stored = {};

  @override
  Future<Set<String>> load({required String viewerId}) async => {
    for (final k in stored)
      if (k.startsWith('$viewerId:')) k.substring(viewerId.length + 1),
  };

  @override
  Future<Set<String>> dismiss({
    required String viewerId,
    required String beaconId,
  }) async {
    stored = {
      ...stored,
      OfferAcceptedDismissals.keyFor(viewerId: viewerId, beaconId: beaconId),
    };
    return load(viewerId: viewerId);
  }
}

BeaconViewState _state({int? roomAccess, CoordinationResponseType? response}) =>
    BeaconViewState(
      beacon: Beacon(
        id: 'B1',
        title: 'Moving day',
        author: _author,
        createdAt: _t,
        updatedAt: _t,
        // The server derives the viewer's access reasons from room_access.
        accessReasons: roomAccess == RoomAccessBits.admitted
            ? BeaconAccessReason.admitted.bit
            : 0,
      ),
      myProfile: _helper,
      helpOffers: [
        TimelineHelpOffer(
          user: _helper,
          message: 'I can help',
          createdAt: _t,
          updatedAt: _t.add(const Duration(minutes: 5)),
          roomAccess: roomAccess,
          coordinationResponse: response,
        ),
      ],
    );

Future<void> _pump(WidgetTester tester, BeaconViewState state) async {
  final cubit = _MockBeaconViewCubit(state);
  await tester.pumpPeopleTagsWidget(
    MaterialApp(
      theme: TenturaTheme.light(),
      localizationsDelegates: L10n.localizationsDelegates,
      supportedLocales: L10n.supportedLocales,
      locale: const Locale('en'),
      home: MultiBlocProvider(
        providers: [
          BlocProvider<ProfileCubit>.value(value: _MockProfileCubit()),
          BlocProvider<ScreenCubit>(create: (_) => ScreenCubit.local()),
          BlocProvider<BeaconViewCubit>.value(value: cubit),
        ],
        child: Scaffold(
          body: SingleChildScrollView(
            child: BeaconPeopleTabBody(
              state: state,
              beaconViewCubit: cubit,
              l10n: lookupL10n(const Locale('en')),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// The admitted helper's state as the server returns it, the offer accepted
/// by [acceptorId] (`responseAuthorUserId`), with [participants] loaded.
BeaconViewState _acceptedBy(
  String? acceptorId, {
  List<BeaconParticipant> participants = const [],
}) => _state(roomAccess: RoomAccessBits.admitted).copyWith(
  roomParticipants: participants,
  helpOffers: timelineHelpOffersFromRemote([
    (
      beaconId: 'B1',
      userId: _helper.id,
      user: _helper,
      message: 'I can help',
      helpType: null,
      roleLabel: null,
      status: 0,
      withdrawReason: null,
      createdAt: _t,
      updatedAt: _t,
      editedAt: null,
      responseType: CoordinationResponseType.useful.index,
      responseUpdatedAt: _t,
      responseAuthorUserId: acceptorId,
      roomAccess: RoomAccessBits.admitted,
      admissionAction: null,
      lastDeclineReason: null,
      lastRemoveReason: null,
      stakeState: 0,
      offerKind: 0,
      isDirectAuthorForward: false,
      authorSeenAt: null,
    ),
  ]),
);

final _stewardParticipant = BeaconParticipant(
  id: 'p-stw',
  beaconId: 'B1',
  userId: _stewardId,
  role: BeaconParticipantRoleBits.steward,
  status: 0,
  roomAccess: RoomAccessBits.admitted,
  createdAt: _t,
  updatedAt: _t,
  userTitle: 'Stella Steward',
);

Finder _inSubcard(String text) => find.descendant(
  of: find.byType(OfferAcceptedEventSubcard),
  matching: find.text(text),
);

void main() {
  late _RecordingPort port;

  setUp(() async {
    port = _RecordingPort();
    final store = OfferAcceptedDismissals(port);
    GetIt.I.registerSingleton<OfferAcceptedDismissals>(store);
  });

  tearDown(() async {
    if (GetIt.I.isRegistered<OfferAcceptedDismissals>()) {
      await GetIt.I.unregister<OfferAcceptedDismissals>();
    }
  });

  testWidgets('admitted helper sees the offer-accepted sub-card', (
    tester,
  ) async {
    await _pump(
      tester,
      _state(
        roomAccess: RoomAccessBits.admitted,
        response: CoordinationResponseType.useful,
      ),
    );
    final l10n = lookupL10n(const Locale('en'));
    final subcard = find.byType(OfferAcceptedEventSubcard);
    expect(subcard, findsOneWidget);
    expect(
      find.descendant(
        of: subcard,
        matching: find.text(l10n.attentionCardOfferAccepted('Author')),
      ),
      findsOneWidget,
    );
  });

  group('#507: names the one who accepted', () {
    final l10n = lookupL10n(const Locale('en'));

    testWidgets("a steward's accept names the steward, not the author", (
      tester,
    ) async {
      await _pump(
        tester,
        _acceptedBy(_stewardId, participants: [_stewardParticipant]),
      );
      expect(
        _inSubcard(l10n.attentionCardOfferAccepted('Stella Steward')),
        findsOneWidget,
      );
      expect(
        _inSubcard(l10n.attentionCardOfferAccepted('Author')),
        findsNothing,
      );
    });

    testWidgets(
      "a steward's accept with no profile at hand names no one, not the author",
      (tester) async {
        await _pump(tester, _acceptedBy(_stewardId));
        expect(
          _inSubcard(l10n.activityForwardOutcomeAcceptedNoAuthor),
          findsOneWidget,
        );
        expect(
          _inSubcard(l10n.attentionCardOfferAccepted('Author')),
          findsNothing,
        );
      },
    );

    testWidgets("the author's accept names the author", (tester) async {
      await _pump(
        tester,
        _acceptedBy(_author.id, participants: [_stewardParticipant]),
      );
      expect(
        _inSubcard(l10n.attentionCardOfferAccepted('Author')),
        findsOneWidget,
      );
    });

    testWidgets('no recorded acceptor still names the author', (tester) async {
      await _pump(
        tester,
        _acceptedBy(null, participants: [_stewardParticipant]),
      );
      expect(
        _inSubcard(l10n.attentionCardOfferAccepted('Author')),
        findsOneWidget,
      );
    });
  });

  testWidgets('× there is remembered for both places', (tester) async {
    await _pump(
      tester,
      _state(
        roomAccess: RoomAccessBits.admitted,
        response: CoordinationResponseType.useful,
      ),
    );
    final subcard = find.byType(OfferAcceptedEventSubcard);
    await tester.tap(
      find.descendant(
        of: subcard,
        matching: find.byKey(AttentionMiniCard.dismissKey),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.descendant(of: subcard, matching: find.byType(AttentionMiniCard)),
      findsNothing,
    );
    expect(port.stored, {
      OfferAcceptedDismissals.keyFor(viewerId: 'h1', beaconId: 'B1'),
    });
  });

  testWidgets('a pending offer shows no accepted sub-card', (tester) async {
    await _pump(tester, _state());
    expect(
      find.descendant(
        of: find.byType(OfferAcceptedEventSubcard),
        matching: find.byType(AttentionMiniCard),
      ),
      findsNothing,
    );
  });

  // #593 review: the sub-card's age is when the author accepted, not when
  // the offer was last edited.
  testWidgets('a later edit of the offer leaves the acceptance time', (
    tester,
  ) async {
    final acceptedAt = DateTime.utc(2025, 1, 1, 0, 5);
    final admitted = _state(roomAccess: RoomAccessBits.admitted);
    final state = admitted.copyWith(
      helpOffers: timelineHelpOffersFromRemote([
        (
          beaconId: 'B1',
          userId: _helper.id,
          user: _helper,
          message: 'I can help, edited',
          helpType: null,
          roleLabel: null,
          status: 0,
          withdrawReason: null,
          createdAt: _t,
          updatedAt: DateTime.utc(2025, 1, 4),
          editedAt: null,
          responseType: CoordinationResponseType.useful.index,
          responseUpdatedAt: acceptedAt,
          responseAuthorUserId: _author.id,
          roomAccess: RoomAccessBits.admitted,
          admissionAction: null,
          lastDeclineReason: null,
          lastRemoveReason: null,
          stakeState: 0,
          offerKind: 0,
          isDirectAuthorForward: false,
          authorSeenAt: null,
        ),
      ]),
    );
    await _pump(tester, state);
    expect(
      tester
          .widget<OfferAcceptedEventSubcard>(
            find.byType(OfferAcceptedEventSubcard),
          )
          .acceptedAt,
      acceptedAt,
    );
  });
}
