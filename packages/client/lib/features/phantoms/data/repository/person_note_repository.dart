import 'package:injectable/injectable.dart';
import 'package:tentura/data/service/remote_api_client/remote_request_client.dart';
import 'package:tentura/data/service/remote_api_service.dart';
import 'package:tentura/domain/exception/generic_exception.dart';

import '../../domain/entity/person_note.dart';
import '../../domain/port/person_note_repository_port.dart';
import '../gql/_g/person_note.req.gql.dart';

@LazySingleton(as: PersonNoteRepositoryPort)
final class PersonNoteRepository implements PersonNoteRepositoryPort {
  PersonNoteRepository(this._remote);

  final RemoteRequestClient _remote;

  @override
  Future<List<PersonNoteSection>> read(PersonNoteSubject subject) async {
    final data = await _request(
      GPersonNoteReq(
        (builder) => builder.vars
          ..subjectUserId = subject.userId
          ..subjectPhantomId = subject.phantomId,
      ),
      'PersonNote',
    );
    final rows = data.personNote;
    if (rows == null) return const [];
    return [
      for (final row in rows)
        (
          body: row.body,
          mergedFrom: switch ((
            subject,
            row.subjectPhantomId,
            row.phantomName,
          )) {
            (_, null, null) => null,
            (PhantomNoteSubject(:final id), final sourceId, _)
                when sourceId == id =>
              null,
            (UserNoteSubject(), final String id, final String name) => (
              subject: PhantomNoteSubject(id),
              name: name,
            ),
            _ => throw const FormatException('Invalid note section'),
          },
        ),
    ];
  }

  @override
  Future<void> save(PersonNoteSubject subject, String body) async {
    if (body.isEmpty) {
      await _request(
        GPersonNoteDeleteReq(
          (builder) => builder.vars
            ..subjectUserId = subject.userId
            ..subjectPhantomId = subject.phantomId,
        ),
        'PersonNoteDelete',
      );
      // Deleting an already absent note also leaves the row absent.
      return;
    }
    final data = await _request(
      GPersonNoteUpsertReq(
        (builder) => builder.vars
          ..subjectUserId = subject.userId
          ..subjectPhantomId = subject.phantomId
          ..body = body,
      ),
      'PersonNoteUpsert',
    );
    if (!data.personNoteUpsert) throw const UnknownException();
  }

  @override
  Future<List<PersonNoteSubject>> search(String query) async {
    final data = await _request(
      GPersonNoteSearchReq((builder) => builder.vars.q = query),
      'PersonNoteSearch',
    );
    return [
      for (final hit in data.personNoteSearch)
        switch ((hit.subjectUserId, hit.subjectPhantomId)) {
          (final String id, null) => UserNoteSubject(id),
          (null, final String id) => PhantomNoteSubject(id),
          _ => throw const FormatException('Invalid note search subject'),
        },
    ];
  }

  Future<TData> _request<TData, TVars>(
    OperationRequest<TData, TVars> request,
    String label,
  ) async {
    final response = await _remote
        .request(request)
        .firstLinkResponse(label: label);
    return response.dataOrThrow(label: label);
  }
}

extension on PersonNoteSubject {
  String? get userId => switch (this) {
    UserNoteSubject(:final id) => id,
    PhantomNoteSubject() => null,
  };

  String? get phantomId => switch (this) {
    UserNoteSubject() => null,
    PhantomNoteSubject(:final id) => id,
  };
}
