import 'package:flutter/foundation.dart';

/// A beacon another screen asked the map to select, e.g. a Post's «Показать
/// на поле». The map takes it once its field is loaded.
final class ConstellationFocusRequest {
  ConstellationFocusRequest._();

  static final instance = ConstellationFocusRequest._();

  final _pending = ValueNotifier<String?>(null);

  ValueListenable<String?> get pending => _pending;

  // ignore: avoid_setters_without_getters -- [pending] is the getter.
  set requested(String beaconId) => _pending.value = beaconId;

  /// The pending beacon id, cleared so it is focused only once.
  String? take() {
    final id = _pending.value;
    _pending.value = null;
    return id;
  }
}
