abstract interface class EmailDiscoverabilityRepositoryPort {
  Future<bool> fetchEnabled();

  Future<bool> setEnabled({required bool enabled});

  Future<bool> isExplainerDismissed(String accountId);

  Future<void> dismissExplainer(String accountId);
}
