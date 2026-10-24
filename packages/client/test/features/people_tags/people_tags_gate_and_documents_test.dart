import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/consts.dart';

/// Reads files by relative path: run from `packages/client`.
const _operations = [
  'personTags',
  'personTagsOf',
  'personTagMemberships',
  'personAutoTags',
  'personAutoTagMembers',
  'personTagSuggestionState',
  'personTagCreate',
  'personTagUpdate',
  'personTagDelete',
  'personTagRestore',
  'personTagMembersApply',
  'personAutoTagPrefSet',
  'personTagSuggestionRecord',
];

String _documents() {
  final dir = Directory('lib/features/people_tags/data/gql');
  if (!dir.existsSync()) return '';
  return [
    for (final f in dir.listSync().whereType<File>().where(
      (f) => f.path.endsWith('.graphql'),
    ))
      f.readAsStringSync(),
  ].join('\n');
}

/// Fields each document must select so its result can be mapped to entities.
const _selections = <String, List<String>>{
  'personTags': [
    'id',
    'name',
    'glyph',
    'color',
    'ord',
    'count',
    'countOffField',
  ],
  'personTagsOf': ['own', 'auto', 'kind', 'n', 'direction'],
  'personTagMemberships': ['tagId', 'personIds'],
  'personAutoTags': ['kind', 'count', 'showInFilters'],
  'personAutoTagMembers': [],
  'personTagSuggestionState': ['canSuggest', 'disabled', 'silencedUntil'],
  'personTagCreate': ['id', 'name', 'glyph', 'color', 'ord', 'count'],
  'personTagUpdate': ['id', 'name', 'glyph', 'color', 'ord', 'count'],
  'personTagDelete': ['tag', 'memberIds', 'sources', 'id', 'name'],
  'personTagRestore': ['id', 'name', 'glyph', 'color', 'ord', 'count'],
  'personTagMembersApply': [],
  'personAutoTagPrefSet': ['kind', 'count', 'showInFilters'],
  'personTagSuggestionRecord': ['canSuggest', 'disabled', 'silencedUntil'],
};

/// The document text that calls [op], from its operation keyword on.
String _documentCalling(String documents, String op) {
  for (final doc in documents.split(
    RegExp(r'(?=^(query|mutation) )', multiLine: true),
  )) {
    if (RegExp('\\b$op\\b\\s*[({\\n]').hasMatch(doc) ||
        RegExp('\\b$op\\s*\$').hasMatch(doc)) {
      return doc;
    }
  }
  return '';
}

/// Index just past the bracket matching the one at [open].
int _closing(String text, int open) {
  final opener = text[open];
  final closer = opener == '(' ? ')' : '}';
  var depth = 0;
  for (var i = open; i < text.length; i++) {
    if (text[i] == opener) depth++;
    if (text[i] == closer && --depth == 0) return i + 1;
  }
  return text.length;
}

/// The result selection of the call to [op] (the `{ ... }` after its
/// arguments), or null when the call is a leaf (scalar result).
String? _resultSelection(String documents, String op) {
  final doc = _documentCalling(documents, op);
  final call = RegExp('\\b$op\\b').allMatches(doc).lastOrNull;
  if (call == null) return null;
  // Skip the variable declaration list of the operation header, if the match
  // landed in it: the call is the last occurrence of the field name.
  var i = call.end;
  while (i < doc.length && RegExp(r'\s').hasMatch(doc[i])) {
    i++;
  }
  if (i < doc.length && doc[i] == '(') {
    i = _closing(doc, i);
    while (i < doc.length && RegExp(r'\s').hasMatch(doc[i])) {
      i++;
    }
  }
  if (i >= doc.length || doc[i] != '{') return null;
  return doc.substring(i + 1, _closing(doc, i) - 1);
}

/// Argument list text of the call to [op], or empty.
String _callArguments(String documents, String op) {
  final doc = _documentCalling(documents, op);
  final call = RegExp('\\b$op\\b').allMatches(doc).lastOrNull;
  if (call == null) return '';
  var i = call.end;
  while (i < doc.length && RegExp(r'\s').hasMatch(doc[i])) {
    i++;
  }
  if (i >= doc.length || doc[i] != '(') return '';
  return doc.substring(i, _closing(doc, i));
}

void main() {
  test('people tags entry points are hidden by default', () {
    expect(kPeopleTagsEnabled, isFalse);
  });

  group('people tags GraphQL contract', () {
    final schema = File('lib/data/gql/schema.graphql').readAsStringSync();
    final documents = _documents();

    for (final op in _operations) {
      test('$op is declared in the client schema', () {
        expect(schema, matches(RegExp('\\b$op\\b')));
      });

      test('$op has a document whose result selection maps to its entity', () {
        expect(
          _documentCalling(documents, op),
          isNotEmpty,
          reason: 'no document calls $op',
        );
        final selection = _resultSelection(documents, op);
        final required = _selections[op]!;
        if (required.isEmpty) {
          expect(
            selection,
            isNull,
            reason: '$op returns a scalar and takes no sub-selection',
          );
          return;
        }
        expect(selection, isNotNull, reason: '$op has no result selection');
        for (final field in required) {
          expect(
            selection,
            matches(RegExp('\\b$field\\b')),
            reason: '$op result selection misses $field',
          );
        }
      });
    }

    test('personAutoTagMembers passes the tag kind and reads plain ids', () {
      expect(
        _callArguments(documents, 'personAutoTagMembers'),
        matches(RegExp(r'kind:\s*\$')),
      );
      expect(_resultSelection(documents, 'personAutoTagMembers'), isNull);
    });

    test('mutations send the idempotency key as an argument', () {
      for (final op in const [
        'personTagCreate',
        'personTagUpdate',
        'personTagDelete',
        'personTagRestore',
        'personTagMembersApply',
        'personTagSuggestionRecord',
      ]) {
        expect(
          _callArguments(documents, op),
          matches(RegExp(r'clientOpId:\s*\$')),
          reason: '$op must carry clientOpId',
        );
      }
    });
  });
}
