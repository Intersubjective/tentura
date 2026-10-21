import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tentura_root/domain/entity/beacon_cover_source.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';

import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/image_entity.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/domain/exception/generic_exception.dart';
import 'package:tentura/domain/use_case/beacon_create_case.dart';
import 'package:tentura/features/beacon_create/ui/bloc/beacon_create_cubit.dart';
import 'package:tentura/features/beacon_create/ui/message/beacon_create_message.dart';
import 'package:tentura/ui/effect/ui_effect.dart';
import 'package:tentura/ui/l10n/l10n_en.dart';
import 'package:tentura/ui/l10n/l10n_ru.dart';

import '../../ui/effect/fake_ui_effect_port.dart';
import 'fake_beacon_ports.dart';

/// Issue #510 (B080): Edit request › Save changes. BeaconUpdate saves the
/// fields, then BeaconSetMedia is turned away with the server admission
/// backoff (1704 "retry later", mapped to [RemoteApiRetryLaterException]).
/// The saved edit must not read as a failed save: the media call is retried
/// after the server hint, a success says "Changes saved", and a media call
/// that still fails says the changes were saved but the photos were not.

const _i1 = ImageEntity(id: 'i1', authorId: 'author-1');
const _i2 = ImageEntity(id: 'i2', authorId: 'author-1');

/// An open request with two uploaded photos, the first one as cover.
Beacon _serverBeacon() => Beacon.empty.copyWith(
  id: 'b-edit',
  status: BeaconStatus.open,
  title: 'Move a sofa',
  description: 'Third floor, no lift.',
  author: const Profile(id: 'author-1'),
  images: const [_i1, _i2],
  coverImageId: 'i1',
  coverSource: BeaconCoverSource.photo,
);

/// Edit command that moves the cover to the second, already uploaded photo:
/// the media really changed, so BeaconSetMedia must run.
BeaconSaveCommand _coverChange() => BeaconSaveCommand(
  fields: _serverBeacon().copyWith(title: 'Move a sofa today'),
  images: const [_i1, _i2],
  coverKey: 'i2',
);

/// Longest wait the client may spend on one server retryAfter hint before
/// re-sending BeaconSetMedia. The implementation must cap at or below this.
/// Owner review on #633: the interactive Save path caps at 2 s.
const _maxRetryWait = Duration(seconds: 2);

/// Edit command that adds a freshly picked local photo (bytes held, no server
/// id yet) and makes it the cover.
BeaconSaveCommand _addLocalPhoto() => BeaconSaveCommand(
  fields: _serverBeacon().copyWith(title: 'Move a sofa today'),
  images: [
    _i1,
    _i2,
    ImageEntity(
      localKey: 'fresh',
      fileName: 'fresh.jpg',
      imageBytes: Uint8List.fromList([1, 2, 3]),
    ),
  ],
  coverKey: 'fresh',
);

/// BeaconSetMedia answers "busy, retry later" while [busy] is set.
class _BusyMediaWritePort extends FakeBeaconWritePort {
  _BusyMediaWritePort({super.beacon});

  final Duration hint = const Duration(milliseconds: 1);
  bool busy = true;
  int setMediaAttempts = 0;

  @override
  Future<Beacon> setMedia({
    required String beaconId,
    required List<String> imageIds,
    required String? coverImageId,
    required String? coverThumbImageId,
    required BeaconCoverSource coverSource,
  }) async {
    setMediaAttempts++;
    if (busy) throw RemoteApiRetryLaterException(hint);
    return super.setMedia(
      beaconId: beaconId,
      imageIds: imageIds,
      coverImageId: coverImageId,
      coverThumbImageId: coverThumbImageId,
      coverSource: coverSource,
    );
  }
}

