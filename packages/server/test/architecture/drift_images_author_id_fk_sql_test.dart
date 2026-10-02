import 'dart:io';

import 'package:test/test.dart';

/// tentura-nyr: Drift-generated `CREATE TABLE` for `image` must not emit
/// `REFERENCES user (id)` — `user` is a reserved keyword in PostgreSQL.
void main() {
  final generated = File('lib/data/database/tentura_db.g.dart');
  assert(generated.existsSync(), 'run from packages/server');

  test(
    'Images.author_id FK constraint quotes the user table or targets users',
    () {
      final source = generated.readAsStringSync();
      final imagesTable = RegExp(
        r'class \$ImagesTable extends Images[\s\S]*?(?=\nclass \$)',
      ).firstMatch(source);
      expect(imagesTable, isNotNull, reason: 'missing \$ImagesTable block');
      final block = imagesTable!.group(0)!;
      final match =
          RegExp(
            r"'author_id'[\s\S]*?"
            r"defaultConstraints: GeneratedColumn\.constraintIsAlways\(\s*'([^']+)'",
          ).firstMatch(block) ??
          RegExp(
            r"'author_id'[\s\S]*?"
            r"\$customConstraints: '([^']+)'",
          ).firstMatch(block);
      expect(
        match,
        isNotNull,
        reason:
            'could not locate Images.author_id FK in \$ImagesTable '
            '(defaultConstraints or \$customConstraints)',
      );
      final constraint = match!.group(1)!;
      expect(
        constraint,
        isNot(contains('REFERENCES user (id)')),
        reason:
            'unquoted REFERENCES user breaks Postgres CREATE TABLE for image',
      );
      expect(
        constraint,
        anyOf(
          contains('REFERENCES "user"'),
          contains('REFERENCES users'),
        ),
        reason: 'FK must reference public."user" or users explicitly',
      );
    },
  );
}
