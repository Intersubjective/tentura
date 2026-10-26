import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:injectable/injectable.dart';

import 'package:tentura_server/domain/entity/constellation_tag_magnet.dart';
import 'package:tentura_server/domain/exception.dart';
import 'package:tentura_server/domain/exception_codes.dart';
import 'package:tentura_server/domain/port/constellation_tag_magnet_repository_port.dart';

import '../database/tentura_db.dart';

const _columns = 'tag_id, x_units, y_units, revision';

/// `constellation_tag_magnet` (m0267). Each write is one transaction under
/// the viewer's people-tags advisory lock, with its replay record in
/// `person_tag_op_log`, so magnets and tags never interleave per viewer.
@LazySingleton(as: ConstellationTagMagnetRepositoryPort)
class ConstellationTagMagnetRepository
    implements ConstellationTagMagnetRepositoryPort {
  const ConstellationTagMagnetRepository(this._database);

  final TenturaDb _database;

  @override
  Future<List<ConstellationTagMagnet>> list(String viewerId) async {
    final rows = await _database
        .customSelect(
          'SELECT $_columns FROM public.constellation_tag_magnet '
          r'WHERE viewer_id = $1 ORDER BY tag_id',
          variables: [Variable.withString(viewerId)],
        )
        .get();
    return rows.map(_fromRow).toList(growable: false);
  }

  @override
  Future<ConstellationTagMagnet> upsert({
    required String viewerId,
    required String tagId,
    required double xUnits,
    required double yUnits,
    required String clientOpId,
  }) => _idempotent<ConstellationTagMagnet>(
    viewerId,
    clientOpId,
    _fingerprint('upsert', [tagId, xUnits, yUnits]),
    decode: ConstellationTagMagnet.fromJson,
    run: () async {
      await _requireOwnTag(viewerId, tagId);
      final row = await _database
          .customSelect(
            '''
INSERT INTO public.constellation_tag_magnet
  (viewer_id, tag_id, x_units, y_units)
VALUES (\$1, \$2, \$3, \$4)
ON CONFLICT (viewer_id, tag_id) DO UPDATE
  SET x_units = EXCLUDED.x_units,
      y_units = EXCLUDED.y_units,
      revision = constellation_tag_magnet.revision + 1
RETURNING $_columns
''',
            variables: [
              Variable.withString(viewerId),
              Variable.withString(tagId),
              Variable.withReal(xUnits),
              Variable.withReal(yUnits),
            ],
          )
          .getSingle();
      return _fromRow(row);
    },
    encode: (m) => m.toJson(),
  );

  @override
  Future<void> remove({
    required String viewerId,
    required String tagId,
    required String clientOpId,
  }) => _idempotent<bool>(
    viewerId,
    clientOpId,
    _fingerprint('remove', [tagId]),
    decode: (_) => true,
    run: () async {
      await _requireOwnTag(viewerId, tagId);
      await _database.customStatement(
        r'''
DELETE FROM public.constellation_tag_magnet
 WHERE viewer_id = $1 AND tag_id = $2
''',
        [viewerId, tagId],
      );
      return true;
    },
    encode: (_) => const {},
  );

  Future<void> _requireOwnTag(String viewerId, String tagId) async {
    final own = await _database
        .customSelect(
          'SELECT 1 FROM public.person_tag '
          r'WHERE id = $1 AND owner_id = $2',
          variables: [
            Variable.withString(tagId),
            Variable.withString(viewerId),
          ],
        )
        .get();
    if (own.isEmpty) {
      throw PeopleTagsException(
        peopleTagsCode: PeopleTagsExceptionCode.tagNotFound,
      );
    }
  }

  Future<T> _idempotent<T>(
    String viewerId,
    String clientOpId,
    String fingerprint, {
    required T Function(Map<String, dynamic>) decode,
    required Future<T> Function() run,
    required Map<String, dynamic> Function(T) encode,
  }) => _database.withMutatingUser(viewerId, () async {
    await _database.customStatement(
      r"SELECT pg_advisory_xact_lock(hashtextextended('person_tags:' || $1, 4242))",
      [viewerId],
    );
    final logged = await _database
        .customSelect(
          'SELECT fingerprint, result::text AS result '
          'FROM public.person_tag_op_log '
          r'WHERE owner_id = $1 AND client_op_id = $2',
          variables: [
            Variable.withString(viewerId),
            Variable.withString(clientOpId),
          ],
        )
        .get();
    if (logged.isNotEmpty) {
      if (logged.single.read<String>('fingerprint') != fingerprint) {
        throw PeopleTagsException(
          peopleTagsCode: PeopleTagsExceptionCode.opIdReused,
        );
      }
      return decode(
        jsonDecode(logged.single.read<String>('result'))
            as Map<String, dynamic>,
      );
    }
    final result = await run();
    await _database.customStatement(
      r'''
INSERT INTO public.person_tag_op_log
  (owner_id, client_op_id, fingerprint, result)
VALUES ($1, $2, $3, $4::jsonb)
''',
      [viewerId, clientOpId, fingerprint, jsonEncode(encode(result))],
    );
    return result;
  });

  static String _fingerprint(String op, List<Object?> payload) => sha256
      .convert(utf8.encode(jsonEncode(['magnet', op, ...payload])))
      .toString();

  static ConstellationTagMagnet _fromRow(QueryRow r) => ConstellationTagMagnet(
    tagId: r.read<String>('tag_id'),
    xUnits: r.read<double>('x_units'),
    yUnits: r.read<double>('y_units'),
    revision: r.read<int>('revision'),
  );
}
