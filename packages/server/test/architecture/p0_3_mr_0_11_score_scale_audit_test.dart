import 'dart:io';

import 'package:test/test.dart';

/// P0.3 acceptance: `docs/plans/mr-0-11-score-scale-audit.md` exists and
/// inventories every absolute MR score threshold in `packages/server/lib`
/// (including migrations) with file:line and a rescale verdict.
void main() {
  final repoRoot = _repoRoot();
  final auditPath = '${repoRoot.path}/docs/plans/mr-0-11-score-scale-audit.md';

  String readAudit() {
    final file = File(auditPath);
    expect(
      file.existsSync(),
      isTrue,
      reason: 'P0.3 requires docs/plans/mr-0-11-score-scale-audit.md',
    );
    return file.readAsStringSync();
  }

  group('P0.3 audit note', () {
    test('exists and pins MeritRank v0.11.0', () {
      final audit = readAudit();
      expect(audit, contains('v0.11.0'));
      expect(audit, contains('Rescale verdict'));
    });

    test('documents the scale-direction conflict', () {
      final audit = readAudit();
      expect(audit, contains('Scale direction'));
      expect(
        audit,
        contains('~6× smaller'),
        reason: 'P0.3 wording: MR 0.11.0 scores are ~6× smaller',
      );
      expect(
        audit,
        contains('grew ~6×'),
        reason: 'plan §U0.3 wording: scores grew ~6×',
      );
    });

    test('treats mr_graph/mr_scores 0/100 args as pagination, not cutoffs',
        () {
      final audit = readAudit();
      expect(audit, contains('mr_graph'));
      expect(audit, contains('mr_scores'));
      expect(audit, contains('offset'));
      expect(audit, contains('limit'));
    });
  });

  group('P0.3 inventory completeness', () {
    test('every live MR score comparison appears in the audit', () {
      final audit = readAudit();
      final liveSites = _liveMrScoreComparisons(repoRoot);
      expect(
        liveSites,
        isNotEmpty,
        reason: 'scanner must find the known sign-only MR filters',
      );
      for (final site in liveSites) {
        expect(
          audit,
          contains(site),
          reason: 'audit must list live threshold $site',
        );
      }
    });

    test('every audit inventory entry is a live comparison site', () {
      final audit = readAudit();
      final liveSites = _liveMrScoreComparisons(repoRoot).toSet();
      final entries = RegExp(r'^### `([^`]+)`', multiLine: true)
          .allMatches(audit)
          .map((m) => m.group(1)!)
          .toList();
      expect(entries, isNotEmpty, reason: 'audit must list inventory entries');
      for (final entry in entries) {
        expect(
          liveSites.contains(entry),
          isTrue,
          reason: 'audit entry $entry is not a live MR score comparison',
        );
      }
      expect(
        entries.length,
        liveSites.length,
        reason: 'audit entry count must match the live comparison count',
      );
    });

    test('summary count matches the inventory', () {
      final audit = readAudit();
      final entries =
          RegExp(r'^### `[^`]+`', multiLine: true).allMatches(audit).length;
      expect(
        audit,
        contains('| $entries |'),
        reason: 'summary table must count the $entries inventory entries',
      );
    });
  });
}

/// Returns `path:line` (relative to `packages/server/lib`) for every
/// executable comparison of an MR score column to a numeric literal.
/// Comment lines (`//`, `///`) are documentation, not thresholds.
Set<String> _liveMrScoreComparisons(Directory repoRoot) {
  final libDir = Directory('${repoRoot.path}/packages/server/lib');
  final pattern = RegExp(
    r'(?:score_value_of_(?:src|dst)|forward_mr|reverse_mr)\s*>\s*0',
  );
  final sites = <String>{};
  for (final entity in libDir.listSync(recursive: true)) {
    if (entity is! File || !entity.path.endsWith('.dart')) {
      continue;
    }
    final relativePath = entity.path.substring(libDir.path.length + 1);
    final lines = entity.readAsLinesSync();
    for (var i = 0; i < lines.length; i++) {
      if (lines[i].trimLeft().startsWith('//')) {
        continue;
      }
      if (pattern.hasMatch(lines[i])) {
        sites.add('$relativePath:${i + 1}');
      }
    }
  }
  return sites;
}

Directory _repoRoot() {
  for (final start in [
    Directory.current,
    Directory('../../'),
    Directory('../../../'),
  ]) {
    final script = File('${start.path}/scripts/run_with_test_cleanup.sh');
    if (script.existsSync()) {
      return start.absolute;
    }
  }
  throw StateError('repo root not found');
}
