// #930: on an iPhone SE in Russian the pin mark in someone else's (narrower)
// bubble read «Закреплено · факт обсу…». It wraps to two lines instead; the
// public and private marks share one layout. Measured with the app font.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';

import 'package:tentura/design_system/tentura_responsive_scope.dart';
import 'package:tentura/design_system/tentura_theme.dart';
import 'package:tentura/domain/entity/beacon_fact_card.dart';
import 'package:tentura/domain/entity/beacon_fact_card_consts.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/domain/entity/room_message.dart';
import 'package:tentura/features/beacon_threads/ui/widget/room_message_tile.dart';
import 'package:tentura/features/profile/ui/bloc/profile_cubit.dart';
import 'package:tentura/ui/bloc/presence_cubit.dart';
import 'package:tentura/ui/bloc/screen_cubit.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura_root/domain/enums.dart';

import '../../support/phone_surface.dart';

class _MockProfileCubit extends Mock implements ProfileCubit {
  @override
  ProfileState get state => const ProfileState(
    profile: Profile(id: 'viewer', displayName: 'Me'),
  );

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

BeaconFactCard _publicFact() => BeaconFactCard(
  id: 'f1',
  beaconId: 'b1',
  factText: 'Pinned text',
  visibility: BeaconFactCardVisibilityBits.public,
  pinnedBy: 'u1',
  createdAt: DateTime.utc(2026),
  status: BeaconFactCardStatusBits.active,
  sourceMessageId: 'm1',
);

RoomMessage _message() => RoomMessage(
  id: 'm1',
  beaconId: 'b1',
  authorId: 'u1',
  author: const Profile(id: 'u1', displayName: 'Author'),
  body: 'Source message body',
  createdAt: DateTime.utc(2026),
);

Widget _harness({
  required BeaconFactCard? pinnedFact,
  required Locale locale,
  required Size size,
  required String viewerId,
}) {
  return MultiBlocProvider(
    providers: [
      BlocProvider<ProfileCubit>.value(value: _MockProfileCubit()),
      BlocProvider<PresenceCubit>.value(value: _MockPresenceCubit()),
      BlocProvider<ScreenCubit>(create: (_) => ScreenCubit.local()),
    ],
    child: MaterialApp(
      theme: TenturaTheme.light(),
      localizationsDelegates: L10n.localizationsDelegates,
      supportedLocales: L10n.supportedLocales,
      locale: locale,
      home: MediaQuery(
        data: MediaQueryData(size: size),
        child: TenturaResponsiveScope(
          child: Scaffold(
            body: RoomMessageTile(
              message: _message(),
              myProfile: Profile(id: viewerId, displayName: 'Me'),
              onToggleReaction: (_, _) async {},
              pinnedFact: pinnedFact,
            ),
          ),
        ),
      ),
    ),
  );
}

Future<void> _loadInter() async {
  final loader = FontLoader('Inter');
  for (final weight in const ['Regular', 'Medium', 'SemiBold', 'Bold']) {
    final bytes = File('fonts/Inter-$weight.ttf').readAsBytesSync();
    loader.addFont(Future.value(ByteData.sublistView(bytes)));
  }
  await loader.load();
}

void main() {
  setUpAll(_loadInter);

  const sizes = {
    '375x667': kPhoneSurface,
    'desktop 1280x800': Size(1280, 800),
  };
  // (visibility, own bubble?, viewer)
  final cases = [
    (BeaconFactCardVisibilityBits.room, 'incoming private', 'viewer'),
    (BeaconFactCardVisibilityBits.public, 'outgoing public', 'u1'),
    (BeaconFactCardVisibilityBits.public, 'incoming public', 'viewer'),
    (BeaconFactCardVisibilityBits.room, 'outgoing private', 'u1'),
  ];

  for (final locale in const [Locale('ru'), Locale('en')]) {
    final l10n = lookupL10n(locale);
    for (final MapEntry(key: sizeName, value: size) in sizes.entries) {
      for (final (visibility, name, viewerId) in cases) {
        testWidgets('${locale.languageCode} $sizeName: $name pin mark shows '
            'in full', (tester) async {
          if (size == kPhoneSurface) {
            await usePhoneSurface(tester);
          } else {
            tester.view
              ..physicalSize = size
              ..devicePixelRatio = 1;
            addTearDown(tester.view.reset);
          }
          await tester.pumpWidget(
            _harness(
              pinnedFact: _publicFact().copyWith(visibility: visibility),
              locale: locale,
              size: size,
              viewerId: viewerId,
            ),
          );
          await tester.pumpAndSettle();

          final label = visibility == BeaconFactCardVisibilityBits.public
              ? l10n.beaconRoomMessagePinnedFactChipPublic
              : l10n.beaconRoomMessagePinnedFactChipPrivate;
          final text = find.text(label);
          expect(text, findsOneWidget);
          final paragraph = tester.renderObject<RenderParagraph>(
            find.descendant(of: text, matching: find.byType(RichText)),
          );
          expect(paragraph.didExceedMaxLines, isFalse, reason: '$label is cut');
          expect(tester.takeException(), isNull);
        });
      }
    }
  }
}
