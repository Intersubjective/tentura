import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/beacon_activity_event.dart';
import '../../support/beacon_activity_event_visibility_bits.dart';
import 'package:tentura/domain/entity/beacon_participant.dart';
import 'package:tentura/domain/entity/beacon_room_consts.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/beacon_view/ui/bloc/beacon_view_cubit.dart';
import 'package:tentura/features/beacon_view/ui/widget/activity_list.dart';
import 'package:tentura/features/beacon_view/ui/widget/beacon_activity_sheet.dart';
import 'package:tentura/ui/l10n/l10n.dart';

// #449: Request > Log is an oversized modal for two rows, has no Close
// button, and renders the creation row (request title, primary colour) unlike
// the status row.

const _kBeaconId = 'b-log-449';
const _kAuthorId = 'author-449';
const _kTitle = 'Help me move the piano';
final _kCreated = DateTime.utc(2026, 10, 13, 22, 35);
final _kStatus = DateTime.utc(2026, 10, 13, 22, 37);

class _LogCubit extends Mock implements BeaconViewCubit {
  _LogCubit(this._state);

  final BeaconViewState _state;
  final _controller = StreamController<BeaconViewState>.broadcast();

  @override
  BeaconViewState get state => _state;

  @override
  Stream<BeaconViewState> get stream => _controller.stream;

  @override
  Future<void> close() async {
    await _controller.close();
  }
}

BeaconActivityEvent _published() => BeaconActivityEvent(
  id: 'ev-published',
  beaconId: _kBeaconId,
  visibility: BeaconActivityEventVisibilityBits.public,
  type: BeaconActivityEventTypeBits.beaconPublished,
  createdAt: _kCreated,
  actorId: _kAuthorId,
  // Server writes the request title into the published event diff
  // (beacon_repository.dart `_insertBeaconPublishedEvent`).
  diffJson: jsonEncode({'title': _kTitle}),
);

BeaconActivityEvent _needsMoreHelp() => BeaconActivityEvent(
  id: 'ev-status',
  beaconId: _kBeaconId,
  visibility: BeaconActivityEventVisibilityBits.public,
  type: BeaconActivityEventTypeBits.beaconLifecycleChanged,
  createdAt: _kStatus,
  actorId: _kAuthorId,
  diffJson: jsonEncode({
    'reason': BeaconLifecycleChangeReason.needsMoreHelp,
  }),
);

BeaconActivityEvent _ask(int i) => BeaconActivityEvent(
  id: 'ev-ask-$i',
  beaconId: _kBeaconId,
  visibility: BeaconActivityEventVisibilityBits.room,
  type: 201,
  createdAt: _kStatus.add(Duration(minutes: i)),
  coordinationItemId: 'ask-$i',
);

BeaconViewState _state(List<BeaconActivityEvent> events) => BeaconViewState(
  beacon: Beacon(
    id: _kBeaconId,
    title: _kTitle,
    author: const Profile(id: _kAuthorId, displayName: 'Author'),
    createdAt: _kCreated,
    updatedAt: _kStatus,
  ),
  myProfile: const Profile(id: _kAuthorId, displayName: 'Author'),
  beaconContentLoaded: true,
  roomParticipantsLoaded: true,
  roomParticipants: [
    BeaconParticipant(
      id: 'p-author',
      beaconId: _kBeaconId,
      userId: _kAuthorId,
      role: 0,
      status: 0,
      roomAccess: RoomAccessBits.admitted,
      createdAt: _kCreated,
      updatedAt: _kCreated,
    ),
  ],
  roomActivityEvents: events,
);

