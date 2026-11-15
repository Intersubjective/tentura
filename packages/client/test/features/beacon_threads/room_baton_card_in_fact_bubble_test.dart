// The author's baton card keeps its layout inside a bubble that also carries
// a pinned-fact ribbon or a quoted fact: each recipient's name stays on one
// line (ellipsis), the name column does not collapse, and the answer status
// sits at the right. Phone 375x667, Russian, app font.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:tentura_root/domain/enums.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/beacon_fact_card.dart';
import 'package:tentura/domain/entity/beacon_fact_card_consts.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/domain/entity/quoted_fact.dart';
import 'package:tentura/domain/entity/room_baton_data.dart';
import 'package:tentura/domain/entity/room_message.dart';
import 'package:tentura/features/beacon_threads/ui/widget/room_baton_card.dart';
import 'package:tentura/features/beacon_threads/ui/widget/room_message_fact_quote.dart';
import 'package:tentura/features/beacon_threads/ui/widget/room_message_tile.dart';
import 'package:tentura/features/beacon_threads/ui/widget/room_pinned_fact_visibility_mark.dart';
import 'package:tentura/features/profile/ui/bloc/profile_cubit.dart';
import 'package:tentura/ui/bloc/presence_cubit.dart';
import 'package:tentura/ui/bloc/screen_cubit.dart';
import 'package:tentura/ui/l10n/l10n.dart';

import '../../support/phone_surface.dart';

const _author = Profile(id: 'u-anna', displayName: 'Anna Author');

const _names = [
  'Константин Александрович Верхнеднепровский',
  'Анастасия Владимировна Новосёлова-Белозёрская',
  'Святослав Игоревич Чернышевский-Подольский',
];

class _MockProfileCubit extends Mock implements ProfileCubit {
  @override
  ProfileState get state => const ProfileState(profile: _author);

  @override
  Stream<ProfileState> get stream => Stream<ProfileState>.value(state);
}

class _MockPresenceCubit extends Mock implements PresenceCubit {
  @override
  Map<String, UserPresenceStatus> get state => const {};

  @override
  Stream<Map<String, UserPresenceStatus>> get stream =>
      Stream<Map<String, UserPresenceStatus>>.value(state);
}

RoomBatonAuthorData _baton({List<int> tiers = const [1, 1, 1]}) =>
    RoomBatonAuthorData(
      id: 'baton-1',
      status: RoomBatonStatus.collecting,
      candidates: [
        for (var i = 0; i < 3; i++)
          RoomBatonCandidate(
            userId: 'u$i',
            title: _names[i],
            tier: tiers[i],
            response: _responses[i],
          ),
      ],
      allAnswered: false,
      eligibleCount: 1,
    );

BeaconFactCard _pinned() => BeaconFactCard(
  id: 'f1',
  beaconId: 'b1',
  factText: 'Pinned text',
  visibility: BeaconFactCardVisibilityBits.public,
  pinnedBy: 'u1',
  createdAt: DateTime.utc(2026),
  status: BeaconFactCardStatusBits.active,
  sourceMessageId: 'm1',
);

const _quoted = QuotedFact(
  factCardId: 'f1',
  seq: 1,
  currentSeq: 1,
  status: BeaconFactCardStatusBits.active,
  factText: 'Quoted fact text',
);

/// Snapshot of the card width in a plain message at 375 dp, ru, Inter, taken
/// before the fix; the card must keep it (tolerance 1 dp).
const _plainCardWidthSnapshot = 212.97;

enum _Bubble { plain, pinned, quoted }

Widget _harness(_Bubble bubble, RoomBatonAuthorData baton) => MultiBlocProvider(
  providers: [
    BlocProvider<ProfileCubit>.value(value: _MockProfileCubit()),
    BlocProvider<PresenceCubit>.value(value: _MockPresenceCubit()),
    BlocProvider<ScreenCubit>(create: (_) => ScreenCubit.local()),
  ],
  child: MaterialApp(
    theme: TenturaTheme.light(),
    localizationsDelegates: L10n.localizationsDelegates,
    supportedLocales: L10n.supportedLocales,
    locale: const Locale('ru'),
    home: MediaQuery(
      data: const MediaQueryData(size: kPhoneSurface),
      child: TenturaResponsiveScope(
        child: Scaffold(
          body: SingleChildScrollView(
            child: RoomMessageTile(
              message: RoomMessage(
                id: 'm1',
                beaconId: 'b1',
                authorId: _author.id,
                author: _author,
                body: 'Кто сможет подвезти?',
                createdAt: DateTime.utc(2026),
                baton: baton,
                quotedFact: bubble == _Bubble.quoted ? _quoted : null,
              ),
              myProfile: _author,
              onToggleReaction: (_, _) async {},
              pinnedFact: bubble == _Bubble.pinned ? _pinned() : null,
            ),
          ),
        ),
      ),
    ),
  ),
);

