import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:injectable/injectable.dart';
import 'package:tentura_root/domain/entity/person_auto_tag_kind.dart';

import 'package:tentura_server/domain/entity/person_tag.dart';
import 'package:tentura_server/domain/exception.dart';
import 'package:tentura_server/domain/exception_codes.dart';
import 'package:tentura_server/domain/port/people_tags_repository_port.dart';

import '_use_case_base.dart';

const kPersonTagMaxNameLength = 32;
const kPersonTagMaxGlyphUnits = 8;
const kPersonTagColors = 8;
const kPersonTagMaxOpsPerCall = 400;
const kPersonTagMaxSource = 4;

/// An owner's own tags: create, update, delete and restore. Names and glyphs
/// are private; they never go into exception text or log lines.
@Singleton(order: 2)
final class PeopleTagsCase extends UseCaseBase {
  PeopleTagsCase(
    this._tags, {
    required super.env,
    required super.logger,
  });

  final PeopleTagsRepositoryPort _tags;

  Future<List<PersonTag>> list({required String ownerId}) =>
      _tags.list(ownerId);

  Future<PersonTag> create({
    required String ownerId,
    required String name,
    required String clientOpId,
    String? glyph,
    int? color,
    int? fromAutoKind,
    String? fromBeaconId,
  }) async {
    if (fromAutoKind != null && fromBeaconId != null) throw _invalidTag();
    final trimmed = _validName(name);
    final tagGlyph = glyph == null
        ? _defaultGlyph(trimmed)
        : _validGlyph(glyph);
    return _tags.create(
      ownerId: ownerId,
      clientOpId: clientOpId,
      fingerprint: _fingerprint('create', [
        name,
        glyph,
        color,
        if (fromAutoKind != null || fromBeaconId != null) ...[
          fromAutoKind,
          fromBeaconId,
        ],
      ]),
      name: trimmed,
      glyph: tagGlyph,
      color: color == null ? null : _validColor(color),
      fromAutoKind: fromAutoKind == null ? null : _validKind(fromAutoKind),
      fromBeaconId: fromBeaconId,
    );
  }

  Future<PersonTag> update({
    required String ownerId,
    required String id,
    required String clientOpId,
    String? name,
    String? glyph,
    int? color,
    int? ord,
  }) async => _tags.update(
    ownerId: ownerId,
    clientOpId: clientOpId,
    fingerprint: _fingerprint('update', [id, name, glyph, color, ord]),
    id: id,
    name: name == null ? null : _validName(name),
    glyph: glyph == null ? null : _validGlyph(glyph),
    color: color == null ? null : _validColor(color),
    ord: ord,
  );

  Future<PersonTagSnapshot> delete({
    required String ownerId,
    required String id,
    required String clientOpId,
  }) async => _tags.delete(
    ownerId: ownerId,
    clientOpId: clientOpId,
    fingerprint: _fingerprint('delete', [id]),
    id: id,
  );

  Future<PersonTag> restore({
    required String ownerId,
    required PersonTagSnapshot snapshot,
    required String clientOpId,
  }) async {
    final tag = snapshot.tag;
    _validName(tag.name);
    _validGlyph(tag.glyph);
    _validColor(tag.color);
    if (tag.id.isEmpty ||
        snapshot.memberIds.length != snapshot.sources.length ||
        snapshot.sources.any((s) => s < 0 || s > 4)) {
      throw PeopleTagsException(
        peopleTagsCode: PeopleTagsExceptionCode.invalidTag,
      );
    }
    return _tags.restore(
      ownerId: ownerId,
      clientOpId: clientOpId,
      fingerprint: _fingerprint('restore', [snapshot.toJson()]),
      snapshot: snapshot,
    );
  }

  /// [ops] are `{tagId, personId, op: add|remove, source}`.
  Future<void> applyMembers({
    required String ownerId,
    required List<Map<String, dynamic>> ops,
    required String clientOpId,
  }) {
    if (ops.length > kPersonTagMaxOpsPerCall) throw _invalidTag();
    final parsed = [for (final o in ops) _parseOp(ownerId, o)];
    return _tags.applyMembers(
      ownerId: ownerId,
      clientOpId: clientOpId,
      fingerprint: _fingerprint('members', [
        for (final o in parsed) [o.tagId, o.personId, o.add, o.source],
      ]),
      ops: parsed,
    );
  }

