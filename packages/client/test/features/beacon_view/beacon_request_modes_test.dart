import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tentura_root/domain/entity/beacon_access.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/beacon_participant.dart';
import 'package:tentura/domain/entity/beacon_room_state.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/beacon_view/ui/bloc/beacon_view_state.dart';
import 'package:tentura/features/beacon_view/ui/util/beacon_request_modes.dart';
import 'package:tentura/features/beacon_view/ui/widget/beacon_hud_pinned_block.dart';
import 'package:tentura/features/beacon_view/ui/widget/beacon_showcase_surface.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/l10n/l10n_en.dart';

const _author = Profile(id: 'author', displayName: 'Priya');
const _me = Profile(id: 'me', displayName: 'Me');
const _ivan = Profile(id: 'ivan', displayName: 'Ivan');
const _olga = Profile(id: 'olga', displayName: 'Olga', myVote: 1);
const _max = Profile(id: 'max', displayName: 'Max');

BeaconViewState _state({
  BeaconAccessLevel? access,
  Profile author = _author,
  List<Profile> roster = const [],
  int helperCount = 0,
  Set<String> acquaintances = const {},
  BeaconRoomState? cue,
  List<BeaconParticipant> participants = const [],
  List<TimelineHelpOffer> offers = const [],
}) => BeaconViewState(
  beacon: Beacon.empty.copyWith(
    id: 'B1',
    updatedAt: DateTime(2026),
    author: author,
    accessLevel: access,
    admittedHelperCount: helperCount,
  ),
  myProfile: _me,
  admittedHelperRoster: roster,
  admittedHelpersLoaded: true,
  teamAcquaintanceIds: acquaintances,
  beaconRoomCue: cue,
  roomParticipants: participants,
  helpOffers: offers,
);

final _l10n = L10nEn();

