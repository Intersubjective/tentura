// B077b: dismissing the «Your help was accepted» sub-card on one device
// hides it on every device of the account. Two stores (two devices) share
// one fake server behind [OfferAcceptedDismissalPort].

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/design_system/tentura_theme.dart';
import 'package:tentura/domain/attention/offer_accepted_dismissals.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/widget/offer_accepted_event_subcard.dart';

const _viewer = 'Uhelper00001';

/// What the server keeps: dismissed Request ids per account.
final class _Server {
  final byViewer = <String, Set<String>>{};
}

final class _ServerPort implements OfferAcceptedDismissalPort {
  _ServerPort(this.server);

  final _Server server;
  bool failLoads = false;
  int loads = 0;

  @override
  Future<Set<String>> load({required String viewerId}) async {
    loads++;
    if (failLoads) throw StateError('offline');
    return {...?server.byViewer[viewerId]};
  }

  bool failDismisses = false;
  bool refuseDismisses = false;
  int dismissCalls = 0;

  /// When set, each dismissal waits for it (a slow network).
  Completer<void>? gate;

  @override
  Future<Set<String>> dismiss({
    required String viewerId,
    required String beaconId,
  }) async {
    dismissCalls++;
    await gate?.future;
    if (failDismisses) throw StateError('offline');
    if (refuseDismisses) throw const OfferAcceptedDismissalRefusedException();
    return {...(server.byViewer[viewerId] ??= {})..add(beaconId)};
  }
}

Widget _subcard(OfferAcceptedDismissals store) => MaterialApp(
  theme: TenturaTheme.light(),
  localizationsDelegates: L10n.localizationsDelegates,
  supportedLocales: L10n.supportedLocales,
  home: Scaffold(
    body: OfferAcceptedEventSubcard(
      beaconId: 'B1',
      viewerId: _viewer,
      author: const Profile(id: 'Uauthor', displayName: 'Tab QA'),
      acceptedAt: DateTime.utc(2026, 10, 14, 9),
      store: store,
    ),
  ),
);

