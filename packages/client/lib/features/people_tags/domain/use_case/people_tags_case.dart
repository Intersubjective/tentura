import 'dart:async';

import 'package:injectable/injectable.dart';
import 'package:uuid/uuid.dart';

import 'package:tentura/domain/entity/realtime/realtime_entity_change.dart';
import 'package:tentura/domain/use_case/realtime_sync_case.dart';
import 'package:tentura/domain/use_case/use_case_base.dart';

import '../entity/people_tags_entities.dart';
import '../port/people_tags_repository_port.dart';

/// The one owner of the viewer's private people tags: the tag list and the
/// membership index (`tagId → person ids`), the single source of own tags on
/// every surface.
@singleton
final class PeopleTagsCase extends UseCaseBase {
  PeopleTagsCase(
    this._repository,
    this._realtimeSyncCase, {
    required super.env,
    required super.logger,
  }) {
    _subscription = _realtimeSyncCase
        .changesFor(const {RealtimeEntityKind.personTag})
        .listen(_onChange);
  }

  final PeopleTagsRepositoryPort _repository;
  final RealtimeSyncCase _realtimeSyncCase;

  static const _debounce = Duration(milliseconds: 300);
  static const _applyAttempts = 2;

  late final StreamSubscription<RealtimeEntityChange> _subscription;
  final _changes = StreamController<void>.broadcast();
  final _members = <String, Set<String>>{};
  final _uuid = const Uuid();

  List<PersonTag> _tags = const [];
  List<PersonAutoTag> _autoTags = const [];
  BigInt? _lastRevision;
  Timer? _timer;

  /// Fires after every change of the tags or the membership index.
  Stream<void> get changes => _changes.stream;

  /// Own tags in `ord` order.
  List<PersonTag> get tags => _tags;

  /// Automatic tags with their counts and filter switches.
  List<PersonAutoTag> get autoTags => _autoTags;

  /// Ids of the people in own tag [tagId].
  Set<String> peopleInTag(String tagId) => {...?_members[tagId]};

  /// Ids of everyone who is in at least one own tag.
  Set<String> get taggedIds => {for (final p in _members.values) ...p};

  /// Ids of the own tags [personId] is in.
  Set<String> tagsOfPerson(String personId) => {
    for (final e in _members.entries)
      if (e.value.contains(personId)) e.key,
  };

  /// The automatic tags [personId] carries, as the server derives them.
  Future<List<PersonAutoTagOf>> autoTagsOf(String personId) async =>
      (await _repository.personTagsOf(personId)).auto;

  Future<void> load() async {
    final results = await Future.wait([
      _repository.personTags(),
      _repository.personTagMemberships(),
    ]);
    _tags = [...results[0] as List<PersonTag>]
      ..sort((a, b) => a.ord.compareTo(b.ord));
    _members
      ..clear()
      ..addEntries([
        for (final m in results[1] as List<PersonTagMembers>)
          MapEntry(m.tagId, {...m.personIds}),
      ]);
    _emit();
  }

  Future<void> loadAutoTags() async {
    _autoTags = await _repository.personAutoTags();
    _emit();
  }

  /// Ids of the people in the automatic tag [kind].
  Future<List<String>> autoTagMembers(int kind) =>
      _repository.personAutoTagMembers(kind);

  /// Moves own tag [id] to the 1-based position [ord]; the server closes up
  /// the rest, so the list is reloaded.
  Future<void> moveTag({required String id, required int ord}) async {
    await _repository.personTagUpdate(
      id: id,
      ord: ord,
      clientOpId: _uuid.v4(),
    );
    await load();
  }

  /// Deletes own tag [id]; the snapshot feeds [restoreTag] (Undo).
  Future<PersonTagSnapshot> deleteTag(String id) async {
    final snapshot = await _repository.personTagDelete(
      id: id,
      clientOpId: _uuid.v4(),
    );
    await load();
    return snapshot;
  }

  /// Brings a deleted tag back under the same id.
  Future<void> restoreTag(PersonTagSnapshot snapshot) async {
    await _repository.personTagRestore(
      snapshot: snapshot,
      clientOpId: _uuid.v4(),
    );
    await load();
  }

