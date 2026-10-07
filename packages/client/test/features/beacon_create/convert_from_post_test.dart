// Converting a Post to a Request opens the Request form first, prefilled from
// the Post's root message. Nothing is written until the author submits: the
// form calls `beaconConvertToRequest` once, then (if the author kept the root
// photo) sets the cover with the ordinary cover upload. A cover failure never
// undoes the conversion, and closing the form sends nothing to the server.

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/app/router/root_router.dart';
import 'package:tentura/consts.dart';
import 'package:tentura/domain/entity/image_entity.dart';
import 'package:tentura/domain/port/post_conversion_port.dart';
import 'package:tentura/domain/use_case/post_conversion_case.dart';
import 'package:tentura/features/beacon_create/ui/bloc/beacon_create_cubit.dart';
import 'package:tentura/ui/effect/ui_effect.dart';

import '../../ui/effect/fake_ui_effect_port.dart';
import 'fake_beacon_ports.dart';

const _postId = 'post-1';

final _rootPhoto = ImageEntity(
  localKey: 'root-photo',
  fileName: 'photo.jpg',
  imageBytes: Uint8List.fromList(kTinyPng),
);

/// One `beaconConvertToRequest` call, as the port received it.
class _ConvertCall {
  const _ConvertCall({
    required this.beaconId,
    required this.title,
    required this.description,
    required this.needs,
    required this.primaryNeedSlug,
    required this.startAt,
    required this.endAt,
    required this.isDiscoverable,
    required this.stagedImagesAtCall,
  });

  final String beaconId;
  final String title;
  final String description;
  final Set<String> needs;
  final String? primaryNeedSlug;
  final DateTime? startAt;
  final DateTime? endAt;
  final bool isDiscoverable;

  /// How many images had been uploaded when the call arrived.
  final int stagedImagesAtCall;
}

class _FakePostConversionPort implements PostConversionPort {
  _FakePostConversionPort(this._write);

  final FakeBeaconWritePort _write;

  PostRootContent root = const PostRootContent(body: '');
  Object? fetchError;
  Object? convertError;

  final fetchedIds = <String>[];
  final convertCalls = <_ConvertCall>[];

  @override
  Future<PostRootContent> fetchRootContent(String beaconId) async {
    fetchedIds.add(beaconId);
    if (fetchError != null) throw fetchError!;
    return root;
  }

  @override
  Future<void> convertToRequest({
    required String beaconId,
    required String title,
    required String description,
    required Set<String> needs,
    required String? primaryNeedSlug,
    required DateTime? startAt,
    required DateTime? endAt,
    required bool isDiscoverable,
    List<String> helperIds = const [],
  }) async {
    convertCalls.add(
      _ConvertCall(
        beaconId: beaconId,
        title: title,
        description: description,
        needs: needs,
        primaryNeedSlug: primaryNeedSlug,
        startAt: startAt,
        endAt: endAt,
        isDiscoverable: isDiscoverable,
        stagedImagesAtCall: _write.stagedKeys.length,
      ),
    );
    if (convertError != null) throw convertError!;
  }
}

