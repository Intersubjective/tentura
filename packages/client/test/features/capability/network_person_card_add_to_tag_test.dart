import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/capability/ui/widget/network_person_card.dart';
import 'package:tentura/features/people_tags/domain/use_case/people_tags_case.dart';
import 'package:tentura/features/profile/ui/bloc/profile_cubit.dart';
import 'package:tentura/ui/bloc/presence_cubit.dart';
import 'package:tentura/ui/bloc/screen_cubit.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura_root/domain/enums.dart';

import '../../support/add_to_tag_sheet_probe.dart';
import '../../support/fake_people_tags_repository.dart';
import '../../support/optional_gate_call.dart';

const _viewer = Profile(id: 'U-viewer', displayName: 'Viewer');
const _peer = Profile(id: 'U-peer', displayName: 'Peer Person');

class _FakeProfileCubit implements ProfileCubit {
  _FakeProfileCubit(Profile profile) : _state = ProfileState(profile: profile);

  final ProfileState _state;

  @override
  ProfileState get state => _state;

  @override
  Stream<ProfileState> get stream => Stream.value(_state);

  @override
  Future<void> close() async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakePresenceCubit implements PresenceCubit {
  @override
  Map<String, UserPresenceStatus> get state => const {};

  @override
  Stream<Map<String, UserPresenceStatus>> get stream => Stream.value(state);

  @override
  Future<void> close() async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late PeopleTagsTestRig rig;

  setUp(() async {
    rig = await PeopleTagsTestRig.create(addToTagProbeRepository(_peer.id));
    GetIt.I.registerSingleton<PeopleTagsCase>(rig.peopleTags);
  });

  tearDown(() async {
    await GetIt.I.reset();
    await rig.dispose();
  });

  /// [peopleTagsEnabled] null leaves the card's own default (the gate).
  Future<void> pumpCard(
    WidgetTester tester, {
    Profile profile = _peer,
    bool? peopleTagsEnabled,
  }) async {
    final screenCubit = ScreenCubit.local();
    addTearDown(screenCubit.close);
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        theme: TenturaTheme.light(),
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        home: MediaQuery(
          data: const MediaQueryData(size: Size(400, 800)),
          child: TenturaResponsiveScope(
            child: MultiBlocProvider(
              providers: [
                BlocProvider<ProfileCubit>.value(
                  value: _FakeProfileCubit(_viewer),
                ),
                BlocProvider<PresenceCubit>.value(value: _FakePresenceCubit()),
                BlocProvider<ScreenCubit>.value(value: screenCubit),
              ],
              child: Scaffold(
                body:
                    callWithPeopleTagsGate(
                          NetworkPersonCard.new,
                          gate: peopleTagsEnabled,
                          named: {#profile: profile},
                        )
                        as Widget,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  final overflowButton = find.byIcon(Icons.more_vert);

  group('Friends card: add to tag', () {
    testWidgets('the overflow button opens a menu with "Add to tag…"', (
      tester,
    ) async {
      await pumpCard(tester, peopleTagsEnabled: true);
      expect(find.text('Add to tag…'), findsNothing);

      await tester.tap(overflowButton);
      await tester.pumpAndSettle();

      expect(find.text('Add to tag…'), findsOneWidget);
    });

    testWidgets('a touch long press opens the same menu', (tester) async {
      await pumpCard(tester, peopleTagsEnabled: true);

      await tester.longPress(find.text('Peer Person'));
      await tester.pumpAndSettle();

      expect(find.text('Add to tag…'), findsOneWidget);
    });

    testWidgets('a mouse secondary tap opens the same menu', (tester) async {
      await pumpCard(tester, peopleTagsEnabled: true);

      final gesture = await tester.startGesture(
        tester.getCenter(find.text('Peer Person')),
        kind: PointerDeviceKind.mouse,
        buttons: kSecondaryMouseButton,
      );
      await gesture.up();
      await tester.pumpAndSettle();

      expect(find.text('Add to tag…'), findsOneWidget);
    });

    testWidgets('a plain tap on the card opens no menu', (tester) async {
      await pumpCard(tester, peopleTagsEnabled: true);

      await tester.tap(find.text('Peer Person'));
      await tester.pumpAndSettle();

      expect(find.text('Add to tag…'), findsNothing);
    });

    for (final way in _OpenWay.values)
      testWidgets(
        '"Add to tag…" opened by ${way.name} opens the sheet for the card '
        'person',
        (tester) async {
          await pumpCard(tester, peopleTagsEnabled: true);

          await way.open(tester, overflowButton, find.text('Peer Person'));
          await tester.tap(find.text('Add to tag…'));

          await expectAddToTagSheetIsForPerson(
            tester,
            rig.repository,
            _peer.id,
          );
        },
      );

    testWidgets('a self row has no overflow button and no long-press menu', (
      tester,
    ) async {
      await pumpCard(
        tester,
        profile: const Profile(id: 'U-viewer', displayName: 'Viewer'),
        peopleTagsEnabled: true,
      );

      expect(overflowButton, findsNothing);
      await tester.longPress(find.text('You'));
      await tester.pumpAndSettle();
      expect(find.text('Add to tag…'), findsNothing);
    });

    testWidgets('is absent when the feature is switched off', (tester) async {
      await pumpCard(tester, peopleTagsEnabled: false);

      expect(overflowButton, findsNothing);
      await tester.longPress(find.text('Peer Person'));
      await tester.pumpAndSettle();
      expect(find.text('Add to tag…'), findsNothing);
    });

    testWidgets('is absent by default while the feature gate is off', (
      tester,
    ) async {
      await pumpCard(tester);

      expect(overflowButton, findsNothing);
      await tester.longPress(find.text('Peer Person'));
      await tester.pumpAndSettle();
      expect(find.text('Add to tag…'), findsNothing);
    });
  });
}

/// The three ways a person opens a Friends card's menu.
enum _OpenWay {
  overflowTap,
  touchLongPress,
  mouseSecondaryTap;

  Future<void> open(WidgetTester tester, Finder overflow, Finder card) async {
    switch (this) {
      case overflowTap:
        await tester.tap(overflow);
      case touchLongPress:
        await tester.longPress(card);
      case mouseSecondaryTap:
        final gesture = await tester.startGesture(
          tester.getCenter(card),
          kind: PointerDeviceKind.mouse,
          buttons: kSecondaryMouseButton,
        );
        await gesture.up();
    }
    await tester.pumpAndSettle();
  }
}
