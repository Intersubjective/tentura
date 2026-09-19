import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/domain/attention/entity/attention_clear.dart';
import 'package:tentura/domain/attention/entity/attention_cursor.dart';
import 'package:tentura/domain/attention/entity/attention_feed.dart';
import 'package:tentura/domain/attention/entity/attention_receipt.dart';
import 'package:tentura/domain/attention/entity/attention_summary.dart';
import 'package:tentura/features/inbox/domain/entity/inbox_provenance.dart';

void main() {
  group('wire enums round-trip', () {
    test('every named value survives wireName -> fromWire', () {
      for (final value in AttentionClearReason.values) {
        expect(AttentionClearReason.fromWire(value.wireName), value);
      }
      for (final value in AttentionClearCaptureKind.values) {
        expect(AttentionClearCaptureKind.fromWire(value.wireName), value);
      }
      for (final value in AttentionOperationStatus.values) {
        expect(AttentionOperationStatus.fromWire(value.wireName), value);
      }
      for (final value in AttentionSweepMemberKind.values) {
        expect(AttentionSweepMemberKind.fromWire(value.wireName), value);
      }
      for (final value in AttentionSweepSkipReason.values) {
        expect(AttentionSweepSkipReason.fromWire(value.wireName), value);
      }
      for (final value in AttentionUndoSkipReason.values) {
        expect(AttentionUndoSkipReason.fromWire(value.wireName), value);
      }
      for (final value in AttentionUndoRefusal.values) {
        expect(AttentionUndoRefusal.fromWire(value.wireName), value);
      }
    });

    test('the wire names match the frozen server vocabulary', () {
      expect(
        AttentionClearReason.values.map((e) => e.wireName),
        containsAll(<String>[
          'explicit',
          'request_open',
          'sweep',
          'legacy_seen',
        ]),
      );
      expect(AttentionClearCaptureKind.requestOpen.wireName, 'request_open');
      expect(
        AttentionSweepSkipReason.values.map((e) => e.wireName),
        containsAll(<String>[
          'awaiting_decision',
          'responsibility_gained',
          'decision_changed',
          'already_cleared',
          'obligation',
          'not_authorized',
          'undone',
          'refused',
        ]),
      );
      expect(
        AttentionUndoSkipReason.values.map((e) => e.wireName),
        containsAll(<String>[
          'not_applied',
          'already_restored',
          'cleared_by_another_operation',
          'decision_changed',
          'obligation',
          'not_authorized',
          'refused',
        ]),
      );
      expect(
        AttentionUndoRefusal.values.map((e) => e.wireName),
        containsAll(<String>['expired', 'not_found', 'never_applied']),
      );
      expect(
        AttentionOperationStatus.values.map((e) => e.wireName),
        containsAll(<String>['complete', 'partial', 'stale', 'denied']),
      );
    });

    test('an unseen wire value falls back to unknown, never to success', () {
      expect(
        AttentionSweepSkipReason.fromWire('teleported_away'),
        AttentionSweepSkipReason.unknown,
      );
      expect(
        AttentionUndoSkipReason.fromWire('teleported_away'),
        AttentionUndoSkipReason.unknown,
      );
      expect(
        AttentionUndoRefusal.fromWire('teleported_away'),
        AttentionUndoRefusal.unknown,
      );
      expect(
        AttentionSweepMemberKind.fromWire('teleported_away'),
        AttentionSweepMemberKind.unknown,
      );
      expect(
        AttentionClearReason.fromWire('teleported_away'),
        AttentionClearReason.unknown,
      );

      // A status the client has never seen must not read as a finished
      // operation: `isComplete` is the only thing allowed to mean success.
      final status = AttentionOperationStatus.fromWire('teleported_away');
      expect(status, AttentionOperationStatus.unknown);
      expect(status!.isComplete, isFalse);
      expect(AttentionOperationStatus.complete.isComplete, isTrue);
    });

    test('null stays null', () {
      expect(AttentionClearReason.fromWire(null), isNull);
      expect(AttentionSweepSkipReason.fromWire(null), isNull);
      expect(AttentionUndoRefusal.fromWire(null), isNull);
    });
  });

  group('result shapes report unfinished work', () {
    test('a partial clear is not a success', () {
      const result = AttentionClearResult(
        operationId: 'op-1',
        appliedReceiptIds: ['a'],
        skippedReceiptIds: ['b'],
        status: AttentionOperationStatus.partial,
      );
      expect(result.isComplete, isFalse);
      expect(result.hasRefusals, isTrue);
    });

    test('a sweep with pending members asks to be resumed', () {
      const result = AttentionDismissAllResult(
        operationId: 'op-2',
        appliedReceiptIds: ['a'],
        appliedCount: 1,
        pendingCount: 3,
        status: AttentionOperationStatus.partial,
      );
      expect(result.isComplete, isFalse);
      expect(result.needsResume, isTrue);
      expect(result.canUndo, isFalse);
    });

    test('a sweep offers undo only when the server issued a token', () {
      final deadline = DateTime.utc(2026, 9, 19, 12);
      final result = AttentionDismissAllResult(
        operationId: 'op-3',
        appliedReceiptIds: const ['a'],
        appliedCount: 1,
        status: AttentionOperationStatus.complete,
        undoToken: 'tok',
        undoDeadline: deadline,
      );
      expect(result.canUndo, isTrue);
      expect(result.isComplete, isTrue);
      expect(result.needsResume, isFalse);
    });

    test('an expired undo is a refusal a person is told, not an error', () {
      const result = AttentionUndoResult(
        operationId: 'op-4',
        status: AttentionOperationStatus.denied,
        refusal: AttentionUndoRefusal.expired,
      );
      expect(result.isRefused, isTrue);
      expect(result.restoredCount, 0);
    });

    test(
      'reconcile does not claim success while something is unrepairable',
      () {
        const summary = AttentionSurfaceSummary(
          activityUnreadTotal: 0,
          myWorkUnreadTotal: 2,
          needsYouTotal: 2,
        );
        const repaired = AttentionReconcileResult(
          createdObligationCount: 1,
          settledObligationCount: 2,
          summary: summary,
        );
        const broken = AttentionReconcileResult(
          createdObligationCount: 1,
          settledObligationCount: 2,
          unrepairableObligationCount: 1,
          summary: summary,
        );
        expect(repaired.isFullyRepaired, isTrue);
        expect(broken.isFullyRepaired, isFalse);
      },
    );
  });

  group('receipt clear state and provenance', () {
    AttentionReceipt receipt({
      DateTime? clearedAt,
      AttentionClearReason? clearReason,
      String? provenanceJson,
    }) => AttentionReceipt(
      id: 'r1',
      category: 'c',
      kind: 'k',
      priority: 'p',
      title: 't',
      body: 'b',
      actionUrl: '',
      createdAt: DateTime.utc(2026),
      collapsedCount: 0,
      presentationPayloadJson: '{}',
      surface: AttentionSurface.activity,
      clearedAt: clearedAt,
      clearReason: clearReason,
      provenanceJson: provenanceJson,
    );

    test('clear state is a separate axis from seenAt', () {
      final cleared = receipt(
        clearedAt: DateTime.utc(2026, 9, 19),
        clearReason: AttentionClearReason.sweep,
      );
      expect(cleared.isCleared, isTrue);
      expect(cleared.isSeen, isFalse);
      expect(receipt().isCleared, isFalse);
    });

    test('provenanceJson is parsed by the existing InboxProvenance', () {
      final raw = jsonEncode({
        'senders': [
          {
            'id': 'u1',
            'displayName': 'Ann',
            'mr': 0.5,
            'notePreview': 'take a look',
            'reasonSlugs': ['knows_topic'],
          },
        ],
        'totalDistinctSenders': 3,
        'strongestNotePreview': 'take a look',
      });
      final parsed = InboxProvenance.parse(
        receipt(provenanceJson: raw).provenanceJson,
      );
      expect(parsed.totalDistinctSenders, 3);
      expect(parsed.senders.single.displayName, 'Ann');
      expect(parsed.strongestNotePreview, 'take a look');
    });
  });

  group('cursor contract', () {
    test('the client mints and accepts only version 2 cursors', () {
      expect(AttentionCursorContract.version, 2);
      final v2 = base64Url
          .encode(
            utf8.encode(
              jsonEncode({
                'createdAt': '2026-09-19T00:00:00.000Z',
                'id': 'r1',
                'v': 2,
              }),
            ),
          )
          .replaceAll('=', '');
      expect(AttentionCursorContract.versionOf(v2), 2);
      expect(AttentionCursorContract.isCurrent(v2), isTrue);
    });

    test('a v1 or unversioned cursor is stale, not resumable', () {
      final v1 = base64Url
          .encode(
            utf8.encode(
              jsonEncode({'createdAt': '2026-09-19T00:00:00.000Z', 'id': 'r1'}),
            ),
          )
          .replaceAll('=', '');
      expect(AttentionCursorContract.versionOf(v1), isNull);
      expect(AttentionCursorContract.isCurrent(v1), isFalse);
      expect(AttentionCursorContract.isCurrent('not-base64-at-all'), isFalse);
      expect(AttentionCursorContract.isCurrent(null), isTrue);
    });

    test('the server refusal for a dead cursor is recognisable', () {
      expect(
        AttentionCursorContract.isStaleCursorError(
          ArgumentError.value('abc', 'cursor', 'invalid attention cursor'),
        ),
        isTrue,
      );
      expect(
        AttentionCursorContract.isStaleCursorError(
          Exception('GraphQL error: invalid attention cursor'),
        ),
        isTrue,
      );
      expect(
        AttentionCursorContract.isStaleCursorError(Exception('network down')),
        isFalse,
      );
    });
  });
}
