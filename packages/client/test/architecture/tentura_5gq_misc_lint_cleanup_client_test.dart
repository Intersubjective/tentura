// tentura-5gq (client items 1–4): pre-existing analyzer hygiene at cited paths.

import 'package:test/test.dart';

import '../support/client_dart_analyze_harness.dart';

const _basicChatBodyRelative = 'lib/ui/widget/basic_chat_body.dart';

/// All client production paths touched by bead items 1–4.
const _client5gqProductionRelatives = <String>[
  _basicChatBodyRelative,
  'lib/features/beacon_threads/domain/use_case/beacon_threads_case.dart',
  'lib/features/beacon_threads/ui/widget/room_message_reply_quote.dart',
  'lib/ui/utils/duration_format.dart',
  'lib/ui/utils/ui_utils.dart',
  'lib/features/beacon_threads/ui/widget/room_message_tile.dart',
];

/// Pre-fix `dart analyze --format=json` on [_client5gqProductionRelatives].
const _client5gqScopedDartAnalyzeBaselineDiagnosticCount = 7;

/// Post-fix: only the two non-bead tentura_lints remain on basic_chat_body.
const _client5gqNonBeadTenturaLintCodesOnBasicChatBody = {
  'no_raw_edge_insets',
  'no_raw_border_radius',
};

const _client5gqScopedDartAnalyzePostFixDiagnosticCount = 2;

/// Pre-fix `flutter analyze lib/ui/widget/basic_chat_body.dart` (bead AC cites six).
const _client5gqItem1FlutterAnalyzeBaselineIssueCount = 6;

/// Bead item 1 acceptance sites (six); line 21 enforced via flutter analyze pins.
const _item1BeadSites = <({int lineOneBased, String code})>[
  (lineOneBased: 21, code: 'unnecessary_import'),
  (lineOneBased: 104, code: 'comment_references'),
  (lineOneBased: 246, code: 'comment_references'),
  (lineOneBased: 584, code: 'unnecessary_null_comparison'),
  (lineOneBased: 715, code: 'always_put_required_named_parameters_first'),
  (lineOneBased: 1097, code: 'comment_references'),
];

const _item1BeadDiagnosticCodes = {
  'unnecessary_import',
  'comment_references',
  'unnecessary_null_comparison',
  'always_put_required_named_parameters_first',
};

const _item2Relative =
    'lib/features/beacon_threads/domain/use_case/beacon_threads_case.dart';

const _item2BeadCodes = {
  'omit_local_variable_types',
  'avoid_redundant_argument_values',
};

const _item2BeadSites = <({int lineOneBased, String code})>[
  (lineOneBased: 214, code: 'omit_local_variable_types'),
  (lineOneBased: 244, code: 'avoid_redundant_argument_values'),
];

const _item3Relative =
    'lib/features/beacon_threads/ui/widget/room_message_reply_quote.dart';

const _item3BeadCodes = {'unnecessary_non_null_assertion'};

const _item3BeadSites = <({int lineOneBased, String code})>[
  (lineOneBased: 148, code: 'unnecessary_non_null_assertion'),
];

const _durationFormatRelative = 'lib/ui/utils/duration_format.dart';
const _uiUtilsRelative = 'lib/ui/utils/ui_utils.dart';
const _roomMessageTileRelative =
    'lib/features/beacon_threads/ui/widget/room_message_tile.dart';

const _item4BeadCodes = {
  'unused_local_variable',
  'unnecessary_import',
  'always_put_required_named_parameters_first',
  'comment_references',
};

const _item4BeadSites = <({int lineOneBased, String code})>[
  (lineOneBased: 44, code: 'unused_local_variable'),
  (lineOneBased: 8, code: 'unnecessary_import'),
  (lineOneBased: 2364, code: 'always_put_required_named_parameters_first'),
  (lineOneBased: 2431, code: 'comment_references'),
  (lineOneBased: 2537, code: 'always_put_required_named_parameters_first'),
];

List<({String relativePath, int lineOneBased, String code})> _dartBeadSites(
  String relativePath,
  List<({int lineOneBased, String code})> sites,
) {
  return sites
      .map(
        (s) => (
          relativePath: relativePath,
          lineOneBased: s.lineOneBased,
          code: s.code,
        ),
      )
      .toList(growable: false);
}

