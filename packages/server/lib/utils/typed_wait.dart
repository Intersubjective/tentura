/// Typed parallel waits for heterogeneous futures, with `Future.wait` error
/// semantics.
///
/// Dart 3's record `.wait` (`await (f0, f1).wait`) gives typed results but
/// throws a `ParallelWaitError` that wraps every failure. Callers here map the
/// original exception (an `ExceptionBase`, a postgres error) upstream, so this
/// keeps what `Future.wait([...])` does: every future runs to completion, and
/// the first error to occur, in time order, is rethrown as itself with its own
/// stack trace. The values land in a typed record, so reordering a future is a
/// compile error instead of a runtime `results[i] as T` cast failure.
library;

import 'dart:async';

extension TypedWait2<A, B> on (Future<A>, Future<B>) {
  /// Waits for both futures; see the library doc for error semantics.
  Future<(A, B)> get waitAll async {
    late A a;
    late B b;
    await Future.wait<void>([
      $1.then((v) => a = v),
      $2.then((v) => b = v),
    ]);
    return (a, b);
  }
}

extension TypedWait3<A, B, C> on (Future<A>, Future<B>, Future<C>) {
  /// Waits for all three futures; see the library doc for error semantics.
  Future<(A, B, C)> get waitAll async {
    late A a;
    late B b;
    late C c;
    await Future.wait<void>([
      $1.then((v) => a = v),
      $2.then((v) => b = v),
      $3.then((v) => c = v),
    ]);
    return (a, b, c);
  }
}

extension TypedWait4<A, B, C, D>
    on (Future<A>, Future<B>, Future<C>, Future<D>) {
  /// Waits for all four futures; see the library doc for error semantics.
  Future<(A, B, C, D)> get waitAll async {
    late A a;
    late B b;
    late C c;
    late D d;
    await Future.wait<void>([
      $1.then((v) => a = v),
      $2.then((v) => b = v),
      $3.then((v) => c = v),
      $4.then((v) => d = v),
    ]);
    return (a, b, c, d);
  }
}

extension TypedWait5<A, B, C, D, E>
    on (Future<A>, Future<B>, Future<C>, Future<D>, Future<E>) {
  /// Waits for all five futures; see the library doc for error semantics.
  Future<(A, B, C, D, E)> get waitAll async {
    late A a;
    late B b;
    late C c;
    late D d;
    late E e;
    await Future.wait<void>([
      $1.then((v) => a = v),
      $2.then((v) => b = v),
      $3.then((v) => c = v),
      $4.then((v) => d = v),
      $5.then((v) => e = v),
    ]);
    return (a, b, c, d, e);
  }
}

extension TypedWait6<A, B, C, D, E, F>
    on (Future<A>, Future<B>, Future<C>, Future<D>, Future<E>, Future<F>) {
  /// Waits for all six futures; see the library doc for error semantics.
  Future<(A, B, C, D, E, F)> get waitAll async {
    late A a;
    late B b;
    late C c;
    late D d;
    late E e;
    late F f;
    await Future.wait<void>([
      $1.then((v) => a = v),
      $2.then((v) => b = v),
      $3.then((v) => c = v),
      $4.then((v) => d = v),
      $5.then((v) => e = v),
      $6.then((v) => f = v),
    ]);
    return (a, b, c, d, e, f);
  }
}
