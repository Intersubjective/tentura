// #785: on a 375 px phone, People-tab help-offer cards must not squeeze the
// role/status line or the name against a trailing participation badge. The
// full status copy stays readable; long names ellipsize on one line.

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/beacon_participant.dart';
import 'package:tentura/domain/entity/beacon_room_consts.dart';
import 'package:tentura/domain/entity/commitment_stake_state.dart';
import 'package:tentura/domain/entity/coordination_response_type.dart';
import 'package:tentura/domain/entity/help_offer_admission_action.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/beacon_view/ui/bloc/beacon_view_state.dart';
import 'package:tentura/ui/presenter/beacon_people_labels.dart';
import 'package:tentura/features/beacon_view/ui/widget/help_offer_tile.dart';
import 'package:tentura/features/profile/ui/bloc/profile_cubit.dart';
import 'package:tentura/ui/bloc/screen_cubit.dart';
import 'package:tentura/ui/l10n/l10n.dart';

class _MockProfileCubit extends Mock implements ProfileCubit {
  @override
  ProfileState get state => const ProfileState(
    profile: Profile(id: 'author', displayName: 'Author'),
  );

  @override
  Stream<ProfileState> get stream => Stream<ProfileState>.value(state);
}

const _phone = Size(375, 667);
final _t = DateTime.utc(2026, 10, 1);

Future<void> _pumpTile(
  WidgetTester tester, {
  required TimelineHelpOffer offer,
  BeaconParticipant? participant,
  Locale locale = const Locale('en'),
}) async {
  tester.view
    ..physicalSize = _phone
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MaterialApp(
      locale: locale,
      localizationsDelegates: L10n.localizationsDelegates,
      supportedLocales: L10n.supportedLocales,
      theme: TenturaTheme.light(),
      home: MultiBlocProvider(
        providers: [
          BlocProvider<ProfileCubit>.value(value: _MockProfileCubit()),
          BlocProvider(create: (_) => ScreenCubit.local()),
        ],
        child: Scaffold(
          body: SingleChildScrollView(
            child: HelpOfferTile(
              helpOffer: offer,
              beaconId: 'B1',
              beaconAuthor: const Profile(id: 'author', displayName: 'Author'),
              beaconAuthorId: 'author',
              isAuthorView: true,
              participant: participant,
              showBackupHint: false,
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void _expectWholeLine(WidgetTester tester, String text) {
  final finder = find.text(text);
  expect(finder, findsOneWidget);
  final paragraph = tester.renderObject<RenderParagraph>(finder);
  expect(paragraph.text.toPlainText(), text);
  expect(paragraph.didExceedMaxLines, isFalse, reason: 'cut: $text');
}

int _lineCount(RenderParagraph paragraph) {
  final painter = TextPainter(
    text: paragraph.text,
    textDirection: TextDirection.ltr,
    textScaler: paragraph.textScaler,
    locale: paragraph.locale,
  )..layout(maxWidth: paragraph.size.width);
  final lines = painter.computeLineMetrics().length;
  painter.dispose();
  return lines;
}

void main() {
  group('#785 participation ended card at 375 px', () {
    TimelineHelpOffer endedOffer({required String displayName}) =>
        TimelineHelpOffer(
          user: Profile(id: 'h1', displayName: displayName),
          message: '',
          createdAt: _t,
          updatedAt: _t,
          coordinationResponse: CoordinationResponseType.useful,
          admissionAction: HelpOfferAdmissionAction.remove,
          stakeState: CommitmentStakeState.released,
          roomAccess: RoomAccessBits.none,
        );

    BeaconParticipant endedParticipant() => BeaconParticipant(
      id: 'p1',
      beaconId: 'B1',
      userId: 'h1',
      role: BeaconParticipantRoleBits.helper,
      status: BeaconParticipantStatusBits.committed,
      roomAccess: RoomAccessBits.none,
      createdAt: _t,
      updatedAt: _t,
    );

    for (final locale in const [Locale('en'), Locale('ru')]) {
      testWidgets('${locale.languageCode}: role line and badge stay readable', (
        tester,
      ) async {
        final l10n = lookupL10n(locale);
        final offer = endedOffer(displayName: 'Alex');
        final participant = endedParticipant();
        final roleLine =
            '${beaconPeopleRoleLabel(l10n, participant.role)} · '
            '${beaconPeopleStatusLabel(
              l10n,
              participant.status,
              offer.coordinationResponse,
              admissionAction: offer.admissionAction,
            )}';

        await _pumpTile(
          tester,
          offer: offer,
          participant: participant,
          locale: locale,
        );

        _expectWholeLine(tester, roleLine);
        _expectWholeLine(tester, l10n.helpOfferParticipationEndedLabel);

        final roleParagraph = tester.renderObject<RenderParagraph>(
          find.text(roleLine),
        );
        // Test font glyphs are wider than the app font; three lines is fine
        // if the full role line is present and not ellipsized.
        expect(
          _lineCount(roleParagraph),
          lessThanOrEqualTo(3),
          reason: 'role line should wrap at words, not fragment',
        );
        expect(tester.takeException(), isNull);
      });
    }
  });

  group('#785 admitted helper badge at 375 px (RU)', () {
    testWidgets('long name ellipsizes; offering-help badge is whole', (
      tester,
    ) async {
      const locale = Locale('ru');
      final l10n = lookupL10n(locale);
      final offer = TimelineHelpOffer(
        user: const Profile(id: 'h1', displayName: 'Bob GQ2'),
        message: '',
        createdAt: _t,
        updatedAt: _t,
        coordinationResponse: CoordinationResponseType.useful,
        admissionAction: HelpOfferAdmissionAction.accept,
        stakeState: CommitmentStakeState.acknowledged,
        roomAccess: RoomAccessBits.admitted,
      );
      final participant = BeaconParticipant(
        id: 'p1',
        beaconId: 'B1',
        userId: 'h1',
        role: BeaconParticipantRoleBits.helper,
        status: BeaconParticipantStatusBits.committed,
        roomAccess: RoomAccessBits.admitted,
        createdAt: _t,
        updatedAt: _t,
      );

      await _pumpTile(
        tester,
        offer: offer,
        participant: participant,
        locale: locale,
      );

      final nameFinder = find.text('Bob GQ2');
      expect(nameFinder, findsOneWidget);
      final nameParagraph = tester.renderObject<RenderParagraph>(nameFinder);
      expect(_lineCount(nameParagraph), 1);

      _expectWholeLine(tester, l10n.beaconPeopleStatusHelpOffered);
      expect(tester.takeException(), isNull);
    });
  });
}
