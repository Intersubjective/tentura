import 'dart:io';

import 'package:test/test.dart';

/// A12 §7: every operation that writes a commitment event takes the
/// per-request lock before the write and calls
/// `ClosureCase.applyMembershipEvent` after it, in the same transaction.
///
/// Source-level contract: each public operation that (directly or through
/// same-file private helpers) writes the event is expanded, helper bodies
/// inlined at their call sites, and the order `lockRequest(` → event write →
/// `applyMembershipEvent(` is checked inside that one operation. A centralized
/// private helper that locks and applies is therefore accepted; an unrelated
/// lock or apply elsewhere in the file is not.
void main() {
  final methodStart = RegExp(
    r'^  [A-Za-z][\w<>?,.]* (_?[a-zA-Z]\w*)\((?=\{|\n|\w)',
    multiLine: true,
  );

  Map<String, String> methodsOf(String src) {
    final starts = methodStart.allMatches(src).toList();
    return {
      for (var i = 0; i < starts.length; i++)
        starts[i].group(1)!: src.substring(
          starts[i].start,
          i + 1 < starts.length ? starts[i + 1].start : src.length,
        ),
    };
  }

  String expand(String body, Map<String, String> methods, int depth) {
    if (depth == 0) return body;
    final out = StringBuffer();
    var last = 0;
    for (final m in RegExp(r'\b(_[a-zA-Z]\w*)\(').allMatches(body)) {
      final helper = methods[m.group(1)];
      if (helper == null) continue;
      out
        ..write(body.substring(last, m.end))
        ..write('\n/*inlined ${m.group(1)}*/\n')
        ..write(expand(helper, methods, depth - 1));
      last = m.end;
    }
    out.write(body.substring(last));
    return out.toString();
  }

  void expectOperationsWrapped(String file, String kind) {
    final src = File('lib/domain/use_case/$file').readAsStringSync();
    final methods = methodsOf(src);
    final write = 'kind: CommitmentEventKind.$kind';
    expect(src, contains(write), reason: '$file writes $kind');

    final operations = methods.entries.where(
      (e) =>
          !e.key.startsWith('_') && expand(e.value, methods, 4).contains(write),
    );
    expect(operations, isNotEmpty, reason: 'public operation writing $kind');
    for (final op in operations) {
      final body = expand(op.value, methods, 4);
      final lock = body.indexOf('lockRequest(');
      final at = body.indexOf(write);
      final apply = body.indexOf('applyMembershipEvent(', at);
      expect(
        lock,
        isNonNegative,
        reason: '${op.key} must call lockRequest before writing $kind',
      );
      expect(
        lock,
        lessThan(at),
        reason: '${op.key}: lock must precede the $kind write',
      );
      expect(
        apply,
        isNonNegative,
        reason: '${op.key} must call applyMembershipEvent after writing $kind',
      );
    }
  }

  group('membership hooks', () {
    test('HelpOfferCase withdrawal', () {
      expectOperationsWrapped('help_offer_case.dart', 'withdrawnByHelper');
    });

    for (final kind in [
      'acknowledged',
      'removedFromChat',
      'readmittedToChat',
      'releasedByAuthor',
    ]) {
      test('CoordinationCase $kind', () {
        expectOperationsWrapped('coordination_case.dart', kind);
      });
    }

    test('UserBlockCase blocked cleanup', () {
      expectOperationsWrapped('user_block_case.dart', 'blockedCleanup');
    });

    test('setBeaconStatus reviewOpen → needsMoreHelp delegates to '
        'ClosureCase.reopen', () {
      final src = File(
        'lib/domain/use_case/coordination_case.dart',
      ).readAsStringSync();
      final body = methodsOf(src)['setBeaconStatus']!;
      final cond = RegExp(
        r'target == BeaconStatus\.needsMoreHelp\s*&&\s*'
        r'beacon\.status == BeaconStatus\.reviewOpen\s*\)\s*\{',
      ).firstMatch(body);
      expect(cond, isNotNull, reason: 'reviewOpen → needsMoreHelp branch');
      var depth = 1;
      var i = cond!.end;
      while (depth > 0 && i < body.length) {
        if (body[i] == '{') depth++;
        if (body[i] == '}') depth--;
        i++;
      }
      final branch = body.substring(cond.end, i);
      expect(
        branch,
        matches(RegExp(r'[Cc]losure\w*\.reopen\(', dotAll: true)),
        reason: 'that branch must call ClosureCase.reopen',
      );
      expect(
        branch,
        contains('beaconId'),
        reason: 'reopen is invoked for this Request',
      );
    });
  });
}