Future<_LogCubit> _open(
  WidgetTester tester, {
  required Size size,
  required List<BeaconActivityEvent> events,
  List<BeaconActivityEvent>? tapped,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  final cubit = _LogCubit(_state(events));
  addTearDown(cubit.close);

  await tester.pumpWidget(
    MaterialApp(
      theme: TenturaTheme.light(),
      localizationsDelegates: L10n.localizationsDelegates,
      supportedLocales: L10n.supportedLocales,
      locale: const Locale('en'),
      home: TenturaResponsiveScope(
        child: Scaffold(
          body: Builder(
            builder: (ctx) => TextButton(
              onPressed: () => showBeaconActivitySheet(
                ctx,
                cubit: cubit,
                onTapCoordinationEvent: tapped?.add ?? (_) {},
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  return cubit;
}

/// Surface that hosts the Log: the outermost Material of the [Dialog]
/// (desktop) or [BottomSheet] (compact). Measured on the container's own
/// Material, not "nearest Material above the title", so an inner header
/// Material cannot make the height checks pass trivially. ([Dialog] itself
/// is not measured directly: its Align fills the whole screen.)
Finder _logSurface(L10n l10n) => find
    .descendant(
      of: find.byWidgetPredicate((w) => w is Dialog || w is BottomSheet),
      matching: find.byType(Material),
    )
    .first;

/// A Close affordance inside the Log: a widget labelled with the l10n Close
/// string (TextButton text, or IconButton tooltip).
Finder _closeControl(L10n l10n) => find.descendant(
  of: _logSurface(l10n),
  matching: find.byWidgetPredicate(
    (w) =>
        (w is Text && w.data == l10n.buttonClose) ||
        (w is Tooltip && w.message == l10n.buttonClose),
  ),
);

TextStyle? _rowStyle(WidgetTester tester, Finder text) {
  final rich = tester.widget<RichText>(
    find.descendant(of: text, matching: find.byType(RichText)).first,
  );
  return rich.text.style;
}

void main() {
  late L10n l10n;

  setUpAll(() async {
    l10n = await L10n.delegate.load(const Locale('en'));
  });

  group('#449 Log size', () {
    testWidgets('desktop: two-entry Log dialog is sized to its content', (
      tester,
    ) async {
      await _open(
        tester,
        size: const Size(1280, 800),
        events: [_published(), _needsMoreHelp()],
      );
      expect(find.byType(Dialog), findsOneWidget);
      final h = tester.getSize(_logSurface(l10n)).height;
      // Today the body forces maxHeight (0.9 * 800 = 720) via Expanded.
      expect(h, lessThan(400), reason: 'Log dialog height was $h');
    });

    testWidgets('compact: two-entry Log sheet is sized to its content', (
      tester,
    ) async {
      await _open(
        tester,
        size: const Size(400, 800),
        events: [_published(), _needsMoreHelp()],
      );
      expect(find.byType(Dialog), findsNothing);
      final h = tester.getSize(_logSurface(l10n)).height;
      expect(h, lessThan(400), reason: 'Log sheet height was $h');
    });

    testWidgets('(guard) desktop: long Log stays bounded and scrolls', (
      tester,
    ) async {
      await _open(
        tester,
        size: const Size(1280, 800),
        events: [for (var i = 0; i < 40; i++) _ask(i)],
      );
      expect(tester.takeException(), isNull);
      final h = tester.getSize(_logSurface(l10n)).height;
      expect(h, lessThanOrEqualTo(800 * 0.9 + 0.5));
      final scrollable = find.descendant(
        of: _logSurface(l10n),
        matching: find.byType(Scrollable),
      );
      expect(scrollable, findsWidgets);
      await tester.drag(scrollable.last, const Offset(0, -500));
      await tester.pump();
      expect(tester.takeException(), isNull);
      // Close-while-scrolled is pinned by its own test below.
    });

    testWidgets('desktop: Close stays visible while a long Log is scrolled', (
      tester,
    ) async {
      await _open(
        tester,
        size: const Size(1280, 800),
        events: [for (var i = 0; i < 40; i++) _ask(i)],
      );
      final scrollable = find.descendant(
        of: _logSurface(l10n),
        matching: find.byType(Scrollable),
      );
      await tester.drag(scrollable.last, const Offset(0, -500));
      await tester.pump();
      final close = _closeControl(l10n);
      expect(close, findsOneWidget);
      // Still on screen (not scrolled away with the rows).
      final surface = tester.getRect(_logSurface(l10n));
      final rect = tester.getRect(close);
      expect(surface.contains(rect.center), isTrue);
    });
  });

  group('#449 Log Close button', () {
    for (final size in const [Size(1280, 800), Size(400, 800)]) {
      testWidgets('Close dismisses the Log at ${size.width.toInt()}px', (
        tester,
      ) async {
        final tapped = <BeaconActivityEvent>[];
        await _open(
          tester,
          size: size,
          events: [_published(), _needsMoreHelp()],
          tapped: tapped,
        );
        expect(find.text(l10n.labelBeaconTabLog), findsOneWidget);
        final close = _closeControl(l10n);
        expect(close, findsOneWidget);

        await tester.tap(close);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));

        expect(find.text(l10n.labelBeaconTabLog), findsNothing);
        expect(tapped, isEmpty, reason: 'Close must not route to a row');
      });
    }
  });

  group('#449 Log rows styled alike', () {
    testWidgets('creation row is a plain event label, not the request title', (
      tester,
    ) async {
      await _open(
        tester,
        size: const Size(1280, 800),
        events: [_published(), _needsMoreHelp()],
      );
      final log = find.byType(BeaconActivityList);
      expect(
        find.descendant(of: log, matching: find.text(_kTitle)),
        findsNothing,
        reason: 'creation row must not render the request title as its body',
      );
      expect(
        find.descendant(
          of: log,
          matching: find.textContaining(l10n.beaconActivityBeaconPublished),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: log,
          matching: find.textContaining(l10n.coordinationMoreHelpNeeded),
        ),
        findsOneWidget,
      );
    });

    testWidgets('creation and status rows share colour and weight', (
      tester,
    ) async {
      await _open(
        tester,
        size: const Size(1280, 800),
        events: [_published(), _needsMoreHelp()],
      );
      final log = find.byType(BeaconActivityList);
      final created = find
          .descendant(
            of: log,
            matching: find.textContaining(l10n.beaconActivityBeaconPublished),
          )
          .first;
      final status = find
          .descendant(
            of: log,
            matching: find.textContaining(l10n.coordinationMoreHelpNeeded),
          )
          .first;
      final a = _rowStyle(tester, created);
      final b = _rowStyle(tester, status);
      expect(a?.color, b?.color);
      expect(a?.fontWeight, b?.fontWeight);

      // Negative guard: "alike" must not mean both look like links.
      final primary = Theme.of(tester.element(log)).colorScheme.primary;
      expect(a?.color, isNot(primary));
      expect(b?.color, isNot(primary));
    });
  });
}
