import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/domain/entity/room_message.dart';
import 'package:tentura/domain/entity/room_read_watermark.dart';
import 'package:tentura/domain/entity/beacon_room_consts.dart';
import 'package:tentura/features/beacon_threads/ui/widget/room_message_receipt_glyph.dart';
import 'package:tentura/features/beacon_threads/ui/widget/room_message_tile.dart';

import 'support/room_body_harness.dart';

// tentura-fpi landing gate acceptance (chat read receipts / room_seen_peer)

/// Alloy tentura-fpi landing gate — same paths as the bead acceptance command.
const kFpiAcceptanceTestPaths = [
  'test/architecture/beacon_room_read_receipts_release_test.dart',
  'test/architecture/realtime_entity_contract_impacts_test.dart',
  'test/features/beacon_threads/beacon_room_body_receipts_test.dart',
  'test/features/beacon_threads/beacon_threads_case_read_watermarks_test.dart',
  'test/features/beacon_threads/beacon_threads_repository_read_watermarks_test.dart',
  'test/features/beacon_threads/room_cubit_read_watermarks_test.dart',
  'test/features/beacon_threads/room_message_receipt_test.dart',
  'test/features/beacon_threads/room_message_receipt_glyph_test.dart',
  'test/features/beacon_threads/beacon_room_invalidation_test.dart',
  'test/data/service/invalidation_service_room_seen_peer_test.dart',
  'test/features/beacon_view/beacon_view_cubit_room_seen_peer_test.dart',
];

const _clientPackageRootSegments = ['packages', 'client'];

File _clientFile(String relativePath) {
  for (final prefix in const ['../../', '']) {
    final candidate = File('$prefix$relativePath');
    if (candidate.existsSync()) {
      return candidate.absolute;
    }
  }
  throw StateError('Client file not found: $relativePath');
}

File _repoContractFile() {
  for (final path in const [
    '../../docs/contracts/realtime-entity-contract.json',
    'docs/contracts/realtime-entity-contract.json',
  ]) {
    final file = File(path);
    if (file.existsSync()) {
      return file.absolute;
    }
  }
  throw StateError('Realtime entity contract manifest not found');
}

List<String> _contractTestPaths(Map<String, dynamic> contract) {
  return (contract['contractTests']! as List).cast<String>();
}

