import 'package:get_it/get_it.dart';

import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/profile/domain/port/profile_repository_port.dart';

/// Profiles of the people listed on a tag screen, fetched once per id.
final class PeopleTagProfiles {
  final _profiles = <String, Profile>{};

  Profile? of(String id) => _profiles[id];

  /// Fetches the profiles of [ids] not held yet; true when any arrived.
  Future<bool> ensure(Iterable<String> ids) async {
    final missing = {
      for (final id in ids)
        if (!_profiles.containsKey(id)) id,
    };
    if (missing.isEmpty) return false;
    final fetched = await GetIt.I<ProfileRepositoryPort>().fetchProfilesByIds(
      missing,
    );
    for (final p in fetched) {
      _profiles[p.id] = p;
    }
    return fetched.isNotEmpty;
  }
}
