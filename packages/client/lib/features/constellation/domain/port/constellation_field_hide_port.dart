abstract interface class ConstellationFieldHidePort {
  Future<void> hide({
    required int targetKind,
    required String targetId,
  });

  Future<void> unhide({
    required int targetKind,
    required String targetId,
  });
}
