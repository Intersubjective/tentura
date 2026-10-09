/// The committed-scene inputs the freeze gate holds back during a drag.
enum SceneInputSource { store, outbox, transition }

/// Holds inputs that would change the committed scene while it is frozen
/// (architecture §5.4). Held inputs coalesce per source, the latest winning,
/// and reach [onApply] only on [release].
class SceneUpdateGate {
  SceneUpdateGate({required this.onApply});

  final void Function(SceneInputSource source, Object input) onApply;

  final Map<SceneInputSource, Object> _held = {};

  bool _isFrozen = false;

  bool get isFrozen => _isFrozen;

  void freeze() => _isFrozen = true;

  /// Applies [input] at once, or holds it while the gate is frozen.
  void submit(SceneInputSource source, Object input) {
    if (_isFrozen) {
      _held[source] = input;
    } else {
      onApply(source, input);
    }
  }

  /// Unfreezes and applies what was held, one input per source.
  void release() {
    _isFrozen = false;
    final held = Map.of(_held);
    _held.clear();
    for (final entry in held.entries) {
      onApply(entry.key, entry.value);
    }
  }
}
