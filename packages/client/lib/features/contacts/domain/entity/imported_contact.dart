import 'dart:typed_data';

final class ImportedContact {
  ImportedContact._(
    this.name,
    List<String> emails,
    List<String> phones, [
    Uint8List? photoBytes,
  ]) : emails = List.unmodifiable(emails),
       phones = List.unmodifiable(phones),
       photoBytes = photoBytes?.asUnmodifiableView();

  final String name;
  final List<String> emails;
  final List<String> phones;
  final Uint8List? photoBytes;

  static ImportedContact? fromFields(
    String name,
    List<String> emails,
    List<String> phones, {
    Uint8List? photoBytes,
  }) {
    if (name.isEmpty && emails.isEmpty && phones.isEmpty) return null;
    return ImportedContact._(name, emails, phones, photoBytes);
  }
}
