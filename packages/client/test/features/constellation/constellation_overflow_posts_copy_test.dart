import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tentura/ui/l10n/l10n.dart';

void main() {
  group('#248 Field overflow chip copy', () {
    test('EN names posts when the hidden cluster is posts-only', () {
      final l10n = lookupL10n(const Locale('en'));
      expect(l10n.constellationMorePostsByAuthor(2, 'Ann'), contains('post'));
      expect(l10n.constellationMorePosts(2), contains('post'));
      expect(l10n.constellationFewerPosts, contains('post'));
    });

    test('RU names posts when the hidden cluster is posts-only', () {
      final l10n = lookupL10n(const Locale('ru'));
      expect(l10n.constellationMorePostsByAuthor(2, 'Ann'), contains('пост'));
    });
  });
}