Finder receiptGlyphForMessageBody(String body) {
  final bodyText = find.text(body);
  final tile = bodyText.evaluate().isNotEmpty
      ? find.ancestor(
          of: bodyText,
          matching: find.byType(RoomMessageTile),
        )
      : find.byType(RoomMessageTile);
  return find.descendant(
    of: tile,
    matching: find.byType(RoomMessageReceiptGlyph),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const viewer = Profile(id: 'me', displayName: 'Me');
  const peer = Profile(id: 'peer', displayName: 'Peer');
  final messageCreatedAt = DateTime.utc(2026, 6, 30, 12);

  group('chat read receipts landing check (tentura-fpi)', () {
    test('fpi acceptance test files declare tentura-fpi landing gate marker', () {
      for (final path in kFpiAcceptanceTestPaths) {
        final file = _clientFile(path);
        expect(
          file.existsSync(),
          isTrue,
          reason: 'missing acceptance path $path',
        );
        final source = file.readAsStringSync();
        expect(
          source,
          contains('tentura-fpi'),
          reason:
              '$path must tag the fpi landing gate for Alloy trial-merge tracking',
        );
      }
    });

    test('realtime contractTests registers the fpi landing check harness', () {
      final contract =
          jsonDecode(_repoContractFile().readAsStringSync())
              as Map<String, dynamic>;
      final contractTests = _contractTestPaths(contract);
      expect(
        contractTests,
        contains(
          'packages/client/test/features/beacon_threads/chat_read_receipts_fpi_landing_check_test.dart',
        ),
        reason:
            'fpi landing gate must be part of the realtime contract evidence set',
      );
    });

    test('realtime contractTests registers every fpi acceptance path', () {
      final contract =
          jsonDecode(_repoContractFile().readAsStringSync())
              as Map<String, dynamic>;
      final contractTests = _contractTestPaths(contract);
      for (final relative in kFpiAcceptanceTestPaths) {
        final repoRelative = [..._clientPackageRootSegments, relative].join('/');
        expect(
          contractTests,
          contains(repoRelative),
          reason:
              'contractTests must list $repoRelative for the fpi landing gate',
        );
      }
    });

    test(
      'beacon_room_body_receipts_test uses roomBodyStateForSenderReceipts for multi-member receipts',
      () {
        final source = _clientFile(
          'test/features/beacon_threads/beacon_room_body_receipts_test.dart',
        ).readAsStringSync();
        expect(
          source,
          contains('roomBodyStateForSenderReceipts'),
          reason:
              'sender receipt widget tests must seed admitted discussion members via the shared harness helper',
        );
      },
    );

    test('roomBodyStateForSenderReceipts loads admitted viewer and peer', () {
      final state = roomBodyStateForSenderReceipts(
        myUserId: viewer.id,
        viewer: viewer,
        admittedPeer: peer,
        messages: [
          RoomMessage(
            id: 'own-1',
            beaconId: 'b1',
            authorId: viewer.id,
            author: viewer,
            body: 'Harness fixture',
            createdAt: messageCreatedAt,
          ),
        ],
        readWatermarks: {
          peer.id: RoomReadWatermark(
            userId: peer.id,
            lastSeenAt: messageCreatedAt,
          ),
        },
        readWatermarksLoaded: true,
      );

      expect(state.participantsLoaded, isTrue);
      expect(
        state.participants.any(
          (p) =>
              p.userId == peer.id &&
              p.roomAccess == RoomAccessBits.admitted,
        ),
        isTrue,
        reason: 'peer must be an admitted discussion member for sender receipts',
      );
      expect(
        state.participants.any(
          (p) =>
              p.userId == viewer.id &&
              p.roomAccess == RoomAccessBits.admitted,
        ),
        isTrue,
        reason: 'viewer participant row must be admitted when loaded',
      );
    });

    testWidgets(
      'manual admitted peer fixture shows read glyph for own message (production wiring)',
      (tester) async {
        final message = RoomMessage(
          id: 'own-manual-fixture',
          beaconId: 'b1',
          authorId: viewer.id,
          author: viewer,
          body: 'Own message with manual admitted peer fixture',
          createdAt: messageCreatedAt,
        );
        await pumpBeaconRoomBody(
          tester,
          viewer: viewer,
          enableComposer: false,
          roomState: roomBodyState(
            myUserId: viewer.id,
            messages: [message],
          ).copyWith(
            participants: [
              roomBodyAdmittedParticipant(
                beaconId: 'b1',
                profile: viewer,
                role: BeaconParticipantRoleBits.author,
              ),
              roomBodyAdmittedParticipant(beaconId: 'b1', profile: peer),
            ],
            participantsLoaded: true,
            readWatermarks: {
              peer.id: RoomReadWatermark(
                userId: peer.id,
                lastSeenAt: messageCreatedAt,
              ),
            },
            readWatermarksLoaded: true,
          ),
        );
        await tester.pumpAndSettle();

        final glyph = receiptGlyphForMessageBody(message.body);
        expect(glyph, findsOneWidget);
        expect(
          tester
              .widget<Icon>(
                find.descendant(
                  of: glyph,
                  matching: find.byType(Icon),
                ),
              )
              .icon,
          Icons.done_all,
        );
      },
    );

    testWidgets(
      'roomBodyStateForSenderReceipts shows read glyph for peer watermark',
      (tester) async {
        final message = RoomMessage(
          id: 'own-harness-fixture',
          beaconId: 'b1',
          authorId: viewer.id,
          author: viewer,
          body: 'Own message via sender receipt harness state',
          createdAt: messageCreatedAt,
        );
        await pumpBeaconRoomBody(
          tester,
          viewer: viewer,
          enableComposer: false,
          roomState: roomBodyStateForSenderReceipts(
            myUserId: viewer.id,
            viewer: viewer,
            admittedPeer: peer,
            messages: [message],
            readWatermarks: {
              peer.id: RoomReadWatermark(
                userId: peer.id,
                lastSeenAt: messageCreatedAt,
              ),
            },
            readWatermarksLoaded: true,
          ),
        );
        await tester.pumpAndSettle();

        expect(receiptGlyphForMessageBody(message.body), findsOneWidget);
      },
    );
  });
}
