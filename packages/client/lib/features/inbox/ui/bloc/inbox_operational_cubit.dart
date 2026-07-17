import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:injectable/injectable.dart';

/// Inbox-owned operational state shared with My Work's empty-state CTA.
@singleton
final class InboxOperationalCubit extends Cubit<InboxOperationalState> {
  InboxOperationalCubit() : super(const InboxOperationalState());

  void report({required int needsMeCount, required bool loadComplete}) {
    final next = InboxOperationalState(
      needsMeCount: needsMeCount,
      loadComplete: loadComplete,
    );
    if (next == state) return;
    emit(next);
  }
}

final class InboxOperationalState {
  const InboxOperationalState({
    this.needsMeCount = 0,
    this.loadComplete = false,
  });

  final int needsMeCount;
  final bool loadComplete;

  @override
  bool operator ==(Object other) =>
      other is InboxOperationalState &&
      other.needsMeCount == needsMeCount &&
      other.loadComplete == loadComplete;

  @override
  int get hashCode => Object.hash(needsMeCount, loadComplete);
}
