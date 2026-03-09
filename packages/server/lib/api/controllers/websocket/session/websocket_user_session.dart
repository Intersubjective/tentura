import 'dart:async';

import 'package:tentura_server/domain/entity/jwt_entity.dart';

class WebsocketUserSession {
  WebsocketUserSession(this.jwt);

  final JwtEntity jwt;

  final List<Timer> _workers = [];

  DateTime _lastSeen = DateTime.now();

  DateTime get lastSeen => _lastSeen;

  //
  void touch() => _lastSeen = DateTime.now();

  //
  void addWorker(Timer worker) => _workers.add(worker);

  //
  void removeWorker(Timer worker) => _workers.remove(worker);

  //
  void cancel() {
    for (final worker in _workers) {
      worker.cancel();
    }
  }
}
