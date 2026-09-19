import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// §0.3 — `AttentionCase` is the **only** owner of attention state. No second
/// attention cache may exist in any feature.
///
/// This is a directory-wide scan on purpose. U10a is the precedent: a guard
/// that lists the known offenders only encodes today, and the fourth spelling
/// of the same thing walks straight past it. What is checked here is the
/// *shape* of a second owner, wherever it is written:
///
/// * a feature-local map of receipts — a cache of attention rows;
/// * a feature deriving a Request's event counts itself, rather than reading
///   the ones the owner published;
/// * a feature stamping the clear axis on a receipt;
/// * a feature instantiating the owner's stores.
///
/// A screen may hold and render what the owner handed it. It may not produce
/// it, and it may not keep its own copy alongside.
void main() {
  const ownerDir = 'lib/domain/attention/';

  List<({String path, String source})> dartSources(String root) => [
    for (final entity in Directory(root).listSync(recursive: true))
      if (entity is File &&
          entity.path.endsWith('.dart') &&
          !entity.path.endsWith('.freezed.dart') &&
          !entity.path.endsWith('.g.dart') &&
          !entity.path.contains('/_g/'))
        (path: entity.path, source: entity.readAsStringSync()),
  ];

  void forbid({
    required String root,
    required String pattern,
    required String because,
    Iterable<String> allow = const [],
  }) {
    for (final file in dartSources(root)) {
      if (allow.any(file.path.contains)) continue;
      expect(
        file.source,
        isNot(contains(pattern)),
        reason: '${file.path}: $because',
      );
    }
  }

  test('no feature keeps its own cache of attention receipts', () {
    forbid(
      root: 'lib/features',
      pattern: 'Map<String, AttentionReceipt',
      because: 'a second attention cache (§0.3); read AttentionCase instead',
    );
  });

  test('only the attention owner derives a Request\'s event counts', () {
    // Constructing the projection is deriving it. Features receive it.
    for (final file in dartSources('lib')) {
      if (file.path.contains(ownerDir)) continue;
      expect(
        file.source,
        isNot(contains('ActivityOfferBeaconMeta(')),
        reason: '${file.path}: attention group counts derived outside '
            'AttentionCase (§0.3)',
      );
    }
  });

  test('no feature stamps the clear axis on a receipt', () {
    forbid(
      root: 'lib/features',
      pattern: 'clearedAt:',
      because: 'clearing is the owner\'s axis (D12–D14), not a screen\'s',
    );
  });

  test('the ack and clear stores have exactly one holder', () {
    for (final pattern in const [
      'AttentionAckStore()',
      'AttentionClearStore()',
    ]) {
      for (final file in dartSources('lib')) {
        if (file.path.contains(ownerDir)) continue;
        expect(
          file.source,
          isNot(contains(pattern)),
          reason: '${file.path}: a second holder of $pattern (§0.3)',
        );
      }
    }
  });

  test('the owner itself is a singleton hub, not one per screen', () {
    final source = File(
      '${ownerDir}attention_case.dart',
    ).readAsStringSync();
    expect(
      source,
      contains('@lazySingleton'),
      reason: 'AttentionCase must be injected as one instance per account',
    );
  });
}
