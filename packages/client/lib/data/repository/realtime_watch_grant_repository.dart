import 'package:injectable/injectable.dart';
import 'package:meta/meta.dart';

import 'package:tentura/data/service/remote_api_service.dart';
import 'package:tentura/domain/entity/realtime/realtime_watch.dart';
import 'package:tentura/domain/port/realtime_watch_grant_port.dart';
import 'package:tentura/env.dart';

@LazySingleton(as: RealtimeWatchGrantPort)
final class RealtimeWatchGrantRepository implements RealtimeWatchGrantPort {
  const RealtimeWatchGrantRepository(this._remoteApiService);

  static final _endpoint = Uri.parse(
    '$kServerName/api/v2/realtime/watch-grant',
  );

  final RemoteApiService _remoteApiService;

  @override
  Future<RealtimeWatchGrant> requestGrant(
    RealtimeWatchDescriptor descriptor,
  ) async {
    final json = await _remoteApiService.postAuthenticatedJson(
      _endpoint,
      body: encodeDescriptor(descriptor),
    );
    return decodeGrant(json, expectedScope: descriptor.scope);
  }

  @visibleForTesting
  static Map<String, Object?> encodeDescriptor(
    RealtimeWatchDescriptor descriptor,
  ) => {
    'scope': descriptor.scope.name,
    'subjectIds': descriptor.requestedSubjectIds.toList()..sort(),
    'projection': switch (descriptor.scope) {
      RealtimeWatchScope.graph => {
        'focus': descriptor.focusId,
        'context': descriptor.context,
        'positiveOnly': descriptor.positiveOnly,
      },
      RealtimeWatchScope.profile => {'profileId': descriptor.profileId},
      RealtimeWatchScope.people => {'beaconId': descriptor.beaconId},
    },
  };

  @visibleForTesting
  static RealtimeWatchGrant decodeGrant(
    Map<String, dynamic> json, {
    required RealtimeWatchScope expectedScope,
  }) {
    final token = json['grant'];
    final scope = _scopeFromWire(json['scope']);
    final rawSubjects = json['subjectIds'];
    final rawExpiresAt = json['expiresAt'];
    final protocolVersion = json['protocolVersion'];
    if (token is! String ||
        token.isEmpty ||
        scope != expectedScope ||
        rawSubjects is! List ||
        rawSubjects.any((subject) => subject is! String) ||
        rawExpiresAt is! String ||
        protocolVersion != 1) {
      throw const FormatException('Invalid realtime watch grant response');
    }
    final expiresAt = DateTime.tryParse(rawExpiresAt)?.toUtc();
    if (expiresAt == null) {
      throw const FormatException('Invalid realtime watch grant expiry');
    }
    return RealtimeWatchGrant(
      token: token,
      scope: scope!,
      authorizedSubjectIds: rawSubjects.cast<String>().toSet(),
      expiresAt: expiresAt,
    );
  }

  static RealtimeWatchScope? _scopeFromWire(Object? value) => switch (value) {
    'graph' => RealtimeWatchScope.graph,
    'profile' => RealtimeWatchScope.profile,
    'people' => RealtimeWatchScope.people,
    _ => null,
  };
}
