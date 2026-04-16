import 'dart:async';

import 'package:injectable/injectable.dart';

import 'package:tentura/data/service/remote_api_service.dart';

/// Exposes app-update signals from the remote API layer without pulling
/// [RemoteApiService] into UI cubits.
@Singleton(env: [Environment.dev, Environment.prod])
class AppUpdateRepository {
  AppUpdateRepository(this._remoteApiService);

  final RemoteApiService _remoteApiService;

  Stream<String> get minClientVersionStream =>
      _remoteApiService.minClientVersionStream;
}
