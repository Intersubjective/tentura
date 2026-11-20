import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/domain/entity/beacon_activity_event_consts.dart';
import 'package:tentura/domain/entity/beacon_fact_history_entry.dart';
import 'package:tentura/features/beacon_threads/ui/bloc/fact_history_cubit.dart';
import 'package:tentura/features/beacon_threads/ui/widget/fact_history_sheet.dart';

import '../../support/phone_surface.dart';
import 'fact_origin_test_support.dart';

const _fixturePath =
    'test/features/beacon_threads/fixtures/created_fact_with_pin_event.json';
const _beaconId = 'B000000000001';
const _factId = 'F000000000001';
const _operation = 'BeaconFactCardRevisions';
const _desktop = Size(1280, 800);

void main() {
  late Map<String, Object?> response;
  late List<Map<String, Object?>> rows;
  late String? cursor;

  Future<OriginWire> startWire() =>
      OriginWire.start(origin: const {}, revisionsResponse: response);

  void expectPage(BeaconFactHistoryPage page) {
    final [revision, pin] = rows;
    expect(page.nextCursor, cursor);
    expect(page.entries, [
      isA<BeaconFactHistoryCreated>()
          .having((entry) => entry.factCardId, 'fact', _factId)
          .having((entry) => entry.seq, 'sequence', revision['seq'])
          .having((entry) => entry.kind, 'kind', revision['kind'])
          .having((entry) => entry.factText, 'body', revision['factText']),
      isA<BeaconFactHistoryEvent>()
          .having((entry) => entry.type, 'event type', pin['kind'])
          .having((entry) => entry.visibilityFrom, 'visibility before', null)
          .having((entry) => entry.visibilityTo, 'visibility after', null),
    ]);
    for (var index = 0; index < rows.length; index++) {
      final wireRow = rows[index];
      final entry = page.entries[index];
      expect(entry.id, wireRow['entryKey']);
      expect(entry.actorId, wireRow['actorId']);
      expect(entry.actorTitle, wireRow['actorTitle']);
      expect(entry.createdAt, DateTime.parse(wireRow['createdAt']! as String));
    }
  }

  group('history with a creation revision and a pin event', () {
    setUpAll(() {
      // The deployed client requested this response for F58ee87ae051e on
      // Beec80fe70075. Desktop and phone captures matched. Only the actor
      // name and ID were replaced. The card has no copy origin.
      response =
          jsonDecode(File(_fixturePath).readAsStringSync())
              as Map<String, Object?>;
      final data = response['data']! as Map<String, Object?>;
      final page = data[_operation]! as Map<String, Object?>;
      rows = (page['entries']! as List<Object?>).cast<Map<String, Object?>>();
      cursor = page['nextCursor'] as String?;
      expect(rows, hasLength(2));
      expect(rows.last, containsPair('entry', 'event'));
      expect(
        rows.last,
        containsPair('kind', BeaconActivityEventTypeBits.factPinned),
      );
      for (final field in [
        'seq',
        'factText',
        'restoredFromSeq',
        'visibilityFrom',
        'visibilityTo',
      ]) {
        expect(rows.last, containsPair(field, isNull));
      }
    });

    for (final (surfaceName, size, minHeight, input) in [
      ('desktop', _desktop, 113.0, 'mouse wheel'),
      ('desktop', _desktop, 113.0, 'mouse drag'),
      ('phone', kPhoneSurface, 135.0, 'touch drag'),
    ]) {
      testWidgets(
        '$surfaceName history shows content below the pin actor after $input',
        (tester) async {
          if (input == 'mouse wheel') {
            // Exercise the repository directly before opening a fresh wire
            // for the UI, which must issue exactly one request of its own.
            await tester.runAsync(() async {
              final wire = await startWire();
              try {
                expectPage(
                  await wire.repository.revisions(
                    beaconId: _beaconId,
                    factCardId: _factId,
                  ),
                );
                expect(wire.sent, [_operation]);
              } finally {
                await wire.close();
              }
            });
          }

          tester.view.devicePixelRatio = 1;
          tester.view.physicalSize = size;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          final wire = (await tester.runAsync(startWire))!;
          addTearDown(() => tester.runAsync(wire.close));
          final [revision, pin] = rows;
          await pumpOpener(
            tester,
            locale: const Locale('ru'),
            size: size,
            open: (context) => unawaited(
              showFactHistorySheet(
                context,
                beaconId: _beaconId,
                factCardId: _factId,
                baseRevisionSeq: revision['seq']! as int,
                canMutate: true,
                repository: wire.repository,
              ),
            ),
          );
          await pumpRealAsync(tester);

          final sheet = find.byType(FactHistorySheet);
          Finder inSheet(Finder target) =>
              find.descendant(of: sheet, matching: target);
          final title = inSheet(find.text('История факта'));
          final state = tester.element(title).read<FactHistoryCubit>().state;
          expect(wire.sent, [_operation]);
          expect(state.loadError, isNull);
          expectPage((entries: state.entries, nextCursor: state.nextCursor));
          expect(tester.takeException(), isNull);
          expect(inSheet(find.byType(ErrorWidget)), findsNothing);

          final panel = _panelBounds(tester, sheet, desktop: size == _desktop);
          final scrollable = inSheet(find.byType(Scrollable));
          Rect viewport() => tester.getRect(scrollable).intersect(panel);
          final revisionActor = inSheet(
            find.textContaining("${revision['actorTitle']} · "),
          );
          final revisionBody = inSheet(
            find.text(revision['factText']! as String, findRichText: true),
          );
          final pinActor = pin['actorTitle']! as String;
          final actorLines = inSheet(
            find.textContaining(
              RegExp('^${RegExp.escape(pinActor)}(?: · .+)?\$'),
            ),
          );
          expect(actorLines, findsNWidgets(2));
          final pinActorLine = actorLines.last;
          expect(panel.height, greaterThan(minHeight));
          expect(panel.height, lessThanOrEqualTo(0.9 * size.height));
          for (final target in [
            title,
            revisionActor,
            revisionBody,
            pinActorLine,
          ]) {
            expect(target, findsOneWidget);
            expect(
              _contains(viewport(), tester.getRect(target)),
              isTrue,
              reason: '$target must fit in the history viewport.',
            );
          }

          // The pin is the final row and this fact has no origin footer.
          // Text lower than its actor line belongs to the pin's details.
          final rowText = find.descendant(
            of: scrollable,
            matching: find.byWidgetPredicate((widget) {
              if (widget is! RichText) return false;
              final text = widget.text.toPlainText().trim();
              return text.isNotEmpty && text != pinActor;
            }),
          );
          bool visibleBelowActor() {
            final actorBottom = tester.getBottomLeft(pinActorLine).dy;
            return rowText.evaluate().any((element) {
              final rect = tester.getRect(find.byWidget(element.widget));
              return rect.top >= actorBottom &&
                  rect.bottom > actorBottom &&
                  _contains(viewport(), rect);
            });
          }

          for (var attempt = 0; attempt < 5; attempt++) {
            final center = viewport().center;
            if (input == 'mouse wheel') {
              await tester.sendEventToBinding(
                PointerScrollEvent(
                  position: center,
                  scrollDelta: const Offset(0, 56),
                ),
              );
            } else {
              await tester.dragFrom(
                center,
                const Offset(0, -56),
                kind: size == _desktop
                    ? PointerDeviceKind.mouse
                    : PointerDeviceKind.touch,
              );
            }
            await tester.pumpAndSettle();
            if (visibleBelowActor()) break;
          }
          expect(tester.takeException(), isNull);
          expect(inSheet(find.byType(ErrorWidget)), findsNothing);
          expect(
            visibleBelowActor(),
            isTrue,
            reason:
                'The second row ends at its actor line. '
                'Content below that line must be fully visible after $input.',
          );
        },
      );
    }
  });
}

Rect _panelBounds(
  WidgetTester tester,
  Finder sheet, {
  required bool desktop,
}) {
  if (desktop) {
    expect(
      find.ancestor(of: sheet, matching: find.byType(Dialog)),
      findsOneWidget,
    );
    final material = tester
        .element(sheet)
        .findAncestorWidgetOfExactType<Material>()!;
    return tester.getRect(find.byWidget(material));
  }
  final bottomSheet = find.ancestor(
    of: sheet,
    matching: find.byType(BottomSheet),
  );
  expect(bottomSheet, findsOneWidget);
  return tester.getRect(bottomSheet);
}

bool _contains(Rect viewport, Rect rect) =>
    rect.left >= viewport.left &&
    rect.top >= viewport.top &&
    rect.right <= viewport.right &&
    rect.bottom <= viewport.bottom;
