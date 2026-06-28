class BackDismissibleOverlayHistorySentinel {
  BackDismissibleOverlayHistorySentinel({required this.onPop});

  final void Function() onPop;

  void markHandledByBack() {}

  void dispose({bool consumeGeneratedPop = false}) {}
}