  Future<List<PersonTagMembers>> memberships({required String ownerId}) =>
      _tags.memberships(ownerId);

  Future<List<String>> tagIdsOf({
    required String ownerId,
    required String personId,
  }) => _tags.tagIdsOf(ownerId, personId);

  Future<List<PersonAutoTagSummary>> autoTags({required String ownerId}) =>
      _tags.autoTags(ownerId);

  Future<PersonAutoTagSummary> setAutoTagPref({
    required String ownerId,
    required int kind,
    required bool showInFilters,
  }) async {
    final valid = PersonAutoTagKind.fromSmallint(_validKind(kind));
    return _tags.setAutoTagPref(
      ownerId: ownerId,
      kind: valid.smallintValue,
      showInFilters: showInFilters,
    );
  }

  Future<List<String>> autoTagMembers({
    required String ownerId,
    required int kind,
  }) => _tags.autoTagMembers(ownerId, _validKind(kind));

  Future<List<PersonAutoTagOf>> autoTagsOf({
    required String ownerId,
    required String personId,
  }) => _tags.autoTagsOf(ownerId, personId);

  Future<PersonTagSuggestionState> suggestionState({
    required String ownerId,
  }) => _tags.suggestionState(ownerId);

  /// [outcome] is `accepted`, `skipped`, `disabled` or `enabled`.
  Future<PersonTagSuggestionState> recordSuggestion({
    required String ownerId,
    required String outcome,
    required String clientOpId,
  }) {
    if (!_suggestionOutcomes.contains(outcome)) throw _invalidTag();
    return _tags.recordSuggestion(
      ownerId: ownerId,
      clientOpId: clientOpId,
      fingerprint: _fingerprint('suggestion', [outcome]),
      outcome: outcome,
    );
  }

  static const _suggestionOutcomes = {
    'accepted',
    'skipped',
    'disabled',
    'enabled',
  };

  static int _validKind(int kind) {
    if (!PersonAutoTagKind.values.any((k) => k.smallintValue == kind)) {
      throw _invalidTag();
    }
    return kind;
  }

  static PersonTagMemberOp _parseOp(String ownerId, Map<String, dynamic> op) {
    final tagId = op['tagId'] as String?;
    final personId = op['personId'] as String?;
    final kind = op['op'] as String?;
    final source = op['source'] as int?;
    if (tagId == null ||
        personId == null ||
        personId == ownerId ||
        (kind != 'add' && kind != 'remove') ||
        source == null ||
        source < 0 ||
        source > kPersonTagMaxSource) {
      throw _invalidTag();
    }
    return PersonTagMemberOp(
      tagId: tagId,
      personId: personId,
      add: kind == 'add',
      source: source,
    );
  }

  static PeopleTagsException _invalidTag() => PeopleTagsException(
    peopleTagsCode: PeopleTagsExceptionCode.invalidTag,
  );

  static String _fingerprint(String op, List<Object?> payload) =>
      sha256.convert(utf8.encode(jsonEncode([op, ...payload]))).toString();

  static String _validName(String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty || trimmed.runes.length > kPersonTagMaxNameLength) {
      throw PeopleTagsException(
        peopleTagsCode: PeopleTagsExceptionCode.invalidTag,
      );
    }
    return trimmed;
  }

  static String _validGlyph(String glyph) {
    if (glyph.isEmpty ||
        glyph.length > kPersonTagMaxGlyphUnits ||
        glyph.contains(_whitespace)) {
      throw PeopleTagsException(
        peopleTagsCode: PeopleTagsExceptionCode.invalidTag,
      );
    }
    return glyph;
  }

  static int _validColor(int color) {
    if (color < 0 || color >= kPersonTagColors) {
      throw PeopleTagsException(
        peopleTagsCode: PeopleTagsExceptionCode.invalidTag,
      );
    }
    return color;
  }

  static String _defaultGlyph(String trimmedName) =>
      String.fromCharCode(trimmedName.runes.first).toUpperCase();

  static final _whitespace = RegExp(r'\s');
}
