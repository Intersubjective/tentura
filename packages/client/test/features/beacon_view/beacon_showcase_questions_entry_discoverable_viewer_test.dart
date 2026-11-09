import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:tentura_root/domain/entity/beacon_access.dart';

import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/beacon_lobby/data/repository/beacon_lobby_repository.dart';
import 'package:tentura/features/beacon_lobby/domain/entity/beacon_lobby.dart';
import 'package:tentura/features/beacon_lobby/domain/use_case/beacon_lobby_case.dart';
import 'package:tentura/features/beacon_lobby/ui/bloc/beacon_lobby_entry_cubit.dart';
import 'package:tentura/features/beacon_lobby/ui/widget/beacon_lobby_entry_row.dart';
import 'package:tentura/features/beacon_view/ui/widget/beacon_showcase_surface.dart';
import 'package:tentura/ui/l10n/l10n.dart';

import '../../support/remote_wire_harness.dart';
import '../beacon_lobby/fake_lobby_port.dart';
import 'beacon_view_screen_harness.dart';

/// Someone who finds a Request through discoverability (nobody sent it to
/// them, no help offer, no seat) may ask the author in Questions when the
/// server's `BeaconLobbyAccess` says they can read. The client holds no policy
/// of its own: the server's answer travels through the real GraphQL mapping
/// (`BeaconLobbyRepository`) to the entry row's cubit, and the showcase shows
/// the Questions entry exactly when it says canRead, on a small phone in
/// Russian.
void main() {
  const viewer = 'discoverable-viewer';
  const description = 'Помогите с переездом в субботу.';
  const smallPhone = Size(375, 667);
  const ru = Locale('ru');

  tearDown(() async {
    await unregisterBeaconViewHarnessGetIt();
    if (GetIt.I.isRegistered<BeaconLobbyCase>()) {
      await GetIt.I.unregister<BeaconLobbyCase>();
    }
  });

  /// The server's probe answer for this viewer, mapped from a GraphQL
  /// response by the real repository over the real Ferry link chain.
  Future<BeaconLobbyAccess> accessFromWire({
    required bool canRead,
    required bool canPost,
  }) async {
    late BeaconLobbyAccess mapped;
    final sent = <WireSent>[];
    await withRemoteWire(
      {
        'BeaconLobbyAccess': {
          '__typename': 'query_root',
          'BeaconLobbyAccess': {
            '__typename': 'BeaconLobbyAccess',
            'beaconId': kBeaconViewHarnessBeaconId,
            'canRead': canRead,
            'canPost': canPost,
            'messageCount': 0,
            'unreadCount': 0,
            'readOnlyReason': null,
            'isHelper': false,
            'takesOffers': true,
          },
        },
      },
      sent,
      (remote) async {
        mapped = await BeaconLobbyRepository(
          remote,
        ).access(kBeaconViewHarnessBeaconId);
      },
    );
    expect(sent.single.variables['beaconId'], kBeaconViewHarnessBeaconId);
    return mapped;
  }

  Future<void> pumpShowcase(
    WidgetTester tester, {
    required BeaconLobbyAccess access,
  }) async {
    final port = FakeLobbyPort(
      viewerId: viewer,
      authorId: kBeaconViewHarnessAuthorId,
      // Nobody sent it, nobody offered.
      offerers: const {},
    )..accessAnswer = access;
    if (GetIt.I.isRegistered<BeaconLobbyCase>()) {
      await GetIt.I.unregister<BeaconLobbyCase>();
    }
    GetIt.I.registerSingleton<BeaconLobbyCase>(
      lobbyCaseFor(port, FakeRealtimeSyncPort()),
    );
    final author = beaconViewHarnessAuthorState();
    await pumpBeaconViewHarness(
      tester,
      size: smallPhone,
      locale: ru,
      beaconState: author.copyWith(
        beacon: author.beacon.copyWith(
          description: description,
          accessLevel: BeaconAccessLevel.observer,
          viewerCanForward: true,
        ),
        myProfile: const Profile(id: viewer, displayName: 'Тео'),
        roomParticipants: const [],
        helpOffers: const [],
      ),
      threadsState: beaconViewHarnessThreadsState(),
    );
    await tester.pumpAndSettle();
  }

  /// What the entry row's cubit holds: the probe answer it shows.
  BeaconLobbyAccess? entryState(WidgetTester tester) {
    final inside = find.descendant(
      of: find.byType(BeaconLobbyEntryRow),
      matching: find.byWidgetPredicate((_) => true),
    );
    return tester.element(inside.last).read<BeaconLobbyEntryCubit>().state;
  }

  group('Questions entry on the showcase for a discoverable viewer', () {
    testWidgets('shows under the description when the server says they '
        'can read', (tester) async {
      final l10n = lookupL10n(ru);
      final access = await accessFromWire(canRead: true, canPost: true);
      await pumpShowcase(tester, access: access);

      expect(find.byType(BeaconShowcaseSurface), findsOneWidget);
      final state = entryState(tester);
      expect(state?.canRead, isTrue);
      expect(state?.canPost, isTrue);
      final entry = find.byKey(BeaconLobbyEntryRow.entryKey);
      expect(entry, findsOneWidget);
      expect(l10n.beaconLobbyTitle, 'Вопросы');
      expect(
        find.descendant(of: entry, matching: find.text('Вопросы')),
        findsOneWidget,
      );
      final text = find.text(description);
      expect(text, findsOneWidget);
      expect(
        tester.getTopLeft(entry).dy,
        greaterThan(tester.getTopLeft(text).dy),
        reason: 'the entry sits under the description',
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('is absent when the server says they cannot read', (
      tester,
    ) async {
      final access = await accessFromWire(canRead: false, canPost: false);
      await pumpShowcase(tester, access: access);

      expect(find.byType(BeaconShowcaseSurface), findsOneWidget);
      expect(entryState(tester)?.canRead, isFalse);
      expect(find.byKey(BeaconLobbyEntryRow.entryKey), findsNothing);
      expect(find.text('Вопросы'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });
}