void main() {
  test('a dismissal on one device is read by the other', () async {
    final server = _Server();
    final phone = OfferAcceptedDismissals(_ServerPort(server));
    final laptop = OfferAcceptedDismissals(_ServerPort(server));

    await phone.ensureLoadedFor(_viewer);
    await phone.dismiss(viewerId: _viewer, beaconId: 'B1');

    await laptop.ensureLoadedFor(_viewer);
    expect(laptop.isDismissed(viewerId: _viewer, beaconId: 'B1'), isTrue);
    expect(laptop.isDismissed(viewerId: _viewer, beaconId: 'B2'), isFalse);
  });

  test("nothing shows before the account's dismissals are known", () async {
    final server = _Server()..byViewer[_viewer] = {'B1'};
    final laptop = OfferAcceptedDismissals(_ServerPort(server));

    expect(laptop.shouldShow(viewerId: _viewer, beaconId: 'B2'), isFalse);
    await laptop.ensureLoadedFor(_viewer);
    expect(laptop.shouldShow(viewerId: _viewer, beaconId: 'B2'), isTrue);
    expect(laptop.shouldShow(viewerId: _viewer, beaconId: 'B1'), isFalse);
  });

  test('when the server cannot be read, the sub-card still shows', () async {
    final port = _ServerPort(_Server())..failLoads = true;
    final store = OfferAcceptedDismissals(port);

    await store.ensureLoadedFor(_viewer);
    expect(store.shouldShow(viewerId: _viewer, beaconId: 'B1'), isTrue);
  });

  testWidgets('a sub-card dismissed on another device never shows here', (
    tester,
  ) async {
    final server = _Server()..byViewer[_viewer] = {'B1'};
    final laptop = OfferAcceptedDismissals(_ServerPort(server));

    await tester.pumpWidget(_subcard(laptop));
    await tester.pumpAndSettle();

    expect(find.textContaining('Tab QA', findRichText: true), findsNothing);
  });

  testWidgets('a sub-card not dismissed anywhere shows once loaded', (
    tester,
  ) async {
    final laptop = OfferAcceptedDismissals(_ServerPort(_Server()));

    await tester.pumpWidget(_subcard(laptop));
    await tester.pumpAndSettle();

    expect(find.textContaining('Tab QA', findRichText: true), findsOneWidget);
  });

  test('a failed read is tried again on the next load', () async {
    final server = _Server()..byViewer[_viewer] = {'B1'};
    final port = _ServerPort(server)..failLoads = true;
    var now = DateTime.utc(2026, 10, 16, 12);
    final store = OfferAcceptedDismissals(port)..clock = () => now;

    await store.ensureLoadedFor(_viewer);
    // Safe default while offline: the card shows.
    expect(store.shouldShow(viewerId: _viewer, beaconId: 'B1'), isTrue);

    port.failLoads = false;
    await store.ensureLoadedFor(_viewer);
    // #537 review: no read straight away on every rebuild after a failure.
    expect(port.loads, 1);
    expect(store.shouldShow(viewerId: _viewer, beaconId: 'B1'), isTrue);

    now = now.add(OfferAcceptedDismissals.retryDelay);
    await store.ensureLoadedFor(_viewer);
    expect(port.loads, 2);
    expect(store.shouldShow(viewerId: _viewer, beaconId: 'B1'), isFalse);
  });

  // #537 review: every rebuild of every sub-card calls ensureLoadedFor; a
  // pending dismissal must still go out once, not once per call.
  test('a pending dismissal is sent by one flush at a time', () async {
    final port = _ServerPort(_Server());
    final phone = OfferAcceptedDismissals(port);
    await phone.ensureLoadedFor(_viewer);
    port.failDismisses = true;
    await phone.dismiss(viewerId: _viewer, beaconId: 'B1');
    expect(port.dismissCalls, 1);

    port
      ..failDismisses = false
      ..gate = Completer<void>();
    final calls = [for (var i = 0; i < 5; i++) phone.ensureLoadedFor(_viewer)];
    port.gate!.complete();
    await Future.wait(calls);

    expect(port.dismissCalls, 2);
    expect(port.server.byViewer[_viewer], {'B1'});
  });

  test('a × tapped while a flush runs is sent by that flush', () async {
    final port = _ServerPort(_Server());
    final phone = OfferAcceptedDismissals(port);
    await phone.ensureLoadedFor(_viewer);

    port.gate = Completer<void>();
    final first = phone.dismiss(viewerId: _viewer, beaconId: 'B1');
    final second = phone.dismiss(viewerId: _viewer, beaconId: 'B2');
    port.gate!.complete();
    await Future.wait([first, second]);

    expect(port.server.byViewer[_viewer], {'B1', 'B2'});
  });

  test('a dismissal the server refuses is not sent again', () async {
    final port = _ServerPort(_Server());
    final phone = OfferAcceptedDismissals(port);
    await phone.ensureLoadedFor(_viewer);

    port.refuseDismisses = true;
    await phone.dismiss(viewerId: _viewer, beaconId: 'B1');
    await phone.ensureLoadedFor(_viewer);
    await phone.ensureLoadedFor(_viewer);

    expect(port.dismissCalls, 1);
    // Hidden here all the same: the person dismissed it.
    expect(phone.isDismissed(viewerId: _viewer, beaconId: 'B1'), isTrue);
  });

  test('a dismissal the server missed is sent again later', () async {
    final server = _Server();
    final port = _ServerPort(server);
    final phone = OfferAcceptedDismissals(port);
    await phone.ensureLoadedFor(_viewer);

    port.failDismisses = true;
    await phone.dismiss(viewerId: _viewer, beaconId: 'B1');
    expect(phone.isDismissed(viewerId: _viewer, beaconId: 'B1'), isTrue);
    expect(server.byViewer[_viewer] ?? const <String>{}, isEmpty);

    port.failDismisses = false;
    await phone.dismiss(viewerId: _viewer, beaconId: 'B2');
    expect(server.byViewer[_viewer], {'B1', 'B2'});
  });

  test('a pending dismissal is also sent on the next load', () async {
    final server = _Server();
    final port = _ServerPort(server);
    final phone = OfferAcceptedDismissals(port);
    await phone.ensureLoadedFor(_viewer);

    port.failDismisses = true;
    await phone.dismiss(viewerId: _viewer, beaconId: 'B1');
    port.failDismisses = false;
    await phone.ensureLoadedFor(_viewer);
    expect(server.byViewer[_viewer], {'B1'});
  });
}