void main() {
  group('beaconViewModeFor', () {
    test('the author gets the HUD', () {
      expect(
        beaconViewModeFor(
          _state(access: BeaconAccessLevel.author, author: _me),
        ),
        BeaconViewMode.hud,
      );
    });

    test('a member let in gets the HUD', () {
      expect(
        beaconViewModeFor(_state(access: BeaconAccessLevel.member)),
        BeaconViewMode.hud,
      );
    });

    test('observers and strangers get the showcase', () {
      for (final access in [
        BeaconAccessLevel.observer,
        BeaconAccessLevel.stranger,
      ]) {
        expect(
          beaconViewModeFor(_state(access: access)),
          BeaconViewMode.showcase,
          reason: access.name,
        );
      }
    });

    test('the author previewing gets the showcase', () {
      expect(
        beaconViewModeFor(
          _state(access: BeaconAccessLevel.author, author: _me),
          previewAsOutsider: true,
        ),
        BeaconViewMode.showcase,
      );
    });
  });

  group('deriveBeaconShowcaseTeam', () {
    test('puts trusted and shared-episode people first, keeps the rest', () {
      final team = deriveBeaconShowcaseTeam(
        roster: const [_ivan, _max, _olga],
        totalCount: 3,
        acquaintanceIds: const {'max'},
        viewerId: 'me',
      );
      expect(team.visible.map((p) => p.id), ['max', 'olga', 'ivan']);
      expect(team.acquaintances.map((p) => p.id), ['max', 'olga']);
      expect(team.hiddenCount, 0);
    });

    test('members the viewer cannot read only count as hidden', () {
      final team = deriveBeaconShowcaseTeam(
        roster: const [_ivan],
        totalCount: 4,
        acquaintanceIds: const {},
        viewerId: 'me',
      );
      expect(team.visible.map((p) => p.id), ['ivan']);
      expect(team.hiddenCount, 3);
      expect(team.total, 4);
    });

    test('never lists the viewer', () {
      final team = deriveBeaconShowcaseTeam(
        roster: const [_me, _ivan],
        totalCount: 2,
        acquaintanceIds: const {'me'},
        viewerId: 'me',
      );
      expect(team.visible.map((p) => p.id), ['ivan']);
    });
  });

  group('beaconShowcaseTeamCaption', () {
    BeaconShowcaseTeam team(List<Profile> known, int total) =>
        BeaconShowcaseTeam(
          visible: known,
          acquaintances: known,
          hiddenCount: total - known.length,
        );

    test('invites to be first when nobody is in', () {
      expect(
        beaconShowcaseTeamCaption(_l10n, team(const [], 0)),
        _l10n.beaconShowcaseTeamEmpty,
      );
    });

    test('counts heads when the viewer knows nobody', () {
      expect(
        beaconShowcaseTeamCaption(_l10n, team(const [], 3)),
        _l10n.beaconShowcaseTeamNoAcquaintances(3),
      );
    });

    test('names up to two acquaintances, then counts the rest', () {
      expect(
        beaconShowcaseTeamCaption(_l10n, team(const [_ivan], 2)),
        'People you know: Ivan',
      );
      expect(
        beaconShowcaseTeamCaption(_l10n, team(const [_ivan, _olga, _max], 3)),
        'People you know: Ivan, Olga and 1 more',
      );
    });
  });

  group('beaconStepEditorName', () {
    test('resolves the last editor of the next step', () {
      expect(
        beaconStepEditorName(
          _state(
            roster: const [_olga],
            cue: BeaconRoomState(
              beaconId: 'B1',
              updatedAt: DateTime(2026),
              currentLine: 'Frame on Saturday',
              updatedBy: 'olga',
            ),
          ),
        ),
        'Olga',
      );
    });
  });

  // #516: the next step still names someone who left after it was set.
  group('beaconStepLeaverName', () {
    const omar = Profile(id: 'omar', displayName: 'Omar Dinner');
    final setAt = DateTime(2026, 1, 1, 10);
    BeaconRoomState cue(String line) => BeaconRoomState(
      beaconId: 'B1',
      updatedAt: setAt,
      currentLine: line,
      updatedBy: 'author',
    );
    TimelineHelpOffer offer({required bool withdrawn, required DateTime at}) =>
        TimelineHelpOffer(
          user: omar,
          message: '',
          createdAt: DateTime(2026),
          updatedAt: at,
          isWithdrawn: withdrawn,
        );

    test('names a person who withdrew after the step was set', () {
      expect(
        beaconStepLeaverName(
          _state(
            cue: cue('Omar: dolly'),
            offers: [offer(withdrawn: true, at: DateTime(2026, 1, 1, 11))],
          ),
        ),
        'Omar Dinner',
      );
    });

    test('a step written after the leave, another name, or an active '
        'offer is not flagged', () {
      final later = DateTime(2026, 1, 1, 11);
      expect(
        beaconStepLeaverName(
          _state(
            cue: cue('Omar: dolly'),
            offers: [offer(withdrawn: true, at: DateTime(2026, 1, 1, 9))],
          ),
        ),
        isNull,
      );
      expect(
        beaconStepLeaverName(
          _state(
            cue: cue('Nina: van'),
            offers: [offer(withdrawn: true, at: later)],
          ),
        ),
        isNull,
      );
      expect(
        beaconStepLeaverName(
          _state(
            cue: cue('Omar: dolly'),
            offers: [offer(withdrawn: false, at: later)],
          ),
        ),
        isNull,
      );
    });
  });

  group('widgets', () {
    Future<void> pump(WidgetTester tester, Widget child) => tester.pumpWidget(
      MaterialApp(
        theme: TenturaTheme.light(),
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        home: Scaffold(body: child),
      ),
    );

    testWidgets('the team strip names acquaintances and counts the rest', (
      tester,
    ) async {
      await pump(
        tester,
        BeaconShowcaseTeamStrip(
          team: deriveBeaconShowcaseTeam(
            roster: const [_ivan, _olga],
            totalCount: 4,
            acquaintanceIds: const {},
            viewerId: 'me',
          ),
        ),
      );
      expect(find.text('HELPING'), findsOneWidget);
      expect(find.text('+2'), findsOneWidget);
      expect(find.text('People you know: Olga'), findsOneWidget);
      expect(find.byType(TenturaAvatar), findsNWidgets(2));
    });

    testWidgets('the pinned HUD shows the attributed next step', (
      tester,
    ) async {
      await pump(
        tester,
        BeaconHudPinnedBlock(
          state: _state(
            access: BeaconAccessLevel.member,
            roster: const [_olga],
            helperCount: 1,
            cue: BeaconRoomState(
              beaconId: 'B1',
              updatedAt: DateTime(2026, 1, 1, 10),
              currentLine: 'Frame on Saturday',
              openBlockerTitle: 'No gate key',
              updatedBy: 'olga',
            ),
          ),
          now: DateTime(2026, 1, 1, 12),
          onEditStep: () {},
        ),
      );
      expect(find.textContaining('No gate key'), findsNothing);
      expect(find.textContaining('Frame on Saturday'), findsOneWidget);
      expect(find.textContaining('Olga · '), findsOneWidget);
      expect(find.bySemanticsLabel('2 people in the team'), findsOneWidget);
      expect(find.text('2 people'), findsOneWidget);
    });

    testWidgets('the next step is flagged when a person it names left', (
      tester,
    ) async {
      await pump(
        tester,
        BeaconHudPinnedBlock(
          state: _state(
            access: BeaconAccessLevel.member,
            cue: BeaconRoomState(
              beaconId: 'B1',
              updatedAt: DateTime(2026, 1, 1, 10),
              currentLine: 'Omar: dolly',
              updatedBy: 'author',
            ),
            offers: [
              TimelineHelpOffer(
                user: const Profile(id: 'omar', displayName: 'Omar Dinner'),
                message: '',
                createdAt: DateTime(2026),
                updatedAt: DateTime(2026, 1, 1, 11),
                isWithdrawn: true,
              ),
            ],
          ),
          now: DateTime(2026, 1, 1, 12),
        ),
      );
      expect(find.byKey(beaconHudStepLeaverFlagKey), findsOneWidget);
      expect(
        find.text('Omar Dinner left after this was set'),
        findsOneWidget,
      );
    });

    testWidgets('a long description folds behind Read more', (tester) async {
      await pump(
        tester,
        BeaconShowcaseDescription(
          text: List.filled(40, 'We build three garden beds.').join(' '),
          collapsedLines: 2,
        ),
      );
      expect(find.text('Read more'), findsOneWidget);
      await tester.tap(find.text('Read more'));
      await tester.pump();
      expect(find.text('Show less'), findsOneWidget);
    });
  });
}