Future<void> _loadInter() async {
  final loader = FontLoader('Inter');
  for (final weight in const ['Regular', 'Medium', 'SemiBold', 'Bold']) {
    final bytes = File('fonts/Inter-$weight.ttf').readAsBytesSync();
    loader.addFont(Future.value(ByteData.sublistView(bytes)));
  }
  await loader.load();
}

Future<void> _pump(
  WidgetTester tester,
  _Bubble bubble,
  RoomBatonAuthorData baton,
) async {
  await usePhoneSurface(tester);
  await tester.pumpWidget(_harness(bubble, baton));
  await tester.pump();
}

/// What the plain (own-message) layout measures; the fix must reproduce it
/// inside the fact bubbles.
class _Reference {
  _Reference({
    required this.lineHeight,
    required this.avatarHeight,
    required this.cardWidth,
    required this.nameWidths,
  });

  /// One line of bodySmall (the one-word status).
  final double lineHeight;
  final double avatarHeight;
  final double cardWidth;
  final List<double> nameWidths;
}

const _responses = [
  RoomBatonResponse.canHelp,
  RoomBatonResponse.waiting,
  RoomBatonResponse.cantHelp,
];

String _statusText(L10n l10n, RoomBatonResponse r) => switch (r) {
  RoomBatonResponse.canHelp => l10n.batonStatusCanHelp,
  RoomBatonResponse.waiting => l10n.batonStatusWaiting,
  RoomBatonResponse.cantHelp => l10n.batonStatusCantHelp,
};

/// The Row holding both [name] and [status] (the candidate's row, never a
/// nested Row that only wraps one of them).
Finder _rowOf(Finder name, Finder status) {
  final rows = find.ancestor(of: name, matching: find.byType(Row));
  for (final row in rows.evaluate()) {
    final own = find.byElementPredicate((e) => identical(e, row));
    if (find.descendant(of: own, matching: status).evaluate().isNotEmpty) {
      return own;
    }
  }
  return rows; // no such Row: the following assertions fail
}

Future<_Reference> _measurePlain(WidgetTester tester, L10n l10n) async {
  await _pump(tester, _Bubble.plain, _baton());
  return _Reference(
    lineHeight: tester
        .getSize(find.text(_statusText(l10n, RoomBatonResponse.canHelp)))
        .height,
    avatarHeight: tester.getSize(find.byType(TenturaAvatar).first).height,
    cardWidth: tester.getSize(find.byType(RoomBatonCard)).width,
    nameWidths: [
      for (final n in _names) tester.getSize(find.text(n)).width,
    ],
  );
}

