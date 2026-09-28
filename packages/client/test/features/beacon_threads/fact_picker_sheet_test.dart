// tentura-617.35: fact picker sheet + Room host wiring + 'Quote in chat'
// action — plan §7.2 B, §7.3 (all live facts from RoomState, search shown
// only when > 5, empty-state copy, single tap selects and closes) and the
// beacon_room_body.dart / fact_actions_sheet.dart wiring described in the
// bead body.
//
// `FactPickerSheet` / `showFactPickerSheet`
// (lib/features/beacon_threads/ui/widget/fact_picker_sheet.dart) do not
// exist yet, so this file does not compile — every test below fails until
// that widget is added AND beacon_room_body.dart wires `onPickFact` to open
// it AND `showFactActionsSheet` wires `onQuoteInChat` (plus composer
// refocus, mirroring the existing `focusComposer()` call after the edit
// sheet closes) to `RoomCubit.setPendingQuotedFact`.

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';

import 'package:tentura/data/repository/clipboard_image_repository.dart';
import 'package:tentura/data/repository/image_repository.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/beacon_fact_card.dart';
import 'package:tentura/domain/entity/beacon_fact_card_consts.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/domain/entity/quoted_fact.dart';
import 'package:tentura/domain/entity/room_message.dart';
import 'package:tentura/features/beacon_threads/ui/bloc/room_cubit.dart';
import 'package:tentura/features/beacon_threads/ui/widget/beacon_room_body.dart';
import 'package:tentura/features/beacon_threads/ui/widget/fact_picker_sheet.dart';
import 'package:tentura/features/beacon_threads/ui/widget/room_message_text_body.dart';
import 'package:tentura/features/profile/ui/bloc/profile_cubit.dart';
import 'package:tentura/ui/bloc/presence_cubit.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/widget/basic_chat_body.dart';

import 'support/room_body_harness.dart';

/// [RoomBodyHarnessCubit] leaves mutators unstubbed (Mockito no-ops), so this
/// gives [RoomCubit.setPendingQuotedFact] the same effect on state as the
/// real cubit (room_cubit.dart), letting tests assert on
/// `cubit.state.pendingQuotedFact` after a UI action rather than merely
/// verifying the call happened.
class _PickerRoomCubit extends RoomBodyHarnessCubit {
  _PickerRoomCubit(super.initial);

  @override
  void setPendingQuotedFact(BeaconFactCard card) {
    emitHarnessState(
      state.copyWith(
        pendingQuotedFact: QuotedFact(
          factCardId: card.id,
          seq: card.revisionSeq,
          currentSeq: card.revisionSeq,
          status: card.status,
          factText: card.factText,
          pinnedById: card.pinnedBy,
          pinnedByTitle: card.pinnedByTitle,
          visibility: card.visibility,
          attachments: card.attachments,
        ),
      ),
    );
  }

  /// Mirrors room_cubit.dart's real `clearPendingFactsFocus` so the
  /// pendingFactsFocusFactId deep-link listener in beacon_room_body.dart
  /// (a second, independent `showFactActionsSheet` call site from the
  /// message-long-press one) can run against this harness cubit exactly as
  /// it would against the real RoomCubit.
  @override
  void clearPendingFactsFocus() {
    if (state.pendingFactsFocusFactId != null) {
      emitHarnessState(state.copyWith(pendingFactsFocusFactId: null));
    }
  }

  @override
  void clearPendingQuotedFact() {
    if (state.pendingQuotedFact != null) {
      emitHarnessState(state.copyWith(pendingQuotedFact: null));
    }
  }
}

BeaconFactCard _fact({
  required String id,
  String factText = 'Some fact text',
  int visibility = BeaconFactCardVisibilityBits.public,
  String pinnedBy = 'peer-1',
  String pinnedByTitle = 'Peer',
  int status = BeaconFactCardStatusBits.active,
  int revisionSeq = 1,
}) => BeaconFactCard(
  id: id,
  beaconId: 'b-fact-picker',
  factText: factText,
  visibility: visibility,
  pinnedBy: pinnedBy,
  pinnedByTitle: pinnedByTitle,
  createdAt: DateTime.utc(2026),
  status: status,
  revisionSeq: revisionSeq,
);

