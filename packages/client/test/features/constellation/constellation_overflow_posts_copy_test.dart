import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tentura/ui/l10n/l10n.dart';

void main() {
  group('#248 Field overflow chip copy', () {
    test('EN names posts when the hidden cluster is posts-only', () {
      final l10n = lookupL10n(const Locale('en'));
      expect(l10n.constellationMorePostsByAuthor(2, 'Ann'), contains('post'));
      expect(l10n.constellationMorePosts(2), '+2 more posts');
      expect(l10n.constellationFewerPosts, contains('post'));
    });

    test('EN constellationMorePosts plural', () {
      final l10n = lookupL10n(const Locale('en'));
      const expected = <int, String>{
        1: '+1 more post',
        2: '+2 more posts',
        3: '+3 more posts',
        4: '+4 more posts',
        5: '+5 more posts',
        11: '+11 more posts',
        21: '+21 more posts',
      };
      for (final entry in expected.entries) {
        expect(l10n.constellationMorePosts(entry.key), entry.value);
      }
    });

    test('RU names posts when the hidden cluster is posts-only', () {
      final l10n = lookupL10n(const Locale('ru'));
      expect(l10n.constellationMorePostsByAuthor(2, 'Ann'), contains('пост'));
    });

    test('RU constellationMorePosts plural', () {
      final l10n = lookupL10n(const Locale('ru'));
      const expected = <int, String>{
        1: 'ещё 1 пост',
        2: 'ещё 2 поста',
        3: 'ещё 3 поста',
        4: 'ещё 4 поста',
        5: 'ещё 5 постов',
        11: 'ещё 11 постов',
        21: 'ещё 21 пост',
      };
      for (final entry in expected.entries) {
        expect(l10n.constellationMorePosts(entry.key), entry.value);
      }
    });
  });
}
