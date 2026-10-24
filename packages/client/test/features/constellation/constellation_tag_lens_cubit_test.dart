import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/features/constellation/domain/entity/constellation_field.dart';
import 'package:tentura/features/constellation/ui/bloc/constellation_tag_lens_cubit.dart';

import 'fixtures/constellation_reference_fixture.dart';

void main() {
  group('ConstellationTagLensCubit', () {
    late ConstellationTagLensCubit cubit;

    setUp(() => cubit = ConstellationTagLensCubit());
    tearDown(() => cubit.close());

    test('starts with nothing selected, in "or" mode', () {
      expect(cubit.state.isEmpty, isTrue);
      expect(cubit.state.mode, ConstellationTagFilterMode.or);
    });

    test('toggleOwn selects a tag and a second toggle clears it', () {
      cubit.toggleOwn('T1');
      expect(cubit.state.selectedOwn, {'T1'});

      cubit.toggleOwn('T1');
      expect(cubit.state.selectedOwn, isEmpty);
      expect(cubit.state.isEmpty, isTrue);
    });

    test('toggleAuto selects an automatic tag', () {
      cubit.toggleAuto(ConstellationAutoTagKind.mutualContact);
      expect(cubit.state.selectedAuto, {
        ConstellationAutoTagKind.mutualContact,
      });

      cubit.toggleAuto(ConstellationAutoTagKind.mutualContact);
      expect(cubit.state.selectedAuto, isEmpty);
    });

    test('changing the mode keeps the selection', () {
      cubit
        ..toggleOwn('T1')
        ..toggleOwn('T2')
        ..setMode(ConstellationTagFilterMode.and);

      expect(cubit.state.mode, ConstellationTagFilterMode.and);
      expect(cubit.state.selectedOwn, {'T1', 'T2'});
    });

    test('clear drops the selection and returns to "or"', () {
      cubit
        ..toggleOwn('T1')
        ..toggleAuto(ConstellationAutoTagKind.iTrust)
        ..setMode(ConstellationTagFilterMode.and)
        ..clear();

      expect(cubit.state.isEmpty, isTrue);
      expect(cubit.state.mode, ConstellationTagFilterMode.or);
    });

    test('a no-op does not emit', () async {
      final emitted = <ConstellationTagFilter>[];
      final sub = cubit.stream.listen(emitted.add);

      cubit
        ..clear()
        ..setMode(ConstellationTagFilterMode.or);
      await Future<void>.delayed(Duration.zero);
      await sub.cancel();

      expect(emitted, isEmpty);
    });

    testWidgets('maybeConstellationTagLens finds the provided cubit', (
      tester,
    ) async {
      ConstellationTagLensCubit? found;
      ConstellationTagLensCubit? missing;
      await tester.pumpWidget(
        Builder(
          builder: (outer) {
            missing = maybeConstellationTagLens(outer);
            return BlocProvider.value(
              value: cubit,
              child: Builder(
                builder: (inner) {
                  found = maybeConstellationTagLens(inner);
                  return const SizedBox();
                },
              ),
            );
          },
        ),
      );

      expect(found, same(cubit));
      expect(missing, isNull);
    });
  });

  group('the tag filter is not field state', () {
    late ConstellationTagLensCubit cubit;

    setUp(() => cubit = ConstellationTagLensCubit());
    tearDown(() => cubit.close());

    test('toggling tags emits nothing from the field cubit', () async {
      final field = await loadReferenceCubit();
      addTearDown(field.close);
      final before = field.state;
      final emitted = <Object>[];
      final sub = field.stream.listen(emitted.add);
      addTearDown(sub.cancel);

      cubit
        ..toggleOwn('T1')
        ..toggleAuto(ConstellationAutoTagKind.iTrust)
        ..setMode(ConstellationTagFilterMode.and);
      await Future<void>.delayed(Duration.zero);

      expect(cubit.state.isEmpty, isFalse);
      expect(emitted, isEmpty);
      expect(field.state, same(before));
    });

    test("the lens cubit asks an injected lookup for a person's own tags", () {
      final lens = ConstellationTagLensCubit(
        ownTagIdsOf: (id) => id == 'ann' ? {'T1'} : const {},
      );
      addTearDown(lens.close);

      expect(lens.ownTagIdsOf('ann'), {'T1'});
      expect(lens.ownTagIdsOf('bob'), isEmpty);
    });
  });
}
