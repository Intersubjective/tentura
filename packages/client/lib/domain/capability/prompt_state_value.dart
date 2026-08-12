/// Server [PromptStateValue] wire values (camelCase enum names).
enum PromptStateValue {
  pending,
  answered,
  skipped;

  static PromptStateValue fromWire(String raw) =>
      PromptStateValue.values.firstWhere(
        (state) => state.name == raw,
        orElse: () =>
            throw ArgumentError.value(raw, 'raw', 'unknown invite seed prompt state'),
      );
}
