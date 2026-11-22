import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'Sentry source documents the worker error finding and reporting decision',
    () {
      final lineComments = RegExp(
        r'^[ \t]*//[^\n]*(?:\n[ \t]*//[^\n]*)*',
        multiLine: true,
      );
      final notes = Directory('lib/app/sentry')
          .listSync()
          .whereType<File>()
          .where((file) => file.path.endsWith('.dart'))
          .expand((file) => lineComments.allMatches(file.readAsStringSync()))
          .map((match) => match.group(0)!)
          .where((note) => note.contains('TENTURA-CLIENT-6G'))
          .where((note) => RegExp(r'#1309\b').hasMatch(note));

      expect(
        notes,
        isNotEmpty,
        reason: 'cite TENTURA-CLIENT-6G and #1309 together beside the change',
      );
      expect(
        notes,
        anyElement(
          allOf(
            matches(
              RegExp(
                r'\b(?:because|caus\w*|origin\w*|rethrow\w*|race|'
                r'shutdown|unconfirmed|unknown)\b',
                caseSensitive: false,
              ),
            ),
            matches(
              RegExp(
                r'\b(?:diagnos\w*|annotat\w*|enrich\w*|rewrit\w*|'
                r'nam\w* the worker)\b',
                caseSensitive: false,
              ),
            ),
          ),
        ),
        reason:
            'record the investigation finding and the diagnostic decision '
            'in the same note',
      );
    },
  );
}