/// Pumps just the picker sheet behind an "open" button — no composer
/// required for layout/search/empty-state assertions.
Future<void> _pumpPickerSheet(
  WidgetTester tester, {
  required RoomCubit cubit,
}) async {
  await tester.binding.setSurfaceSize(const Size(400, 900));
  addTearDown(() => tester.binding.setSurfaceSize(null));

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
              onPressed: () => showFactPickerSheet(ctx, cubit: cubit),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

/// Pumps the full [BeaconRoomBody] (composer included) under [cubit], with
/// the GetIt deps the composer needs, mirroring
/// support/room_body_harness.dart's `pumpBeaconRoomBody` but accepting a
/// pre-built cubit so tests can use [_PickerRoomCubit].
Future<void> _pumpRoomBodyWithCubit(
  WidgetTester tester, {
  required _PickerRoomCubit cubit,
  double width = 390,
  double height = 720,
}) async {
  final getIt = GetIt.I;
  await getIt.reset();

  final profileCubit = RoomBodyHarnessProfileCubit(
    const Profile(id: 'me', displayName: 'Me'),
  );
  final presenceCubit = RoomBodyHarnessPresenceCubit();

  getIt
    ..registerSingleton<ProfileCubit>(profileCubit)
    ..registerSingleton<ImageRepository>(ImageRepository())
    ..registerSingleton<ClipboardImageRepository>(ClipboardImageRepository());

  await tester.binding.setSurfaceSize(Size(width, height));
  addTearDown(() => tester.binding.setSurfaceSize(null));

  await tester.pumpWidget(
    MultiBlocProvider(
      providers: [
        BlocProvider<RoomCubit>.value(value: cubit),
        BlocProvider<ProfileCubit>.value(value: profileCubit),
        BlocProvider<PresenceCubit>.value(value: presenceCubit),
      ],
      child: MaterialApp(
        locale: const Locale('en'),
        theme: TenturaTheme.light(),
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        home: MediaQuery(
          data: MediaQueryData(size: Size(width, height)),
          child: const TenturaResponsiveScope(
            child: Scaffold(
              body: BeaconRoomBody(),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  group('FactPickerSheet layout (tentura-617.35)', () {
    testWidgets(
      'lists every live fact from RoomState, including both visibility '
      'variants',
      (tester) async {
        final facts = [
          _fact(id: 'f-public-1', factText: 'Public fact Alpha'),
          _fact(id: 'f-public-2', factText: 'Public fact Beta'),
          _fact(
            id: 'f-room-1',
            factText: 'Room-only fact Gamma',
            visibility: BeaconFactCardVisibilityBits.room,
          ),
          _fact(
            id: 'f-room-2',
            factText: 'Room-only fact Delta',
            visibility: BeaconFactCardVisibilityBits.room,
          ),
        ];
        final cubit = _PickerRoomCubit(
          roomBodyState().copyWith(factCards: facts),
        );

        await _pumpPickerSheet(tester, cubit: cubit);

        for (final fact in facts) {
          expect(
            find.textContaining(fact.factText),
            findsOneWidget,
            reason:
                'plan §7.2 B: the picker must list every live fact from '
                'RoomState — missing ${fact.id} (visibility=${fact.visibility})',
          );
        }
      },
    );

    testWidgets(
      'omits a non-live (removed) fact still present in RoomState.factCards',
      (tester) async {
        final live = _fact(id: 'f-live', factText: 'Live fact Alpha');
        final removed = _fact(
          id: 'f-removed',
          factText: 'Unpinned fact Omega',
          status: BeaconFactCardStatusBits.removed,
        );
        final cubit = _PickerRoomCubit(
          roomBodyState().copyWith(factCards: [live, removed]),
        );

        await _pumpPickerSheet(tester, cubit: cubit);

        expect(
          find.textContaining(live.factText),
          findsOneWidget,
          reason: 'the live fact must still be listed',
        );
        expect(
          find.textContaining(removed.factText),
          findsNothing,
          reason:
              'plan §7.2 B: "all live facts from RoomState" excludes '
              'unpinned/removed cards (BeaconFactCardStatusBits.removed), '
              'matching the existing activePinnedFacts() convention in '
              'beacon_view/domain/pinned_facts.dart — a removed fact must '
              'not be selectable as a quote source even though it is still '
              'present in factCards',
        );
      },
    );

    testWidgets('search field is absent for exactly 5 facts', (tester) async {
      final facts = List.generate(
        5,
        (i) => _fact(id: 'f$i', factText: 'Fact number $i'),
      );
      final cubit = _PickerRoomCubit(
        roomBodyState().copyWith(factCards: facts),
      );

      await _pumpPickerSheet(tester, cubit: cubit);

      expect(
        find.descendant(
          of: find.byType(FactPickerSheet),
          matching: find.byType(TextField),
        ),
        findsNothing,
        reason: 'plan §7.3: search is shown only once facts exceed 5',
      );
    });

    testWidgets('search field is present for 6 facts', (tester) async {
      final facts = List.generate(
        6,
        (i) => _fact(id: 'f$i', factText: 'Fact number $i'),
      );
      final cubit = _PickerRoomCubit(
        roomBodyState().copyWith(factCards: facts),
      );

      await _pumpPickerSheet(tester, cubit: cubit);

      expect(
        find.descendant(
          of: find.byType(FactPickerSheet),
          matching: find.byType(TextField),
        ),
        findsOneWidget,
        reason: 'plan §7.3: search must appear once facts exceed 5',
      );
    });

    testWidgets(
      'search field stays absent when factCards.length is 6 but only 5 '
      'are live',
      (tester) async {
        // The ">5" threshold in plan §7.3 must be keyed off the live/listed
        // facts, not the raw RoomState.factCards length — a removed card
        // still occupies a slot in factCards (server never deletes rows)
        // but must not count toward the search-visibility threshold, same
        // as it must not appear in the list itself.
        final facts = [
          ...List.generate(5, (i) => _fact(id: 'f$i', factText: 'Fact number $i')),
          _fact(
            id: 'f-removed',
            factText: 'Unpinned fact Omega',
            status: BeaconFactCardStatusBits.removed,
          ),
        ];
        final cubit = _PickerRoomCubit(
          roomBodyState().copyWith(factCards: facts),
        );

        await _pumpPickerSheet(tester, cubit: cubit);

        expect(
          find.descendant(
            of: find.byType(FactPickerSheet),
            matching: find.byType(TextField),
          ),
          findsNothing,
          reason:
              'plan §7.3: RoomState.factCards.length is 6 here, but only 5 '
              'are live (one is removed) — search must stay hidden, proving '
              'the threshold is keyed off the listable facts, not the raw '
              'factCards count',
        );
      },
    );

    testWidgets('search filters the displayed facts to text matches', (
      tester,
    ) async {
      final facts = [
        _fact(id: 'f-alpha', factText: 'Alpha fact about the gate code'),
        _fact(id: 'f-beta', factText: 'Beta fact about the parking spot'),
        _fact(id: 'f-gamma', factText: 'Gamma fact about the wifi password'),
        _fact(id: 'f-delta', factText: 'Delta fact about trash pickup'),
        _fact(id: 'f-epsilon', factText: 'Epsilon fact about quiet hours'),
        _fact(id: 'f-zeta', factText: 'Zeta fact about the mailbox key'),
      ];
      final cubit = _PickerRoomCubit(
        roomBodyState().copyWith(factCards: facts),
      );

      await _pumpPickerSheet(tester, cubit: cubit);

      final searchField = find.descendant(
        of: find.byType(FactPickerSheet),
        matching: find.byType(TextField),
      );
      expect(searchField, findsOneWidget);

      await tester.enterText(searchField, 'gate code');
      await tester.pumpAndSettle();

      expect(
        find.textContaining('Alpha fact about the gate code'),
        findsOneWidget,
        reason:
            'plan §7.3: the matching fact must remain listed while '
            'searching, not merely present a nonfunctional search box',
      );
      expect(
        find.textContaining('Beta fact about the parking spot'),
        findsNothing,
        reason:
            'plan §7.3: typing a query into search must filter out '
            'non-matching facts, not just render a TextField that does '
            'nothing',
      );
      expect(
        find.textContaining('Gamma fact about the wifi password'),
        findsNothing,
        reason: 'non-matching facts must be filtered out while searching',
      );
    });

    testWidgets("empty list shows the 'No pinned facts yet' copy", (
      tester,
    ) async {
      final cubit = _PickerRoomCubit(
        roomBodyState().copyWith(factCards: const []),
      );

      await _pumpPickerSheet(tester, cubit: cubit);

      // Asserts on the rendered copy itself (bead body quotes this exact
      // phrase), not on a specific l10n getter name: the implementation may
      // reuse the existing `l10n.beaconFactsSheetEmpty` ("No pinned facts
      // yet.", already used by the analogous beacon-view pinned-facts
      // sheet) or introduce a new Room-scoped key — either satisfies the
      // acceptance criterion, but neither getter exists yet, so pinning one
      // by name would fail to compile for the wrong reason.
      expect(
        find.textContaining('No pinned facts yet'),
        findsOneWidget,
        reason:
            'plan §7.3: an empty fact list must show the "No pinned facts '
            'yet" empty-state copy',
      );
    });
  });

  group('FactPickerSheet selection wiring (tentura-617.35)', () {
    testWidgets(
      'tapping a fact in the picker closes the sheet and sets '
      'RoomCubit.pendingQuotedFact to it',
      (tester) async {
        // factA and factB differ on every field pendingQuotedFact copies
        // (visibility, status, revisionSeq, pinnedBy), not just id/text, so
        // an implementation that quotes the wrong card — or maps the right
        // card's fields incorrectly — is caught below, not just an id match.
        final factA = _fact(
          id: 'fact-a',
          factText: 'Alpha fact text',
          visibility: BeaconFactCardVisibilityBits.room,
          status: BeaconFactCardStatusBits.corrected,
          revisionSeq: 3,
          pinnedBy: 'author-a',
          pinnedByTitle: 'Author A',
        );
        final factB = _fact(
          id: 'fact-b',
          factText: 'Beta fact text',
          visibility: BeaconFactCardVisibilityBits.public,
          status: BeaconFactCardStatusBits.active,
          revisionSeq: 1,
          pinnedBy: 'author-b',
          pinnedByTitle: 'Author B',
        );
        final cubit = _PickerRoomCubit(
          roomBodyState().copyWith(factCards: [factA, factB]),
        );

        await _pumpRoomBodyWithCubit(tester, cubit: cubit);

        final l10n = await L10n.delegate.load(const Locale('en'));

        await tester.tap(find.byKey(const ValueKey('attach')));
        await tester.pumpAndSettle();
        await tester.tap(find.text(l10n.beaconRoomAttachPickFact));
        await tester.pumpAndSettle();

        expect(
          find.byType(FactPickerSheet),
          findsOneWidget,
          reason:
              'beacon_room_body.dart must wire onPickFact to open '
              'fact_picker_sheet.dart; today onPickFact is never passed to '
              "BasicChatBody, so the attach menu never even offers 'Fact'",
        );

        await tester.tap(find.textContaining('Alpha fact text'));
        await tester.pumpAndSettle();

        expect(
          find.byType(FactPickerSheet),
          findsNothing,
          reason: 'plan §7.3: a single tap selects and closes the picker',
        );
        final pending = cubit.state.pendingQuotedFact;
        expect(
          pending?.factCardId,
          'fact-a',
          reason:
              'tapping a fact must call RoomCubit.setPendingQuotedFact '
              'with the tapped card',
        );
        expect(
          pending?.factText,
          factA.factText,
          reason: 'the pending quote must carry the tapped card\'s text, '
              'not the other listed card\'s',
        );
        expect(
          pending?.seq,
          factA.revisionSeq,
          reason: 'the pending quote must carry the tapped card\'s '
              'revisionSeq as seq (room_cubit.dart RoomCubit.'
              'setPendingQuotedFact\'s existing contract)',
        );
        expect(
          pending?.visibility,
          factA.visibility,
          reason: 'the pending quote must carry the tapped card\'s '
              'visibility, not factB\'s (they differ: room vs public)',
        );
        expect(
          pending?.status,
          factA.status,
          reason: 'the pending quote must carry the tapped card\'s status, '
              'not factB\'s (they differ: corrected vs active)',
        );
        expect(
          pending?.pinnedById,
          factA.pinnedBy,
          reason: 'the pending quote must carry the tapped card\'s pinner, '
              'not factB\'s (they differ: author-a vs author-b)',
        );

        expect(
          find.byKey(const ValueKey('quoted-fact-banner')),
          findsOneWidget,
          reason:
              'beacon_room_body must pass pendingQuotedFact into '
              'BasicChatBody so the composer shows the attached-fact banner',
        );
        expect(find.textContaining(factA.factText), findsWidgets);
        expect(find.textContaining(factA.pinnedByTitle), findsWidgets);

        await tester.tap(find.byKey(const ValueKey('quoted-fact-close')));
        await tester.pumpAndSettle();

        expect(
          cubit.state.pendingQuotedFact,
          isNull,
          reason:
              'closing the banner must call RoomCubit.clearPendingQuotedFact',
        );
        expect(
          find.byKey(const ValueKey('quoted-fact-banner')),
          findsNothing,
        );
      },
    );
  });

  group("Fact manage sheet 'Quote in chat' wiring (tentura-617.35)", () {
    testWidgets(
      "opened from the real Room UI entry point (long-press a message's "
      "linked fact → 'View pinned fact'), tapping 'Quote in chat' closes "
      'the sheet, sets the pending quote and focuses the composer',
      (tester) async {
        const messageId = 'm-quote-source';
        final fact = _fact(
          id: 'fact-quote',
          factText: 'Gate code is 4821',
        ).copyWith(sourceMessageId: messageId);
        final message = RoomMessage(
          id: messageId,
          beaconId: 'b1',
          authorId: 'other',
          author: const Profile(id: 'other', displayName: 'Alex'),
          body: 'Hello room',
          createdAt: DateTime.utc(2026, 6, 30, 12),
        );
        final cubit = _PickerRoomCubit(
          roomBodyState(messages: [message]).copyWith(factCards: [fact]),
        );

        await _pumpRoomBodyWithCubit(tester, cubit: cubit, height: 900);

        final l10n = await L10n.delegate.load(const Locale('en'));

        Finder composerFieldFinder() => find.descendant(
          of: find.byType(BeaconRoomComposer),
          matching: find.byType(TextField),
        );
        bool composerHasFocus() {
          final finder = composerFieldFinder();
          expect(finder, findsOneWidget);
          return tester.widget<TextField>(finder).focusNode?.hasFocus ??
              false;
        }

        expect(
          composerHasFocus(),
          isFalse,
          reason:
              'baseline: the composer must start unfocused so the later '
              'focus assertion actually proves the quote action requested '
              'it, rather than the composer having been focused all along',
        );

        // Real Room UI entry point: long-press the message body to open the
        // message-actions sheet (see beacon_room_message_actions_sheet_test.dart),
        // then tap "View pinned fact" — the same call site
        // (`_pinOrManageFactForMessage` → `showFactActionsSheet`) production
        // code already uses.
        await tester.longPressAt(
          tester.getTopLeft(find.byType(RoomMessageTextBody)) +
              const Offset(8, 8),
        );
        await tester.pumpAndSettle();

        expect(
          find.text(l10n.beaconRoomActionViewPinnedFact),
          findsOneWidget,
          reason:
              'a message linked to a fact card must offer "View pinned '
              'fact" in its actions sheet',
        );

        await tester.ensureVisible(
          find.text(l10n.beaconRoomActionViewPinnedFact),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text(l10n.beaconRoomActionViewPinnedFact));
        await tester.pumpAndSettle();

        expect(
          find.text(l10n.beaconRoomFactCardActionQuoteInChat),
          findsOneWidget,
          reason:
              'showFactActionsSheet must pass onQuoteInChat so the manage '
              "sheet's 'Quote in chat' item appears when opened from the "
              'real Room UI entry point; today it is never wired, so the '
              'item never renders',
        );
        // Baseline: the manage sheet is actually open right now (as a real
        // BottomSheet route, plan §14) — required so the post-tap
        // `findsNothing` checks below prove the sheet closed rather than
        // merely that it was never rendered as a BottomSheet in the first
        // place.
        expect(
          find.text(l10n.beaconRoomFactManageSheetTitle),
          findsOneWidget,
          reason: 'the manage sheet must be open before tapping its action',
        );
        expect(find.byType(BottomSheet), findsOneWidget);

        await tester.tap(find.text(l10n.beaconRoomFactCardActionQuoteInChat));
        await tester.pumpAndSettle();

        expect(
          find.text(l10n.beaconRoomFactCardActionQuoteInChat),
          findsNothing,
          reason:
              "'Quote in chat' must close the manage sheet (its own "
              'action item must be gone)',
        );
        expect(
          find.text(l10n.beaconRoomFactManageSheetTitle),
          findsNothing,
          reason:
              "'Quote in chat' must close the *entire* manage sheet, not "
              'just remove the tapped row — the sheet title must be gone '
              'too, not merely the tapped item',
        );
        expect(
          find.byType(BottomSheet),
          findsNothing,
          reason:
              "'Quote in chat' must dismiss the manage sheet's BottomSheet "
              'route entirely',
        );
        expect(
          cubit.state.pendingQuotedFact?.factCardId,
          'fact-quote',
          reason:
              "'Quote in chat' must call RoomCubit.setPendingQuotedFact",
        );
        expect(
          find.byKey(const ValueKey('quoted-fact-banner')),
          findsOneWidget,
          reason:
              "'Quote in chat' must show the composer attached-fact banner",
        );

        expect(
          composerHasFocus(),
          isTrue,
          reason:
              "'Quote in chat' must request composer focus (the composer "
              'started unfocused per the baseline check above), mirroring '
              'the existing focusComposer() call used after the edit-fact '
              'sheet closes (beacon_room_body.dart)',
        );
      },
    );

    testWidgets(
      'also wired at the pendingFactsFocusFactId deep-link entry point — a '
      'second, independent showFactActionsSheet call site from the '
      'message-long-press one above, proving onQuoteInChat is wired at the '
      'shared showFactActionsSheet layer rather than hand-added to a '
      'single call site',
      (tester) async {
        final fact = _fact(
          id: 'fact-deep-link',
          factText: 'Deep-link quoted fact',
        );
        final cubit = _PickerRoomCubit(
          roomBodyState().copyWith(factCards: [fact]),
        );

        await _pumpRoomBodyWithCubit(tester, cubit: cubit);

        final l10n = await L10n.delegate.load(const Locale('en'));

        Finder composerFieldFinder() => find.descendant(
          of: find.byType(BeaconRoomComposer),
          matching: find.byType(TextField),
        );
        bool composerHasFocus() {
          final finder = composerFieldFinder();
          expect(finder, findsOneWidget);
          return tester.widget<TextField>(finder).focusNode?.hasFocus ??
              false;
        }

        expect(
          composerHasFocus(),
          isFalse,
          reason: 'baseline: the composer must start unfocused',
        );

        // beacon_room_body.dart's `pendingFactsFocusFactId` BlocListener
        // opens showFactActionsSheet on its own once this state field is
        // set — an entry point independent of the message-long-press +
        // "View pinned fact" one exercised above.
        cubit.emitHarnessState(
          cubit.state.copyWith(pendingFactsFocusFactId: fact.id),
        );
        await tester.pumpAndSettle();

        expect(
          find.text(l10n.beaconRoomFactManageSheetTitle),
          findsOneWidget,
          reason:
              'the pendingFactsFocusFactId deep link must open the manage '
              'sheet for the targeted fact',
        );
        expect(
          find.text(l10n.beaconRoomFactCardActionQuoteInChat),
          findsOneWidget,
          reason:
              "'Quote in chat' must render from this call site too, not "
              'only from the message-long-press one — otherwise the '
              'wiring is call-site-specific rather than shared',
        );

        await tester.tap(find.text(l10n.beaconRoomFactCardActionQuoteInChat));
        await tester.pumpAndSettle();

        expect(
          find.text(l10n.beaconRoomFactManageSheetTitle),
          findsNothing,
          reason: "'Quote in chat' must close the manage sheet here too",
        );
        expect(
          cubit.state.pendingQuotedFact?.factCardId,
          'fact-deep-link',
          reason:
              "'Quote in chat' must call RoomCubit.setPendingQuotedFact "
              'from this call site too',
        );
        expect(
          composerHasFocus(),
          isTrue,
          reason:
              'composer focus must be requested from this call site too, '
              'not only from the message-long-press one',
        );
      },
    );
  });
}
