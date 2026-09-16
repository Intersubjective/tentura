import 'package:tentura/features/profile_view/domain/port/person_shared_context_port.dart';

final class FakePersonSharedContextPort implements PersonSharedContextPort {
  FakePersonSharedContextPort({this.contexts = const [], this.error});

  List<PersonSharedContext> contexts;
  Object? error;

  @override
  Future<List<PersonSharedContext>> fetchSharedContexts(String userId) async {
    final e = error;
    if (e != null) throw e;
    return contexts;
  }
}
