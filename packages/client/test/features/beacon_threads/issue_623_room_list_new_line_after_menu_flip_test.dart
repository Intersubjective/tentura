// #623: in the request room on web, the author accepting an offer or
// changing status inserts a new line into the chat list and rebuilds the
// existing messages; if a bubble hover had flipped the browser context-menu
// flag since their last build (#456), every message text region crashed on
// re-registration and a grey ErrorWidget replaced part of the list.
//
// kIsWeb is false in VM tests, so the browser-menu flag is driven through
// TenturaSelectionArea.browserContextMenuEnabled. Spec: inserting a line
// and rebuilding the keyed list across a flag flip throws nothing, shows no
// ErrorWidget, every message text is selectable again in a fresh region, and
// the messages already on screen stay on screen.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:tentura_root/domain/enums.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/domain/entity/room_message.dart';
import 'package:tentura/features/beacon_threads/ui/widget/room_message_tile.dart';
import 'package:tentura/features/profile/ui/bloc/profile_cubit.dart';
import 'package:tentura/ui/bloc/presence_cubit.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/widget/tentura_selection_area.dart';

const _viewer = Profile(id: 'me', displayName: 'Me');
const _helper = Profile(id: 'helper', displayName: 'Helper');

class _MockProfileCubit extends Mock implements ProfileCubit {
  @override
  ProfileState get state => const ProfileState(profile: _viewer);

  @override
  Stream<ProfileState> get stream => const Stream<ProfileState>.empty();
}

class _MockPresenceCubit extends Mock implements PresenceCubit {
  @override
  Map<String, UserPresenceStatus> get state => const {};

  @override
  Stream<Map<String, UserPresenceStatus>> get stream =>
      const Stream<Map<String, UserPresenceStatus>>.empty();
}

RoomMessage _message(String id, Profile author, String body, int minute) =>
    RoomMessage(
      id: id,
      beaconId: 'b1',
      authorId: author.id,
      author: author,
      body: body,
      createdAt: DateTime.utc(2026, 10, 21, 12, minute),
    );

const _first = 'Bring the ladder on Saturday';
const _second = 'I can bring mine too';
const _inserted = 'Status changed to Final check';

Finder _richText(String text) => find.byWidgetPredicate(
  (w) => w is RichText && w.text.toPlainText().contains(text),
);

void main() {
  late bool browserMenuOn;
  final original = TenturaSelectionArea.browserContextMenuEnabled;

  setUp(() {
    browserMenuOn = true;
    TenturaSelectionArea.browserContextMenuEnabled = () => browserMenuOn;
  });
  tearDown(() => TenturaSelectionArea.browserContextMenuEnabled = original);

  testWidgets(
    '#623 a new line in the room list after a browser-menu flip shows no '
    'error box',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(900, 700));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final messages = [
        _message('m1', _viewer, _first, 0),
        _message('m2', _helper, _second, 1),
      ];
      late StateSetter rebuildList;

      await tester.pumpWidget(
        MultiBlocProvider(
          providers: [
            BlocProvider<ProfileCubit>.value(value: _MockProfileCubit()),
            BlocProvider<PresenceCubit>.value(value: _MockPresenceCubit()),
          ],
          child: MaterialApp(
            locale: const Locale('en'),
            theme: TenturaTheme.light(),
            localizationsDelegates: L10n.localizationsDelegates,
            supportedLocales: L10n.supportedLocales,
            home: Scaffold(
              body: StatefulBuilder(
                builder: (context, setState) {
                  rebuildList = setState;
                  return ListView(
                    children: [
                      for (final m in messages)
                        RoomMessageTile(
                          key: ValueKey(m.id),
                          message: m,
                          myProfile: _viewer,
                          onActionsPressed: (_) {},
                          onReplyPressed: (_) {},
                          onToggleReaction: (_, _) async {},
                        ),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.ancestor(
          of: _richText(_first).first,
          matching: find.byType(SelectionArea),
        ),
        findsOneWidget,
        reason: 'precondition: desktop message text is selectable',
      );
      final regionsBefore = tester
          .stateList<SelectableRegionState>(find.byType(SelectableRegion))
          .toList();
      expect(regionsBefore, isNotEmpty);

      // The pointer crossed a bubble (browser menu off), then the author's
      // status change lands as a new line and the list rebuilds.
      browserMenuOn = false;
      rebuildList(
        () => messages.add(_message('m3', _helper, _inserted, 2)),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.byType(ErrorWidget), findsNothing);
      for (final text in [_first, _second, _inserted]) {
        expect(
          find.ancestor(
            of: _richText(text).first,
            matching: find.byType(SelectionArea),
          ),
          findsOneWidget,
          reason: '"$text" is on screen and selectable',
        );
      }
      final regionsAfter = tester
          .stateList<SelectableRegionState>(find.byType(SelectableRegion))
          .toList();
      for (final old in regionsBefore) {
        expect(
          regionsAfter.any((r) => identical(r, old)),
          isFalse,
          reason:
              'a region built before the flip must not be rebuilt in place '
              '(on web its inner SelectionContainer re-registers and throws)',
        );
      }
    },
    variant: TargetPlatformVariant.desktop(),
  );
}