void main() {
  group('tentura-5gq client misc lint cleanup', () {
    test(
      'item 1 basic_chat_body removes six acceptance flutter sites and leaves tentura_lints on dart only',
      () {
        final outcome = runFlutterAnalyzeOnRelativePaths([_basicChatBodyRelative]);
        final summary = requireFlutterAnalyzeSummary(
          outcome: outcome,
          relativePath: _basicChatBodyRelative,
        );
        final allParsed = parseFlutterAnalyzeHits(
          combinedOutput: summary.combined,
          relativePath: _basicChatBodyRelative,
        );
        expect(
          allParsed.length,
          summary.issueCount,
          reason:
              'parsed flutter analyze diagnostics must match the issue summary '
              'line (guard against empty/unrecognized output)',
        );

        final flutterBeadHits = beadFlutterLintHitsOnSites(
          combinedOutput: summary.combined,
          relativePath: _basicChatBodyRelative,
          beadSites: _item1BeadSites,
        );
        expect(
          flutterBeadHits,
          isEmpty,
          reason:
              'tentura-5gq item 1: flutter analyze must not report any of the '
              'six bead acceptance sites on $_basicChatBodyRelative (including '
              'unnecessary_import at line 21 via flutter pins):\n'
              '${formatClientAnalyzeHits(flutterBeadHits)}',
        );

        expect(
          summary.issueCount,
          0,
          reason:
              'tentura-5gq item 1: flutter analyze on $_basicChatBodyRelative '
              'reports only the bead-listed findings today (not tentura_lints); '
              'post-fix issue count must be 0 once those '
              '$_client5gqItem1FlutterAnalyzeBaselineIssueCount acceptance '
              'findings are cleaned (currently ${summary.issueCount})',
        );
        expect(
          outcome.exitCode,
          0,
          reason:
              'flutter analyze on $_basicChatBodyRelative must exit 0 once '
              'bead-listed flutter findings are gone',
        );

        final dartBeadCodeHits = dartBeadCodeHitsOnRelativePath(
          relativePath: _basicChatBodyRelative,
          beadCodes: _item1BeadDiagnosticCodes,
        );
        expect(
          dartBeadCodeHits,
          isEmpty,
          reason:
              'tentura-5gq item 1: dart analyze must report no bead item-1 '
              'codes anywhere on $_basicChatBodyRelative:\n'
              '${formatClientAnalyzeHits(dartBeadCodeHits)}',
        );

        final basicChatCodes = dartDiagnosticCodesOnRelativePath(
          _basicChatBodyRelative,
        );
        expect(
          basicChatCodes.toSet(),
          _client5gqNonBeadTenturaLintCodesOnBasicChatBody,
          reason:
              'post-fix dart analyze on $_basicChatBodyRelative must retain '
              'only the two non-bead tentura_lints (not drop or replace them): '
              '$basicChatCodes',
        );
      },
      timeout: const Timeout(Duration(minutes: 6)),
    );

    test(
      'items 2–4 paths stay clean under flutter and dart bead code guards',
      () {
        final cases = <({
          String relativePath,
          Set<String> beadCodes,
          List<({int lineOneBased, String code})> flutterSites,
        })>[
          (
            relativePath: _item2Relative,
            beadCodes: _item2BeadCodes,
            flutterSites: _item2BeadSites,
          ),
          (
            relativePath: _item3Relative,
            beadCodes: _item3BeadCodes,
            flutterSites: _item3BeadSites,
          ),
          (
            relativePath: _durationFormatRelative,
            beadCodes: {'unused_local_variable'},
            flutterSites: [_item4BeadSites.first],
          ),
          (
            relativePath: _uiUtilsRelative,
            beadCodes: {'unnecessary_import'},
            flutterSites: [_item4BeadSites[1]],
          ),
          (
            relativePath: _roomMessageTileRelative,
            beadCodes: {
              'always_put_required_named_parameters_first',
              'comment_references',
            },
            flutterSites: _item4BeadSites.sublist(2),
          ),
        ];

        for (final entry in cases) {
          final outcome = runFlutterAnalyzeOnRelativePaths([entry.relativePath]);
          final summary = requireFlutterAnalyzeSummary(
            outcome: outcome,
            relativePath: entry.relativePath,
          );
          final allParsed = parseFlutterAnalyzeHits(
            combinedOutput: summary.combined,
            relativePath: entry.relativePath,
          );
          expect(
            allParsed.length,
            summary.issueCount,
            reason:
                'flutter analyze on ${entry.relativePath} must parse '
                'successfully',
          );
          final flutterHits = beadFlutterLintHitsOnSites(
            combinedOutput: summary.combined,
            relativePath: entry.relativePath,
            beadSites: entry.flutterSites,
          );
          expect(
            flutterHits,
            isEmpty,
            reason:
                'tentura-5gq items 2–4: flutter bead pins on '
                '${entry.relativePath} must be clean:\n'
                '${formatClientAnalyzeHits(flutterHits)}',
          );
          expect(
            summary.issueCount,
            0,
            reason:
                'tentura-5gq items 2–4: flutter analyze on '
                '${entry.relativePath} must report 0 issues post-fix',
          );

          final dartCodeHits = dartBeadCodeHitsOnRelativePath(
            relativePath: entry.relativePath,
            beadCodes: entry.beadCodes,
          );
          expect(
            dartCodeHits,
            isEmpty,
            reason:
                'tentura-5gq items 2–4: dart analyze must not report bead '
                'codes on ${entry.relativePath}:\n'
                '${formatClientAnalyzeHits(dartCodeHits)}',
          );

          final dartPinnedHits = beadLintHitsOnRelativePaths(
            relativePaths: [entry.relativePath],
            beadSites: _dartBeadSites(entry.relativePath, entry.flutterSites),
          );
          expect(
            dartPinnedHits,
            isEmpty,
            reason:
                'tentura-5gq items 2–4: dart pinned bead sites on '
                '${entry.relativePath} must be clean:\n'
                '${formatClientAnalyzeHits(dartPinnedHits)}',
          );
        }
      },
      timeout: const Timeout(Duration(minutes: 12)),
    );

    test(
      'client package and scoped production paths drop only bead diagnostics with no drift',
      () {
        final pinnedHits = beadLintHitsOnRelativePaths(
          relativePaths: _client5gqProductionRelatives,
          beadSites: [
            ..._dartBeadSites(_basicChatBodyRelative, _item1BeadSites),
            ..._dartBeadSites(_item2Relative, _item2BeadSites),
            ..._dartBeadSites(_item3Relative, _item3BeadSites),
            ..._dartBeadSites(_durationFormatRelative, [_item4BeadSites.first]),
            ..._dartBeadSites(_uiUtilsRelative, [_item4BeadSites[1]]),
            ..._dartBeadSites(_roomMessageTileRelative, _item4BeadSites.sublist(2)),
          ],
        );
        expect(
          pinnedHits,
          isEmpty,
          reason:
              'tentura-5gq client: dart pinned bead sites must all be absent:\n'
              '${formatClientAnalyzeHits(pinnedHits)}',
        );

        final scopedCount = countDartAnalyzeDiagnosticsOnRelativePaths(
          _client5gqProductionRelatives,
        );
        expect(
          scopedCount,
          _client5gqScopedDartAnalyzePostFixDiagnosticCount,
          reason:
              'tentura-5gq client: scoped production-path dart analyze must '
              'drop from baseline '
              '$_client5gqScopedDartAnalyzeBaselineDiagnosticCount to '
              '$_client5gqScopedDartAnalyzePostFixDiagnosticCount (only '
              'non-bead tentura_lints on basic_chat_body; actual $scopedCount)',
        );

        for (final relative in _client5gqProductionRelatives) {
          if (relative == _basicChatBodyRelative) {
            continue;
          }
          expect(
            countDartAnalyzeDiagnosticsOnRelativePaths([relative]),
            0,
            reason:
                'post-fix dart analyze on $relative must stay issue-free '
                '(items 2–4 bead scope)',
          );
        }
      },
      timeout: const Timeout(Duration(minutes: 12)),
    );
  });
}
