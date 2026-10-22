/// Non-web builds have no browser online/offline signal.
bool browserInitiallyOnline() => true;

Stream<bool>? browserOnlineChanges() => null;
