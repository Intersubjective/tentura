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
  BigInt? _lastRevision;
  Timer? _timer;

  /// Fires after every change of the tags or the membership index.
  Stream<void> get changes => _changes.stream;

  /// Own tags in `ord` order.
  List<PersonTag> get tags => _tags;

  /// Ids of the people in own tag [tagId].
  Set<String> peopleInTag(String tagId) => {...?_members[tagId]};

  /// Ids of the own tags [personId] is in.
  Set<String> tagsOfPerson(String personId) => {
    for (final e in _members.entries)
      if (e.value.contains(personId)) e.key,
  };

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

  Future<void> addToTag({required String personId, required String tagId}) =>
      _edit(personId: personId, tagId: tagId, add: true);

  Future<void> removeFromTag({
    required String personId,
    required String tagId,
  }) => _edit(personId: personId, tagId: tagId, add: false);

  Future<void> dispose() async {
    _timer?.cancel();
    await _subscription.cancel();
    await _changes.close();
  }

  Future<void> _edit({
    required String personId,
    required String tagId,
    required bool add,
  }) async {
    if (!_setMember(tagId, personId, add)) return;
    final op = PersonTagMemberOp(tagId: tagId, personId: personId, add: add);
    // One id per edit, reused by every retry so the server applies it once.
    final clientOpId = _uuid.v4();
    for (var attempt = 1; ; attempt++) {
      try {
        await _repository.personTagMembersApply(
          ops: [op],
          clientOpId: clientOpId,
        );
        return;
      } catch (_) {
        if (attempt < _applyAttempts) continue;
        _setMember(tagId, personId, !add);
        rethrow;
      }
    }
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
