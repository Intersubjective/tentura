import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/domain/port/platform_repository_port.dart';
import 'package:tentura/features/settings/ui/bloc/settings_cubit.dart';

class _PlatformRepository implements PlatformRepositoryPort {
  _PlatformRepository(this._version);

  final Future<String> Function() _version;

  @override
  Future<String> getAppVersion() => _version();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  // #878: on web the version label is a version.json fetch with no deadline;
  // SettingsCubit.hydrated awaits it during startup, so a stalled fetch held
  // startup until the 60 s boot timeout.
  test('a version lookup that never finishes reads as no version', () async {
    final version = await SettingsCubit.appVersionOrEmpty(
      _PlatformRepository(() => Completer<String>().future),
      timeout: const Duration(milliseconds: 10),
    );

    expect(version, '');
  });

  test('a version lookup that finishes reads as that version', () async {
    final version = await SettingsCubit.appVersionOrEmpty(
      _PlatformRepository(() async => '7.59.40'),
    );

    expect(version, '7.59.40');
  });
}
