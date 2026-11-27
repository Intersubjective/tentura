import 'dart:convert';
import 'dart:typed_data';

import '../../domain/entity/imported_contact.dart';

export '../../domain/entity/imported_contact.dart';

final _vCardFold = RegExp(r'\r?\n[ \t]');
final _vCardEscape = RegExp(r'\\([\\,;nN])');
final _vCardNameParts = RegExp(r'^((?:\\.|[^;\\])*)(?:;((?:\\.|[^;\\])*))?');
final _telephoneScheme = RegExp('^tel:', caseSensitive: false);
final _imageDataUri = RegExp(
  '^data:image/[^;,]+;base64,',
  caseSensitive: false,
);

List<ImportedContact> parseVCard(List<int> bytes) {
  final text = utf8.decode(bytes, allowMalformed: true);
  final contacts = <ImportedContact>[];
  List<String>? card;
  for (final line in const LineSplitter().convert(
    text.replaceAll(_vCardFold, ''),
  )) {
    switch (line.toUpperCase()) {
      case 'BEGIN:VCARD':
        card = [];
      case 'END:VCARD':
        final contact = card == null ? null : _parseCard(card);
        if (contact != null) contacts.add(contact);
        card = null;
      default:
        card?.add(line);
    }
  }
  return contacts;
}

ImportedContact? _parseCard(List<String> lines) {
  var version = '';
  var name = '';
  var structuredName = '';
  final emails = <String>[];
  final phones = <String>[];
  Uint8List? photo;

  for (final line in lines) {
    final delimiter = line.indexOf(':');
    if (delimiter < 1) continue;
    final property = line.substring(0, delimiter).toUpperCase().split(';');
    final value = line.substring(delimiter + 1).trim();
    if (value.isEmpty) continue;

    switch (property.first.split('.').last) {
      case 'VERSION':
        version = value;
      case 'FN':
        name = _vCardText(value);
      case 'N':
        final parts = _vCardNameParts.firstMatch(value);
        structuredName = _joinName(
          _vCardText(parts?[2] ?? ''),
          _vCardText(parts?[1] ?? ''),
        );
      case 'EMAIL':
        emails.add(_vCardText(value));
      case 'TEL':
        final phone = _vCardText(value.replaceFirst(_telephoneScheme, ''));
        if (phone.isNotEmpty) phones.add(phone);
      case 'PHOTO':
        photo ??= _decodePhoto(property, value);
    }
  }

  if (version != '3.0' && version != '4.0') return null;
  return ImportedContact.fromFields(
    name.isEmpty ? structuredName : name,
    emails,
    phones,
    photoBytes: photo,
  );
}

String _vCardText(String value) =>
    value.replaceAllMapped(_vCardEscape, (match) {
      final escaped = match.input[match.start + 1];
      return escaped == 'n' || escaped == 'N' ? '\n' : escaped;
    }).trim();

Uint8List? _decodePhoto(List<String> property, String value) {
  final imageUri = _imageDataUri.matchAsPrefix(value);
  if (imageUri == null && !property.contains('ENCODING=B')) return null;
  final payload = imageUri == null ? value : value.substring(imageUri.end);
  if (payload.isEmpty) return null;
  try {
    return base64Decode(payload);
  } on FormatException {
    return null;
  }
}

final _csvField = RegExp(r'(?:"((?:[^"]|"")*)"|([^",\r\n]*))(,|\r\n?|\n|$)');
final _lineBreak = RegExp(r'\r\n?|\n');
final _emailHeader = RegExp(r'^E-mail [0-9]+ - Value$');
final _phoneHeader = RegExp(r'^Phone [0-9]+ - Value$');

List<ImportedContact> parseGoogleContactsCsv(List<int> bytes) {
  final text = utf8.decode(bytes, allowMalformed: true);
  final header = _readCsvRow(text, 0);
  if (header == null) return [];
  final columns = header.cells.map((cell) => cell.trim()).toList();
  final name = columns.indexOf('Name');
  final firstName = _nameColumn(columns, 'First Name', 'Given Name');
  final lastName = _nameColumn(columns, 'Last Name', 'Family Name');
  final emails = _valueColumns(columns, _emailHeader);
  final phones = _valueColumns(columns, _phoneHeader);
  if (name < 0 &&
      firstName < 0 &&
      lastName < 0 &&
      emails.isEmpty &&
      phones.isEmpty) {
    return [];
  }

  final contacts = <ImportedContact>[];
  var offset = header.end;
  while (offset < text.length) {
    final row = _readCsvRow(text, offset);
    if (row == null) {
      // Retry at the next physical line only after the logical row fails,
      // since a well-formed quoted field can span multiple lines.
      final newline = _lineBreak.allMatches(text, offset).firstOrNull;
      if (newline == null) break;
      offset = newline.end;
      continue;
    }
    offset = row.end;
    final displayName = _cell(row.cells, name).trim();
    final contact = ImportedContact.fromFields(
      displayName.isNotEmpty
          ? displayName
          : _joinName(
              _cell(row.cells, firstName).trim(),
              _cell(row.cells, lastName).trim(),
            ),
      _csvValues(row.cells, emails),
      _csvValues(row.cells, phones),
    );
    if (contact != null) contacts.add(contact);
  }
  return contacts;
}

({List<String> cells, int end})? _readCsvRow(String text, int start) {
  final cells = <String>[];
  var offset = start;
  while (true) {
    final match = _csvField.matchAsPrefix(text, offset);
    if (match == null) return null;
    final value = match[1]?.replaceAll('""', '"') ?? match[2] ?? '';
    cells.add(value);
    if (match[3] != ',') return (cells: cells, end: match.end);
    offset = match.end;
  }
}

int _nameColumn(List<String> columns, String current, String legacy) {
  final index = columns.indexOf(current);
  return index >= 0 ? index : columns.indexOf(legacy);
}

List<int> _valueColumns(List<String> columns, RegExp header) => [
  for (final (index, column) in columns.indexed)
    if (header.hasMatch(column)) index,
];

String _cell(List<String> cells, int index) =>
    index >= 0 && index < cells.length ? cells[index] : '';

List<String> _csvValues(List<String> cells, List<int> columns) => [
  for (final index in columns)
    for (final value in _cell(cells, index).split(' ::: ').map((v) => v.trim()))
      if (value.isNotEmpty) value,
];

String _joinName(String first, String last) =>
    [first, last].where((part) => part.isNotEmpty).join(' ');
