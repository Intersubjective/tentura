import 'package:injectable/injectable.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:tentura/data/service/remote_api_client/remote_request_client.dart';
import 'package:tentura/data/service/remote_api_service.dart';

import '../../domain/port/email_discoverability_repository_port.dart';
import '../gql/_g/email_discoverability.req.gql.dart';

@LazySingleton(as: EmailDiscoverabilityRepositoryPort)
class EmailDiscoverabilityRepository
    implements EmailDiscoverabilityRepositoryPort {
  EmailDiscoverabilityRepository(this._remote);

  final RemoteRequestClient _remote;
  final _preferences = SharedPreferencesAsync();

  static const _label = 'EmailDiscoverability';

  @override
  Future<bool> fetchEnabled() => _remote
      .request(GEmailDiscoverabilityReq())
      .firstLinkResponse(label: _label)
      .then((result) => result.dataOrThrow(label: _label).emailDiscoverability);

  @override
  Future<bool> setEnabled({required bool enabled}) => _remote
      .request(
        GEmailDiscoverabilitySetReq(
          (request) => request.vars.enabled = enabled,
        ),
      )
      .firstLinkResponse(label: _label)
      .then(
        (result) => result.dataOrThrow(label: _label).emailDiscoverabilitySet,
      );

  @override
  Future<bool> isExplainerDismissed(String accountId) async =>
      await _preferences.getBool(_dismissalKey(accountId)) ?? false;

  @override
  Future<void> dismissExplainer(String accountId) =>
      _preferences.setBool(_dismissalKey(accountId), true);

  static String _dismissalKey(String accountId) =>
      'emailDiscoverability:explainerDismissed:$accountId';
}