void _expectRowsLaidOutAsInOwnMessage(
  WidgetTester tester,
  _Reference ref,
  L10n l10n, {
  List<int> tiers = const [1, 1, 1],
  bool checkNames = true,
}) {
  expect(find.byType(RoomBatonCard), findsOneWidget);
  expect(tester.takeException(), isNull);
  final showTiers = tiers.toSet().length > 1;
  double? statusRight;
  for (var i = 0; i < 3; i++) {
    final nameFinder = find.text(_names[i]);
    final statusFinder = find.text(_statusText(l10n, _responses[i]));
    final row = _rowOf(nameFinder, statusFinder);
    expect(row, findsOneWidget, reason: 'row $i holds name and status');

    if (checkNames) {
      final name = tester.widget<Text>(nameFinder);
      expect(name.maxLines, 1, reason: 'name $i maxLines');
      expect(name.overflow, TextOverflow.ellipsis, reason: 'name $i overflow');
      final nameSize = tester.getSize(nameFinder);
      expect(nameSize.height, closeTo(ref.lineHeight, 0.5), reason: 'name $i');
      expect(nameSize.width, greaterThan(40), reason: 'name $i collapsed');
      if (!showTiers) {
        expect(
          nameSize.width,
          greaterThanOrEqualTo(ref.nameWidths[i] * 0.5),
          reason: 'name $i keeps at least half its own-message width',
        );
      }
      expect(
        tester.getSize(row).height,
        lessThanOrEqualTo(ref.avatarHeight + 0.5),
        reason: 'row $i no taller than the avatar',
      );
      expect(
        tester.getTopLeft(statusFinder).dx,
        greaterThanOrEqualTo(tester.getTopRight(nameFinder).dx - 0.5),
        reason: 'status $i is right of name',
      );
    }

    expect(
      tester.getSize(statusFinder).height,
      closeTo(ref.lineHeight, 0.5),
      reason: 'status $i is one line',
    );
    final right = tester.getTopRight(statusFinder).dx;
    statusRight ??= right;
    expect(right, closeTo(statusRight, 1), reason: 'status $i right edge');

    if (showTiers) {
      final tier = find.descendant(
        of: row,
        matching: find.text(l10n.batonTierLabel(tiers[i])),
      );
      expect(tier, findsOneWidget, reason: 'tier label $i in the name row');
      expect(
        tester.getSize(tier).height,
        closeTo(ref.lineHeight, 0.5),
        reason: 'tier label $i is one line',
      );
      expect(
        tester.getTopRight(tier).dx,
        lessThanOrEqualTo(tester.getTopLeft(statusFinder).dx + 0.5),
        reason: 'tier label $i is left of status',
      );
      if (checkNames) {
        expect(
          tester.getTopLeft(tier).dx,
          greaterThanOrEqualTo(tester.getTopRight(nameFinder).dx - 0.5),
          reason: 'tier label $i is right of name',
        );
      }
    }
  }
}

void main() {
  setUpAll(_loadInter);
  final l10n = lookupL10n(const Locale('ru'));

  group('RoomBatonCard inside a pinned-fact bubble', () {
    testWidgets('each long recipient name stays on one line, status at right', (
      tester,
    ) async {
      final ref = await _measurePlain(tester, l10n);
      await _pump(tester, _Bubble.pinned, _baton());
      expect(find.byType(RoomPinnedFactVisibilityMark), findsOneWidget);
      _expectRowsLaidOutAsInOwnMessage(tester, ref, l10n);
    });

    testWidgets('name, tier label and status each stay on one line', (
      tester,
    ) async {
      final ref = await _measurePlain(tester, l10n);
      const tiers = [1, 2, 1];
      await _pump(tester, _Bubble.pinned, _baton(tiers: tiers));
      expect(find.byType(RoomPinnedFactVisibilityMark), findsOneWidget);
      _expectRowsLaidOutAsInOwnMessage(tester, ref, l10n, tiers: tiers);
    });
  });

  group('RoomBatonCard inside a quoted-fact bubble', () {
    testWidgets('each long recipient name stays on one line, status at right', (
      tester,
    ) async {
      final ref = await _measurePlain(tester, l10n);
      await _pump(tester, _Bubble.quoted, _baton());
      expect(find.byType(RoomMessageFactQuote), findsOneWidget);
      expect(
        tester.getBottomLeft(find.byType(RoomMessageFactQuote)).dy,
        lessThanOrEqualTo(tester.getTopLeft(find.byType(RoomBatonCard)).dy),
        reason: 'the fact quote is above the baton card',
      );
      _expectRowsLaidOutAsInOwnMessage(tester, ref, l10n);
    });
  });

  group('RoomBatonCard in a plain message', () {
    testWidgets(
      'keeps its card width, one-line status at right and no overflow',
      (
        tester,
      ) async {
        final ref = await _measurePlain(tester, l10n);
        await _pump(tester, _Bubble.plain, _baton());
        expect(find.byType(RoomMessageFactQuote), findsNothing);
        expect(find.byType(RoomPinnedFactVisibilityMark), findsNothing);
        // Card width measured before the fix (own-message layout, 375 dp, ru).
        expect(ref.cardWidth, closeTo(_plainCardWidthSnapshot, 1));
        _expectRowsLaidOutAsInOwnMessage(tester, ref, l10n, checkNames: false);
      },
    );
  });
}
