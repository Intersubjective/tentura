import 'dart:ui' show SemanticsAction, SemanticsFlag;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/beacon_participant.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/domain/entity/room_poll_data.dart';
import 'package:tentura/features/beacon_threads/ui/widget/room_poll_card.dart';
import 'package:tentura/features/profile/ui/bloc/profile_cubit.dart';
import 'package:tentura/ui/l10n/l10n.dart';

class _MockProfileCubit extends Mock implements ProfileCubit {
  @override
  ProfileState get state => const ProfileState(
    profile: Profile(id: 'viewer', displayName: 'Me'),
  );

  @override
  Stream<ProfileState> get stream => Stream<ProfileState>.value(state);
}

BeaconParticipant _participant(String id, String name) => BeaconParticipant(
  id: 'participant-$id',
  beaconId: 'beacon-1',
  userId: id,
  userTitle: name,
  role: 0,
  status: 0,
  roomAccess: 0,
  createdAt: DateTime.utc(2026),
  updatedAt: DateTime.utc(2026),
);

const _totalVoters = 3;

Widget _app({required bool anonymous, required bool author}) =>
    BlocProvider<ProfileCubit>.value(
      value: _MockProfileCubit(),
      child: MaterialApp(
        theme: TenturaTheme.light(),
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        locale: const Locale('en'),
        home: Scaffold(
          body: SingleChildScrollView(
            child: RoomPollCard(
              poll: RoomPollData(
                id: 'poll-1',
                question: 'Which day works?',
                isAnonymous: anonymous,
                allowRevote: false,
                totalVotes: _totalVoters,
                myVariantIds: author ? const [] : const ['sunday'],
                variants: const [
                  RoomPollVariant(
                    id: 'sunday',
                    description: 'Sunday',
                    votesCount: 2,
                    voterIds: ['voter-alice', 'voter-bob'],
                  ),
                  RoomPollVariant(
                    id: 'saturday',
                    description: 'Saturday',
                    votesCount: 1,
                    voterIds: ['voter-carol'],
                  ),
                ],
              ),
              isAuthor: author,
              participants: [
                _participant('voter-alice', 'Alice'),
                _participant('voter-bob', 'Bob'),
                _participant('voter-carol', 'Carol'),
                _participant('non-voter-dana', 'Dana'),
              ],
              onVote: (_, {score}) {},
            ),
          ),
        ),
      ),
    );

void main() {
  for (final author in [false, true]) {
    testWidgets(
      '${author ? 'author without a vote' : 'voter'} opens the voter list from '
      'the vote count only when the poll is non-anonymous',
      (tester) async {
        final semantics = tester.ensureSemantics();

        await tester.pumpWidget(_app(anonymous: true, author: author));
        await tester.pumpAndSettle();

        final l10n = L10n.of(tester.element(find.byType(RoomPollCard)))!;
        final footer = find.text(l10n.beaconRoomPollVotesCount(_totalVoters));
        expect(footer, findsOneWidget);
        final anonymousFooter = tester.getSemantics(footer).getSemanticsData();
        expect(anonymousFooter.hasFlag(SemanticsFlag.isButton), isFalse);
        expect(anonymousFooter.hasAction(SemanticsAction.tap), isFalse);
        semantics.dispose();
        await tester.tap(footer);
        await tester.pumpAndSettle();
        for (final name in ['Alice', 'Bob', 'Carol', 'Dana']) {
          expect(find.text(name), findsNothing);
        }

        await tester.pumpWidget(_app(anonymous: false, author: author));
        await tester.pumpAndSettle();
        expect(footer, findsOneWidget);
        for (final name in ['Alice', 'Bob', 'Carol', 'Dana']) {
          expect(find.text(name), findsNothing);
        }
        await tester.tap(footer);
        await tester.pumpAndSettle();

        for (final name in ['Alice', 'Bob', 'Carol']) {
          expect(find.text(name), findsOneWidget);
        }
        expect(find.text('Dana'), findsNothing);
      },
    );
  }
}