  Future<void> setAutoTagShownInFilters({
    required int kind,
    required bool show,
  }) async {
    final updated = await _repository.personAutoTagPrefSet(
      kind: kind,
      showInFilters: show,
    );
    _autoTags = [
      for (final t in _autoTags)
        if (t.kind == kind) updated else t,
    ];
    _emit();
  }

  Future<void> addToTag({required String personId, required String tagId}) =>
      applyMembership([
        PersonTagMemberOp(tagId: tagId, personId: personId, add: true),
      ]);

  Future<void> removeFromTag({
    required String personId,
    required String tagId,
  }) => applyMembership([
    PersonTagMemberOp(tagId: tagId, personId: personId, add: false),
  ]);

  /// Creates an own tag and puts it last in the list. With [fromAutoKind]
  /// the server fills it with the people of that automatic tag, so the
  /// membership index is reloaded; likewise with [fromBeaconId], which fills
  /// it with the other members of that Request.
  Future<PersonTag> createTag({
    required String name,
    String? glyph,
    int? color,
    int? fromAutoKind,
    String? fromBeaconId,
  }) async {
    final tag = await _repository.personTagCreate(
      name: name,
      glyph: glyph,
      color: color,
      fromAutoKind: fromAutoKind,
      fromBeaconId: fromBeaconId,
      clientOpId: _uuid.v4(),
    );
    if (fromAutoKind != null || fromBeaconId != null) {
      await load();
    } else {
      _tags = [..._tags, tag]..sort((a, b) => a.ord.compareTo(b.ord));
      _emit();
    }
    return tag;
  }

  /// Whether "Tag from participants" is offered: only to a member of a
  /// Request, never on a Post.
  bool canTagFromParticipants({
    required bool viewerIsMember,
    required bool isRequest,
  }) => viewerIsMember && isRequest;

  /// Renames or recolours own tag [id].
  Future<PersonTag> updateTag({
    required String id,
    String? name,
    String? glyph,
    int? color,
  }) async {
    final tag = await _repository.personTagUpdate(
      id: id,
      name: name,
      glyph: glyph,
      color: color,
      clientOpId: _uuid.v4(),
    );
    _tags = [
      for (final t in _tags)
        if (t.id == id) tag else t,
    ];
    _emit();
    return tag;
  }

  /// Applies [ops] to the index and sends them as one batch; the ops that
  /// change nothing are dropped, and a failed send rolls the index back.
  Future<void> applyMembership(List<PersonTagMemberOp> ops) async {
    final changed = [
      for (final op in ops)
        if (_setMember(op.tagId, op.personId, op.add)) op,
    ];
    if (changed.isEmpty) return;
    // One id per batch, reused by every retry so the server applies it once.
    final clientOpId = _uuid.v4();
    for (var attempt = 1; ; attempt++) {
      try {
        await _repository.personTagMembersApply(
          ops: changed,
          clientOpId: clientOpId,
        );
        return;
      } catch (_) {
        if (attempt < _applyAttempts) continue;
        for (final op in changed.reversed) {
          _setMember(op.tagId, op.personId, !op.add);
        }
        rethrow;
      }
    }
  }

  Future<void> dispose() async {
    _timer?.cancel();
    await _subscription.cancel();
    await _changes.close();
  }

  /// Sets the membership in the index; false when it already was so.
  bool _setMember(String tagId, String personId, bool add) {
    final people = _members.putIfAbsent(tagId, () => <String>{});
    final changed = add ? people.add(personId) : people.remove(personId);
    if (changed) _emit();
    return changed;
  }

  void _onChange(RealtimeEntityChange change) {
    final revision = change.revision;
    final last = _lastRevision;
    if (revision != null) {
      if (last != null && revision <= last) return;
      _lastRevision = revision;
    }
    _timer?.cancel();
    _timer = Timer(_debounce, () => unawaited(_refetch()));
  }

  Future<void> _refetch() async {
    try {
      await load();
    } catch (e, s) {
      logger.warning('people tags refetch failed', e, s);
    }
  }

  void _emit() {
    if (!_changes.isClosed) _changes.add(null);
  }
}
