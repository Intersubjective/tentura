// ignore: one_member_abstracts -- narrow write boundary for #898
abstract interface class ConstellationNewPeoplePort {
  Future<void> acknowledgeNew(Iterable<String> peerIds);
}