void main() {
  group('#510 use case: BeaconSetMedia busy after the edit saved', () {
    test(
      'a busy BeaconSetMedia is retried after the server hint and the edit '
      'succeeds',
      () {
        fakeAsync((async) {
          final write = FakeBeaconWritePort(beacon: _serverBeacon())
            ..failSetMediaAtCall = 0
            ..setMediaError = const RemoteApiRetryLaterException(
              Duration(milliseconds: 60),
            );
          final sut = BeaconCreateCase(write, FakeBeaconImagePort());

          BeaconSaveResult? result;
          unawaited(sut.saveEdit(_coverChange()).then((r) => result = r));

          async
            ..elapse(const Duration(milliseconds: 59))
            ..flushMicrotasks();
          expect(
            write.setMediaCalls,
            hasLength(1),
            reason: 'the retry waits for the server retryAfterMs hint',
          );
          expect(result, isNull);

          async
            ..elapse(const Duration(milliseconds: 1))
            ..flushMicrotasks();
          expect(result, isNotNull);
          expect(write.updatedFields, hasLength(1));
          expect(write.setMediaCalls, hasLength(2));
          expect(write.setMediaCalls.last.imageIds, ['i1', 'i2']);
          expect(write.setMediaCalls.last.coverImageId, 'i2');
          expect(write.stagedKeys, isEmpty, reason: 'nothing to re-stage');
          expect(result!.beacon.coverImageId, 'i2');
        });
      },
    );

    test(
      'a busy BeaconSetMedia after adding a fresh photo re-sends the same '
      'payload and does not upload the photo again',
      () async {
        final write = FakeBeaconWritePort(beacon: _serverBeacon())
          ..failSetMediaAtCall = 0
          ..setMediaError = const RemoteApiRetryLaterException(
            Duration(milliseconds: 1),
          );
        final sut = BeaconCreateCase(write, FakeBeaconImagePort());

        final result = await sut.saveEdit(_addLocalPhoto());

        expect(write.updatedFields, hasLength(1));
        expect(
          write.stagedKeys,
          ['fresh'],
          reason: 'busy is not an expired stage: the photo uploads once',
        );
        expect(write.setMediaCalls, hasLength(2));
        final first = write.setMediaCalls.first;
        final second = write.setMediaCalls.last;
        expect(first.imageIds, ['i1', 'i2', 'staged-0']);
        expect(second.imageIds, first.imageIds);
        expect(first.coverImageId, 'staged-0');
        expect(second.coverImageId, first.coverImageId);
        expect(second.coverThumbImageId, first.coverThumbImageId);
        expect(second.coverSource, first.coverSource);
        expect(result.beacon.coverImageId, 'staged-0');
        expect(result.images.last.id, 'staged-0');
      },
    );

    test(
      'a huge server retryAfter hint is capped (at most $_maxRetryWait)',
      () {
        fakeAsync((async) {
          final write = FakeBeaconWritePort(beacon: _serverBeacon())
            ..failSetMediaAtCall = 0
            ..setMediaError = const RemoteApiRetryLaterException(
              Duration(minutes: 10),
            );
          final sut = BeaconCreateCase(write, FakeBeaconImagePort());

          BeaconSaveResult? result;
          Object? error;
          unawaited(
            sut
                .saveEdit(_coverChange())
                .then<void>(
                  (r) {
                    result = r;
                  },
                  onError: (Object e) {
                    error = e;
                  },
                ),
          );

          async
            ..elapse(_maxRetryWait)
            ..flushMicrotasks();

          expect(error, isNull);
          expect(
            result,
            isNotNull,
            reason: 'the retry must not wait the full 10 min hint',
          );
          expect(write.setMediaCalls, hasLength(2));
          expect(result!.beacon.coverImageId, 'i2');
        });
      },
    );

    test(
      'a BeaconSetMedia that stays busy is retried a bounded number of times',
      () async {
        final write = _BusyMediaWritePort(beacon: _serverBeacon());
        final sut = BeaconCreateCase(write, FakeBeaconImagePort());

        await expectLater(
          sut.saveEdit(_coverChange()),
          throwsA(
            isA<BeaconSaveFailure>()
                .having((e) => e.phase, 'phase', BeaconSavePhase.reconcile)
                .having(
                  (e) => e.cause,
                  'cause',
                  isA<RemoteApiRetryLaterException>(),
                ),
          ),
        );
        expect(write.updatedFields, hasLength(1));
        expect(write.setMediaAttempts, inInclusiveRange(2, 3));
      },
    );

    test(
      'guard: a BeaconSetMedia failure that is not busy is not retried',
      () async {
        final write = FakeBeaconWritePort(beacon: _serverBeacon())
          ..failSetMediaAtCall = 0
          ..setMediaError = Exception('image not found');
        final sut = BeaconCreateCase(write, FakeBeaconImagePort());

        await expectLater(
          sut.saveEdit(_coverChange()),
          throwsA(
            isA<BeaconSaveFailure>().having(
              (e) => e.phase,
              'phase',
              BeaconSavePhase.reconcile,
            ),
          ),
        );
        expect(write.setMediaCalls, hasLength(1));
      },
    );
  });

  group('#510 cubit: Save changes feedback', () {
    late FakeUiEffectPort effects;

    Future<BeaconCreateCubit> openEditor(FakeBeaconWritePort write) async {
      effects = FakeUiEffectPort();
      final cubit = BeaconCreateCubit(
        beaconCreateCase: fakeBeaconCreateCase(write: write),
        effects: effects,
      );
      await cubit.loadEdit('b-edit');
      expect(cubit.state.isEditMode, isTrue);
      effects.clear();
      return cubit;
    }

    Iterable<Object> messages() =>
        effects.emitted.whereType<ShowMessage>().map((e) => e.message);

    test('Save changes says Changes saved and closes the editor', () async {
      final write = FakeBeaconWritePort(beacon: _serverBeacon());
      final cubit = await openEditor(write);
      addTearDown(cubit.close);

      cubit.setTitle('Move a sofa today');
      await cubit.saveEdit(context: 'c');

      expect(write.updatedFields.single.title, 'Move a sofa today');
      expect(
        write.setMediaCalls,
        isEmpty,
        reason: 'a title-only edit sends no BeaconSetMedia (#515)',
      );
      expect(effects.emitted.whereType<ShowError>(), isEmpty);
      expect(effects.emitted.whereType<NavigateBack>(), hasLength(1));
      expect(messages(), contains(isA<BeaconChangesSavedMessage>()));
      expect(
        messages(),
        isNot(contains(isA<BeaconPhotosNotUpdatedMessage>())),
      );
    });

    test(
      'a cover change saved after one busy answer still closes with '
      'Changes saved',
      () async {
        final write = FakeBeaconWritePort(beacon: _serverBeacon())
          ..failSetMediaAtCall = 0
          ..setMediaError = const RemoteApiRetryLaterException(
            Duration(milliseconds: 1),
          );
        final cubit = await openEditor(write);
        addTearDown(cubit.close);

        cubit.setCoverImageKey('i2');
        await cubit.saveEdit(context: 'c');

        expect(effects.emitted.whereType<ShowError>(), isEmpty);
        expect(effects.emitted.whereType<NavigateBack>(), hasLength(1));
        expect(messages(), contains(isA<BeaconChangesSavedMessage>()));
        expect(write.beacon.coverImageId, 'i2');
      },
    );

    test(
      'photos that stay busy after the fields saved do not read as a failed '
      'save, and Save changes again finishes the job',
      () async {
        final write = _BusyMediaWritePort(beacon: _serverBeacon());
        final cubit = await openEditor(write);
        addTearDown(cubit.close);

        cubit
          ..setTitle('Move a sofa today')
          ..setCoverImageKey('i2');
        await cubit.saveEdit(context: 'c');

        // The fields are saved on the server.
        expect(write.beacon.title, 'Move a sofa today');
        // No raw "busy" error bar as if nothing was saved.
        expect(effects.emitted.whereType<ShowError>(), isEmpty);
        expect(messages(), contains(isA<BeaconPhotosNotUpdatedMessage>()));
        expect(messages(), isNot(contains(isA<BeaconChangesSavedMessage>())));
        // The editor stays open with the chosen cover, so nothing the author
        // picked is dropped and Save changes can send it again.
        expect(effects.emitted.whereType<NavigateBack>(), isEmpty);
        expect(cubit.state.coverKey, 'i2');
        expect(cubit.state.isLoading, isFalse);

        write.busy = false;
        effects.clear();
        await cubit.saveEdit(context: 'c');

        expect(write.beacon.coverImageId, 'i2');
        expect(effects.emitted.whereType<ShowError>(), isEmpty);
        expect(effects.emitted.whereType<NavigateBack>(), hasLength(1));
        expect(messages(), contains(isA<BeaconChangesSavedMessage>()));
      },
    );

    test(
      'guard: a failed field save still shows the error and stays open',
      () async {
        final write = FakeBeaconWritePort(beacon: _serverBeacon())
          ..updateError = Exception('Request is closed');
        final cubit = await openEditor(write);
        addTearDown(cubit.close);

        cubit.setTitle('Move a sofa today');
        await cubit.saveEdit(context: 'c');

        expect(effects.emitted.whereType<ShowError>(), hasLength(1));
        expect(effects.emitted.whereType<NavigateBack>(), isEmpty);
        expect(messages(), isNot(contains(isA<BeaconChangesSavedMessage>())));
        expect(
          messages(),
          isNot(contains(isA<BeaconPhotosNotUpdatedMessage>())),
        );
      },
    );

    test('Changes saved and photos-not-updated read in both languages', () {
      const saved = BeaconChangesSavedMessage();
      const photos = BeaconPhotosNotUpdatedMessage();
      expect(saved.toEn, 'Changes saved');
      expect(saved.toRu, 'Изменения сохранены');
      expect(photos.toEn, contains('photos were not updated'));
      expect(photos.toRu, contains('фото не обновились'));
      // Owner review on #633: name the button by its own label.
      expect(
        photos.toEn,
        contains('“${L10nEn().buttonSaveChanges}”'),
      );
      expect(
        photos.toRu,
        contains('«${L10nRu().buttonSaveChanges}»'),
      );
      for (final text in [photos.toEn, photos.toRu]) {
        expect(text.toLowerCase(), isNot(contains('constellation')));
        expect(text.toLowerCase(), isNot(contains('database')));
      }
    });
  });
}
