// U093: the request screen's team face pile (author + admitted helpers)
// shows who is online right now, with the same green dot as the chat
// avatars and the recipient picker.

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:tentura_root/domain/enums.dart';

import 'package:tentura/design_system/components/tentura_avatar.dart';
import 'package:tentura/design_system/components/tentura_presence_dot.dart';
import 'package:tentura/design_system/tentura_theme.dart';
import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/ui/bloc/presence_cubit.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/widget/beacon_involved_people_face_pile.dart';

const _author = Profile(id: 'u-author', displayName: 'Tab QA');
const _nina = Profile(id: 'u-nina', displayName: 'Nina Mover');
const _omar = Profile(id: 'u-omar', displayName: 'Omar Dinner');

class _PresenceCubit extends Mock implements PresenceCubit {
  _PresenceCubit(this._state);

  final Map<String, UserPresenceStatus> _state;

  @override
  Map<String, UserPresenceStatus> get state => _state;

  @override
  Stream<Map<String, UserPresenceStatus>> get stream =>
      Stream<Map<String, UserPresenceStatus>>.value(_state);
}

Widget _pile({PresenceCubit? presence, bool showPresence = true}) {
  final pile = BeaconInvolvedPeopleFacePile(
    beacon: Beacon.empty.copyWith(id: 'B1', author: _author),
    involvedProfiles: const [_nina, _omar],
    currentUserId: 'viewer',
    showPresence: showPresence,
  );
  return MaterialApp(
    theme: TenturaTheme.light(),
    localizationsDelegates: L10n.localizationsDelegates,
    supportedLocales: L10n.supportedLocales,
    home: Scaffold(
      body: Center(
        child: presence == null
            ? pile
            : BlocProvider<PresenceCubit>.value(value: presence, child: pile),
      ),
    ),
  );
}

void main() {
  testWidgets('online team members carry the presence dot', (tester) async {
    await tester.pumpWidget(
      _pile(
        presence: _PresenceCubit(const {
          'u-nina': UserPresenceStatus.online,
          'u-omar': UserPresenceStatus.offline,
        }),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(TenturaPresenceDot), findsOneWidget);
    // The dot sits on Nina's face, at its bottom-right.
    final nina = tester.getRect(
      find.byWidgetPredicate(
        (w) => w is TenturaAvatar && w.profile.id == 'u-nina',
      ),
    );
    final dot = tester.getCenter(find.byType(TenturaPresenceDot));
    expect(nina.contains(dot), isTrue);
    expect(dot.dx, greaterThan(nina.center.dx));
    expect(dot.dy, greaterThan(nina.center.dy));
  });

  testWidgets('the dot is painted above every face ring (#533)', (
    tester,
  ) async {
    await tester.pumpWidget(
      _pile(
        presence: _PresenceCubit(const {'u-nina': UserPresenceStatus.online}),
      ),
    );
    await tester.pumpAndSettle();

    final dot = find.byType(TenturaPresenceDot);
    expect(dot, findsOneWidget);
    // Not inside a face: its own ring and the next face would paint over it.
    expect(
      find.ancestor(of: dot, matching: find.byType(TenturaAvatarStackRing)),
      findsNothing,
    );
    expect(
      find.ancestor(of: dot, matching: find.byType(TenturaAvatar)),
      findsNothing,
    );

    // In the pile Stack, the dot comes after (is painted over) every face.
    final stack = tester.widget<Stack>(
      find.ancestor(of: dot, matching: find.byType(Stack)).first,
    );
    final dotLayer = find.ancestor(of: dot, matching: find.byType(Positioned));
    final dotIndex = stack.children.indexOf(tester.widget(dotLayer.first));
    final faceIndexes = [
      for (final face in find.byType(TenturaAvatarStackRing).evaluate())
        stack.children.indexOf(
          tester.widget(
            find
                .ancestor(
                  of: find.byWidget(face.widget),
                  matching: find.byType(Positioned),
                )
                .first,
          ),
        ),
    ];
    expect(faceIndexes, isNotEmpty);
    expect(faceIndexes.every((i) => i >= 0 && i < dotIndex), isTrue);
  });

  testWidgets('nobody online: no dots', (tester) async {
    await tester.pumpWidget(_pile(presence: _PresenceCubit(const {})));
    await tester.pumpAndSettle();

    expect(find.byType(TenturaPresenceDot), findsNothing);
  });

  testWidgets('without presence data (no provider) it still renders', (
    tester,
  ) async {
    await tester.pumpWidget(_pile());
    await tester.pumpAndSettle();

    expect(find.byType(TenturaAvatar), findsNWidgets(3));
    expect(find.byType(TenturaPresenceDot), findsNothing);
  });

  testWidgets('other piles (My Work cards, threads) show no dots by default', (
    tester,
  ) async {
    // Only the request header watches the team's presence; elsewhere a dot
    // would appear for whoever another screen happens to watch.
    await tester.pumpWidget(
      _pile(
        presence: _PresenceCubit(const {'u-nina': UserPresenceStatus.online}),
        showPresence: false,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(TenturaPresenceDot), findsNothing);
  });

  testWidgets('screen readers hear how many are online, not just a colour', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(
      _pile(
        presence: _PresenceCubit(const {
          'u-author': UserPresenceStatus.online,
          'u-nina': UserPresenceStatus.online,
          'u-omar': UserPresenceStatus.offline,
        }),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.bySemanticsLabel(RegExp(r', 2 online$')), findsOneWidget);

    await tester.pumpWidget(_pile(presence: _PresenceCubit(const {})));
    await tester.pumpAndSettle();
    expect(find.bySemanticsLabel(RegExp('online')), findsNothing);
    semantics.dispose();
  });
}
