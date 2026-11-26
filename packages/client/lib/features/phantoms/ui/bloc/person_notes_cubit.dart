import 'package:flutter_bloc/flutter_bloc.dart';

import '../../domain/entity/person_note.dart';
import '../../domain/port/person_note_repository_port.dart';

typedef PersonNotesState = ({
  List<PersonNoteSection>? sections,
  bool busy,
  bool failed,
});

final class PersonNotesCubit extends Cubit<PersonNotesState> {
  PersonNotesCubit(this._repository, this._subject)
    : super((sections: null, busy: false, failed: false));

  final PersonNoteRepositoryPort _repository;
  final PersonNoteSubject _subject;

  Future<void> load() async {
    if (state.busy) return;
    emit((sections: null, busy: true, failed: false));
    try {
      final sections = await _repository.read(_subject);
      if (isClosed) return;
      emit((
        sections: List.unmodifiable([
          if (!sections.any((section) => section.mergedFrom == null))
            (body: '', mergedFrom: null),
          ...sections,
        ]),
        busy: false,
        failed: false,
      ));
    } on Exception {
      if (!isClosed) emit((sections: null, busy: false, failed: true));
    }
  }

  Future<void> save(PersonNoteSection section, String body) async {
    final sections = state.sections;
    if (sections == null || state.busy || section.body == body) return;
    emit((sections: sections, busy: true, failed: false));
    try {
      await _repository.save(section.mergedFrom?.subject ?? _subject, body);
      if (isClosed) return;
      emit((
        sections: List.unmodifiable([
          for (final current in sections)
            if (current != section)
              current
            else if (current.mergedFrom == null || body.isNotEmpty)
              (body: body, mergedFrom: current.mergedFrom),
        ]),
        busy: false,
        failed: false,
      ));
    } on Exception {
      if (!isClosed) emit((sections: sections, busy: false, failed: true));
    }
  }
}