void main() {
  late FakeBeaconWritePort write;
  late _FakePostConversionPort conversion;
  late FakeUiEffectPort effects;
  late BeaconCreateCubit cubit;

  setUp(() {
    write = FakeBeaconWritePort();
    conversion = _FakePostConversionPort(write);
    effects = FakeUiEffectPort();
    cubit = BeaconCreateCubit(
      beaconCreateCase: fakeBeaconCreateCase(write: write),
      postConversionCase: PostConversionCase(conversion),
      effects: effects,
    );
    addTearDown(cubit.close);
  });

  Future<void> openForm(String body, {ImageEntity? photo}) async {
    conversion.root = PostRootContent(body: body, firstImage: photo);
    await cubit.loadConvertFromPost(_postId);
  }

  Iterable<String> openedPaths() =>
      effects.emitted.whereType<NavigatePush>().map((e) => e.path);

  void expectNothingWritten() {
    expect(openedPaths(), isEmpty);
    expect(write.createdFields, isEmpty);
    expect(write.updatedDraftFields, isEmpty);
    expect(write.updatedFields, isEmpty);
    expect(write.stagedKeys, isEmpty);
    expect(write.setMediaCalls, isEmpty);
    expect(conversion.convertCalls, isEmpty);
  }

  group('prefill from the root message', () {
    test('first line becomes the title and the rest the description', () async {
      await openForm('Need a ladder\nI can pick it up on Saturday.');

      expect(conversion.fetchedIds, [_postId]);
      expect(cubit.state.title, 'Need a ladder');
      expect(cubit.state.description, 'I can pick it up on Saturday.');
      expect(cubit.state.meetsPublishFormRequirements, isTrue);
      expect(cubit.state.canTryToPublish, isTrue);
    });

    test('a single short line is the title and leaves no description', () async {
      await openForm('Need a ladder');

      expect(cubit.state.title, 'Need a ladder');
      expect(cubit.state.description, isEmpty);
    });

    test('a first line over the title limit is cut to the limit', () async {
      final firstLine = 'x' * (kBeaconTitleMaxLength + 20);

      await openForm(firstLine);

      expect(
        cubit.state.title,
        firstLine.substring(0, kBeaconTitleMaxLength),
      );
      expect(cubit.state.title, hasLength(kBeaconTitleMaxLength));
    });

    test(
      'a long first line is cut to the title limit and the following lines '
      'become the description',
      () async {
        final firstLine = 'y' * (kBeaconTitleMaxLength + 20);

        await openForm('$firstLine\nSecond line\nThird line');

        expect(
          cubit.state.title,
          firstLine.substring(0, kBeaconTitleMaxLength),
        );
        expect(cubit.state.description, 'Second line\nThird line');
      },
    );

    test('the first image of the root message is the cover suggestion', () async {
      await openForm('Need a ladder\nSaturday', photo: _rootPhoto);

      expect(cubit.state.images.map((i) => i.key), ['root-photo']);
      expect(cubit.state.coverKey, 'root-photo');
    });

    test('a root message without a photo suggests no cover', () async {
      await openForm('Need a ladder\nSaturday');

      expect(cubit.state.images, isEmpty);
      expect(cubit.state.coverKey, isNull);
    });

    test('a photo-only root leaves the title empty with its error shown', () async {
      await openForm('', photo: _rootPhoto);

      expect(cubit.state.title, isEmpty);
      expect(cubit.state.description, isEmpty);
      expect(cubit.state.images, hasLength(1));
      expect(cubit.state.publishBlocker, BeaconPublishBlocker.title);
      expect(cubit.state.canTryToPublish, isFalse);
      expect(cubit.state.showValidationHints, isTrue);
    });

    test('an unreadable root reports the error and prefills nothing', () async {
      conversion.fetchError = Exception('root unavailable');

      await cubit.loadConvertFromPost(_postId);

      expect(cubit.state.title, isEmpty);
      expect(effects.emitted.whereType<ShowError>(), hasLength(1));
      expectNothingWritten();
    });
  });

  group('submit', () {
    test('sends exactly one convert call carrying the form content', () async {
      await openForm('Need a ladder\nSaturday');
      cubit
        ..setTitle('Need a tall ladder')
        ..setDescription('Saturday morning, two flights up.')
        ..setNeeds({'transport'})
        ..setDeadline(DateTime.utc(2027, 1, 5))
        ..setDiscoverable(false);

      final opened = await cubit.submitConversion();

      expect(opened, _postId);
      expect(conversion.convertCalls, hasLength(1));
      final call = conversion.convertCalls.single;
      expect(call.beaconId, _postId);
      expect(call.title, 'Need a tall ladder');
      expect(call.description, 'Saturday morning, two flights up.');
      expect(call.needs, {'transport'});
      expect(call.primaryNeedSlug, cubit.state.primaryNeedSlug);
      expect(call.primaryNeedSlug, isNotNull);
      expect(call.startAt, isNull);
      expect(call.endAt, DateTime.utc(2027, 1, 5));
      expect(call.isDiscoverable, isFalse);
      expect(openedPaths(), ['$kPathBeaconView/$_postId']);
    });

    test('a Request is discoverable unless the dialog said otherwise', () async {
      await openForm('Need a ladder\nSaturday');

      await cubit.submitConversion();

      expect(conversion.convertCalls.single.isDiscoverable, isTrue);
    });

    test('the discoverability chosen in the dialog reaches the convert call', () async {
      conversion.root = const PostRootContent(body: 'Need a ladder\nSaturday');
      await cubit.loadConvertFromPost(_postId, isDiscoverable: false);

      expect(cubit.state.isDiscoverable, isFalse);

      await cubit.submitConversion();

      expect(conversion.convertCalls.single.isDiscoverable, isFalse);
    });

    test('a discoverable choice in the dialog reaches the convert call', () async {
      conversion.root = const PostRootContent(body: 'Need a ladder\nSaturday');
      await cubit.loadConvertFromPost(_postId, isDiscoverable: true);

      await cubit.submitConversion();

      expect(conversion.convertCalls.single.isDiscoverable, isTrue);
    });

    test('a second submit while one is in flight does not convert twice', () async {
      await openForm('Need a ladder\nSaturday');

      final results = await Future.wait([
        cubit.submitConversion(),
        cubit.submitConversion(),
      ]);

      expect(conversion.convertCalls, hasLength(1));
      expect(results, contains(_postId));
    });

    test('never creates or saves a draft', () async {
      await openForm('Need a ladder\nSaturday', photo: _rootPhoto);

      await cubit.submitConversion();

      expect(write.createdFields, isEmpty);
      expect(write.updatedDraftFields, isEmpty);
      expect(write.updatedFields, isEmpty);
      expect(write.publishedIds, isEmpty);
    });

    test('an invalid form sends nothing', () async {
      await openForm('', photo: _rootPhoto);

      final opened = await cubit.submitConversion();

      expect(opened, isNull);
      expectNothingWritten();
    });

    test('a failed conversion reports the error and uploads no cover', () async {
      await openForm('Need a ladder\nSaturday', photo: _rootPhoto);
      conversion.convertError = Exception('not allowed');

      final opened = await cubit.submitConversion();

      expect(opened, isNull);
      expect(conversion.convertCalls, hasLength(1));
      expect(effects.emitted.whereType<ShowError>(), hasLength(1));
      expect(write.stagedKeys, isEmpty);
      expect(write.setMediaCalls, isEmpty);
      expect(openedPaths(), isEmpty);
    });
  });

  group('cover after conversion', () {
    test('a kept photo is uploaded as the cover once the Post is a Request', () async {
      await openForm('Need a ladder\nSaturday', photo: _rootPhoto);

      final opened = await cubit.submitConversion();

      expect(opened, _postId);
      expect(conversion.convertCalls.single.stagedImagesAtCall, 0);
      expect(write.stagedKeys, ['root-photo']);
      expect(write.setMediaCalls, hasLength(1));
      final media = write.setMediaCalls.single;
      expect(media.beaconId, _postId);
      expect(media.imageIds, ['staged-0']);
      expect(media.coverImageId, 'staged-0');
      expect(openedPaths(), ['$kPathBeaconView/$_postId']);
    });

    test('a removed photo uploads nothing', () async {
      await openForm('Need a ladder\nSaturday', photo: _rootPhoto);
      cubit.removeImage(0);

      final opened = await cubit.submitConversion();

      expect(opened, _postId);
      expect(conversion.convertCalls, hasLength(1));
      expect(write.stagedKeys, isEmpty);
      expect(write.setMediaCalls, isEmpty);
      expect(openedPaths(), ['$kPathBeaconView/$_postId']);
    });

    test('a cover upload failure still opens the converted Request', () async {
      await openForm('Need a ladder\nSaturday', photo: _rootPhoto);
      write.failStageAtCall = 0;

      final opened = await cubit.submitConversion();

      expect(opened, _postId);
      expect(conversion.convertCalls, hasLength(1));
      expect(write.stagedKeys, ['root-photo']);
      expect(write.setMediaCalls, isEmpty);
      expect(effects.emitted.whereType<ShowError>(), hasLength(1));
      expect(openedPaths(), ['$kPathBeaconView/$_postId']);
    });
  });

  group('cancel', () {
    test('closing the prefilled form sends nothing to the server', () async {
      await openForm('Need a ladder\nSaturday', photo: _rootPhoto);

      await cubit.close();

      expectNothingWritten();
    });

    test('editing the prefilled form never autosaves a draft', () async {
      await openForm('Need a ladder\nSaturday', photo: _rootPhoto);
      cubit
        ..setTitle('Need a taller ladder')
        ..setDescription('Saturday morning.');

      await cubit.flushAutosave();
      await cubit.close();

      expectNothingWritten();
    });
  });

  group('route', () {
    test('the Request form route carries the Post to convert', () {
      expect(BeaconCreateRoute().args!.convertFromPostId, isEmpty);
      expect(
        BeaconCreateRoute(convertFromPostId: _postId).args!.convertFromPostId,
        _postId,
      );
    });

    test('the Request form route carries the dialog discoverability', () {
      expect(BeaconCreateRoute().args!.convertIsDiscoverable, isTrue);
      expect(
        BeaconCreateRoute(
          convertFromPostId: _postId,
          convertIsDiscoverable: false,
        ).args!.convertIsDiscoverable,
        isFalse,
      );
    });
  });
}
