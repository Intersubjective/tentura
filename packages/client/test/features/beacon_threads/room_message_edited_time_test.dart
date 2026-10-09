// An edited chat message keeps showing the time it was SENT; the edit time is
// only reachable through a tooltip on the «Edited» suffix. Both places where
// the tile renders the time line are covered:
//  - the inline trailing meta inside the text bubble (text, no reactions);
//  - the lifecycle footer row (a message that carries reactions).

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
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

const _viewer = Profile(id: 'me', displayName: 'Me');

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

// Local-time constructors: the tile formats `toLocal()`, so the expected
// strings do not depend on the machine's time zone.
final _sentAt = DateTime(2026, 10, 9, 21, 28);
final _editedAt = DateTime(2026, 10, 9, 21, 52);

RoomMessage _message({
  DateTime? editedAt,
  Map<String, int> reactionCounts = const {},
}) => RoomMessage(
  id: 'm1',
  beaconId: 'b1',
  authorId: _viewer.id,
  author: _viewer,
  body: 'See you at the dock',
  createdAt: _sentAt,
  editedAt: editedAt,
  reactionCounts: reactionCounts,
);

Future<void> _pumpTile(WidgetTester tester, RoomMessage message) async {
  await tester.binding.setSurfaceSize(const Size(900, 600));
  addTearDown(() => tester.binding.setSurfaceSize(null));
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
          body: Center(
            child: RoomMessageTile(
              message: message,
              myProfile: _viewer,
              onToggleReaction: (_, _) async {},
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Finder _text(String needle) =>
    find.textContaining(needle, findRichText: true);

Finder _tooltipWithEditTime() => find.byWidgetPredicate(
  (w) => w is Tooltip && (w.message ?? '').contains('21:52'),
);

/// Every semantics node under the tile, as «label | tooltip | value | hint».
List<String> _semanticsTexts(WidgetTester tester) {
  final out = <String>[];
  void visit(SemanticsNode node) {
    final d = node.getSemanticsData();
    out.add('${d.label} | ${d.tooltip} | ${d.value} | ${d.hint}');
    node.visitChildren((child) {
      visit(child);
      return true;
    });
  }

  visit(tester.getSemantics(find.byType(RoomMessageTile)));
  return out;
}

void main() {
  final edited = lookupL10n(const Locale('en')).beaconRoomMessageEdited;

  final paths = <String, Map<String, int>>{
    'inline trailing meta': const {},
    'reactions footer': const {'👍': 1},
  };

  for (final entry in paths.entries) {
    group('edited message time line (${entry.key})', () {
      testWidgets('shows the send time, not the edit time', (tester) async {
        await _pumpTile(
          tester,
          _message(editedAt: _editedAt, reactionCounts: entry.value),
        );

        expect(_text('21:28'), findsOneWidget);
        expect(_text('21:52'), findsNothing);
      });

      testWidgets('keeps the edited suffix next to the send time', (
        tester,
      ) async {
        await _pumpTile(
          tester,
          _message(editedAt: _editedAt, reactionCounts: entry.value),
        );

        expect(_text(edited), findsOneWidget);
        expect(_text('21:28'), findsOneWidget);
      });

      testWidgets('exposes the edit time in a tooltip on the suffix', (
        tester,
      ) async {
        await _pumpTile(
          tester,
          _message(editedAt: _editedAt, reactionCounts: entry.value),
        );

        expect(_tooltipWithEditTime(), findsOneWidget);
        expect(
          find.descendant(of: _tooltipWithEditTime(), matching: _text(edited)),
          findsOneWidget,
        );
      });

      testWidgets('announces the edit time with the suffix to assistive tech', (
        tester,
      ) async {
        final handle = tester.ensureSemantics();
        await _pumpTile(
          tester,
          _message(editedAt: _editedAt, reactionCounts: entry.value),
        );

        final nodes = _semanticsTexts(tester);
        // Must be released inside the body: Flutter verifies open semantics
        // handles before tearDown callbacks run.
        handle.dispose();
        // The send time is what the message announces...
        expect(nodes.where((n) => n.contains('21:28')), isNotEmpty);
        // ...and the node carrying the «Edited» suffix also carries the edit
        // time (as its tooltip/label), so screen readers can reach it.
        expect(
          nodes.where((n) => n.contains(edited) && n.contains('21:52')),
          isNotEmpty,
        );
      });

      testWidgets('unedited message shows send time without suffix or tooltip', (
        tester,
      ) async {
        await _pumpTile(tester, _message(reactionCounts: entry.value));

        expect(_text('21:28'), findsOneWidget);
        expect(_text(edited), findsNothing);
        expect(_tooltipWithEditTime(), findsNothing);
      });
    });
  }
}
