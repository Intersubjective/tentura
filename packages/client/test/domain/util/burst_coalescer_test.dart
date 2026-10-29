import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tentura/domain/util/burst_coalescer.dart';

void main() {
  test('one batch unions keys including requests from microtasks', () {
    fakeAsync((async) {
      final batches = <Set<String>>[];
      final coalescer = BurstCoalescer<String>(batches.add)..request('beacon');
      scheduleMicrotask(() => coalescer.request('participant'));
      scheduleMicrotask(() => coalescer.request('offer'));
      coalescer.request('beacon');
      expect(batches, isEmpty);
      async
        ..flushMicrotasks()
        ..elapse(BurstCoalescer.window);
      expect(batches, [
        {'beacon', 'participant', 'offer'},
      ]);
      coalescer.dispose();
    });
  });

  test('requests after action starts produce exactly one further batch', () {
    fakeAsync((async) {
      final batches = <Set<String>>[];
      late final BurstCoalescer<String> coalescer;
      coalescer = BurstCoalescer<String>((keys) {
        batches.add(keys);
        if (batches.length == 1) {
          coalescer
            ..request('later')
            ..request('later')
            ..request('another');
        }
      });
      coalescer.request('first');
      async.elapse(BurstCoalescer.window);
      expect(batches, [
        {'first'},
      ]);
      async.elapse(BurstCoalescer.window);
      expect(batches, [
        {'first'},
        {'later', 'another'},
      ]);
      expect(batches.first, {'first'}, reason: 'Batch snapshots stay stable');
      coalescer.dispose();
    });
  });

  test('dispose cancels pending action and ignores later requests', () {
    fakeAsync((async) {
      final batches = <Set<String>>[];
      BurstCoalescer<String>(batches.add)
        ..request('pending')
        ..dispose()
        ..dispose()
        ..request('after-dispose');
      async.elapse(BurstCoalescer.window);
      expect(batches, isEmpty);
    });
  });
}
