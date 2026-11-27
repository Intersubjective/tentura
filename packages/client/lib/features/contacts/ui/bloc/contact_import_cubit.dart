import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:tentura/features/phantoms/domain/entity/phantom_import.dart';
import 'package:tentura_root/consts.dart';

import '../../domain/entity/imported_contact.dart';
import '../../domain/use_case/contact_import_case.dart';

part 'contact_import_cubit.freezed.dart';

enum ContactImportStatus { ready, importing, retry }

@freezed
abstract class ContactImportRow with _$ContactImportRow {
  const factory ContactImportRow({
    required ImportedContact source,
    required String name,
    @Default(false) bool selected,
    PhantomImportOutcome? outcome,
  }) = _ContactImportRow;

  const ContactImportRow._();

  static String foldName(String name) => name.trim().toLowerCase();

  bool get needsEditor => source.name.runes.length < kTitleMinLength;
  bool get created => outcome is PhantomImportCreated;
  String get importName => String.fromCharCodes(
    name.trim().runes.take(kTitleMaxLength),
  ).trimRight();
  bool get hasValidName => importName.runes.length >= kTitleMinLength;
}

@freezed
abstract class ContactImportState with _$ContactImportState {
  const factory ContactImportState({
    required List<ContactImportRow> rows,
    @Default(ContactImportStatus.ready) ContactImportStatus status,
    @Default(true) bool usePhoto,
    @Default(false) bool keepContacts,
    @Default('') String query,
  }) = _ContactImportState;

  const ContactImportState._();

  bool get busy => status == ContactImportStatus.importing;
  bool get canEdit => status == ContactImportStatus.ready;
  bool get canSubmit {
    if (busy) return false;
    final selected = rows.where((row) => row.selected);
    return selected.isNotEmpty && selected.every((row) => row.hasValidName);
  }
}

final class ContactImportCubit extends Cubit<ContactImportState> {
  ContactImportCubit(this._import, List<ImportedContact> contacts)
    : super(
        ContactImportState(
          rows: [
            for (final contact in contacts)
              ContactImportRow(source: contact, name: contact.name),
          ],
        ),
      );

  final ContactImportCase _import;

  void search(String query) =>
      emit(state.copyWith(query: ContactImportRow.foldName(query)));

  void setUsePhoto(bool value) {
    if (state.canEdit) emit(state.copyWith(usePhoto: value));
  }

  void setKeepContacts(bool value) {
    if (state.canEdit) emit(state.copyWith(keepContacts: value));
  }

  void select(int index, {required bool selected}) =>
      _update(index, state.rows[index].copyWith(selected: selected));

  void rename(int index, String name) =>
      _update(index, state.rows[index].copyWith(name: name, outcome: null));

  void _update(int index, ContactImportRow row) {
    if (!state.canEdit || state.rows[index].created) return;
    final rows = [...state.rows];
    rows[index] = row;
    emit(state.copyWith(rows: rows));
  }

  Future<bool> submit() async {
    if (!state.canSubmit) return false;
    final selected = [
      for (final (index, row) in state.rows.indexed)
        if (row.selected) index,
    ];
    final entries = [
      for (final index in selected)
        (
          contact: (
            name: state.rows[index].importName,
            email: state.rows[index].source.emails.firstOrNull,
            phone: state.rows[index].source.phones.firstOrNull,
          ),
          photo: state.usePhoto ? state.rows[index].source.photoBytes : null,
        ),
    ];
    emit(state.copyWith(status: ContactImportStatus.importing));
    try {
      final outcomes = await _import.run(
        entries,
        keepContacts: state.keepContacts,
      );
      if (!isClosed) {
        final rows = [...state.rows];
        for (final outcome in outcomes) {
          final index = selected[outcome.rowIndex];
          rows[index] = rows[index].copyWith(outcome: outcome, selected: false);
        }
        emit(state.copyWith(rows: rows, status: ContactImportStatus.ready));
      }
      return outcomes.any((outcome) => outcome is PhantomImportCreated);
    } on Exception {
      if (!isClosed) emit(state.copyWith(status: ContactImportStatus.retry));
      return false;
    }
  }
}
