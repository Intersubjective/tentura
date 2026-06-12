import 'dart:async';

import 'package:injectable/injectable.dart';

/// Subjective profiles: in-memory contact-name map of the current account.
///
/// Filled by `ContactsCase` (Drift cache first, then server `myContacts`).
/// Consulted synchronously by data-layer mappers to overlay the viewer's
/// private contact name over a profile's self-chosen display name.
@lazySingleton
class ContactNameStore {
  final _names = <String, String>{};

  final _changesController = StreamController<void>.broadcast();

  /// Emits whenever the map changes (rename, reset, account switch, sync).
  Stream<void> get changes => _changesController.stream;

  /// The current account's private name for [userId], or null when none.
  String? nameOf(String userId) => _names[userId];

  Map<String, String> get all => Map.unmodifiable(_names);

  void replaceAll(Map<String, String> names) {
    _names
      ..clear()
      ..addAll(names);
    _changesController.add(null);
  }

  void set(String userId, String contactName) {
    _names[userId] = contactName;
    _changesController.add(null);
  }

  void remove(String userId) {
    if (_names.remove(userId) != null) {
      _changesController.add(null);
    }
  }

  void clear() {
    if (_names.isNotEmpty) {
      _names.clear();
      _changesController.add(null);
    }
  }

  @disposeMethod
  Future<void> dispose() => _changesController.close();
}
