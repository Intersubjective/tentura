// Real app and local stack, launched by run_client_integration_web_local.sh.
// The OS file chooser is deterministic; the composer, upload, persistence,
// router, repositories and cold app bootstrap are production code. The
// companion Playwright test additionally proves a new browser document.
import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:image_picker/image_picker.dart' show XFile;
import 'package:integration_test/integration_test.dart';
import 'package:web/web.dart' as web;

import 'package:tentura/consts.dart';
import 'package:tentura/features/beacon_create/ui/bloc/beacon_create_cubit.dart';
import 'package:tentura/features/beacon_create/ui/screen/post_create_screen.dart';
import 'package:tentura/features/settings/ui/bloc/settings_cubit.dart';
import 'package:tentura/main.dart' as app;
import 'package:tentura/ui/widget/pending_attachments.dart';

import 'support/e2e_test_helpers.dart';

const _body = 'Черновик поста сохраняет текст, файл, пересылку и срок жизни.';
const _fileName = 'notes.txt';

Future<void> _reveal(WidgetTester tester, Finder finder) async {
  if (finder.evaluate().isEmpty) {
    await tester.scrollUntilVisible(
      finder,
      150,
      scrollable: find.byType(Scrollable).first,
      maxScrolls: 12,
    );
  }
  await Scrollable.ensureVisible(tester.element(finder), alignment: 0.5);
  await pumpBounded(tester, frames: 3);
}

Future<Map<String, Object?>> _visibleDraft(WidgetTester tester) async {
  final field = find.byKey(PostCreateScreen.textFieldKey);
  if (field.evaluate().isEmpty) {
    await tester.scrollUntilVisible(
      field,
      -150,
      scrollable: find.byType(Scrollable).first,
      maxScrolls: 12,
    );
  }
  final body = tester.widget<TextField>(field).controller!.text;
  final picker = find.byType(SegmentedButton<int>);
  await _reveal(tester, picker);
  final previews = tester
      .widgetList<PendingAttachmentPreview>(
        find.byType(PendingAttachmentPreview),
      )
      .toList();
  final lifetime = tester.widget<SegmentedButton<int>>(picker).selected;
  final toggle = find.byType(SwitchListTile);
  await _reveal(tester, toggle);
  return {
    'body': body,
    'files': [for (final preview in previews) preview.upload.fileName],
    'canForward': tester.widget<SwitchListTile>(toggle).value,
    'lifetime': lifetime,
  };
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'reopening a Post draft URL restores body file closed forwarding and 24 hours',
    (tester) async {
      await launchApp(app.main);
      await pumpSettleBounded(tester);
      final fixture = await bootstrapFixture(
        runId: uniqueRunId('post-composer-reload'),
      );
      await loginAs(tester, fixture.authorEmail);
      await GetIt.I<SettingsCubit>().setLocalePreference(kLocalePreferenceRu);
      await pumpBounded(tester);
      await goToPath(tester, kPathPostNew);
      final field = find.byKey(PostCreateScreen.textFieldKey);
      await pumpUntilVisible(tester, field);
      await tester.tap(field);
      await tester.enterText(field, _body);
      await tester.pump();

      final previousPicker = FilePickerPlatform.instance;
      FilePickerPlatform.instance = _Files();
      addTearDown(() => FilePickerPlatform.instance = previousPicker);
      final attach = find.byIcon(Icons.attach_file_rounded);
      await _reveal(tester, attach);
      await tester.tap(attach);
      await pumpUntil(
        tester,
        () => find.byType(PendingAttachmentPreview).evaluate().length == 1,
        label: 'the selected document appears in the existing attachment strip',
      );
      final lifetime = find.text('24 часа');
      await _reveal(tester, lifetime);
      await tester.tap(lifetime);
      await tester.pump();
      final toggle = find.byType(SwitchListTile);
      await _reveal(tester, toggle);
      await tester.tap(
        find.descendant(of: toggle, matching: find.byType(Switch)),
      );
      await tester.pump();
      const expected = {
        'body': _body,
        'files': [_fileName],
        'canForward': false,
        'lifetime': {24},
      };
      expect(
        await _visibleDraft(tester),
        expected,
        reason:
            'the author entered all four values before leaving the document',
      );

      final cubit = tester
          .element(find.byType(PostCreateScreen))
          .read<BeaconCreateCubit>();
      await pumpUntil(
        tester,
        () => cubit.state.draftId?.isNotEmpty ?? false,
        timeout: const Duration(seconds: 30),
        label: 'server Post draft id',
      );
      final draftId = cubit.state.draftId!;
      // The last setting uses the same 1.5 second autosave as text. Keep this
      // settle bounded instead of waiting indefinitely for a missing mutation.
      await Future<void>.delayed(
        const Duration(milliseconds: 1700),
      ).timeout(const Duration(milliseconds: 2000));
      await tester.pump();

      // Follow the integration suite's cold-bootstrap pattern: dispose the old
      // tree and dependency graph and read draft_id as the initial route. No
      // old cubit or pendingUploads list is reused. Playwright covers F5 itself.
      final path = '$kPathPostNew?$kQueryBeaconDraftId=$draftId';
      await tester.pumpWidget(const SizedBox.shrink());
      await pumpBounded(tester, frames: 8);
      web.window.history.replaceState(null, '', path);
      final dispatcher = tester.binding.platformDispatcher
        ..defaultRouteNameTestValue = path;
      addTearDown(dispatcher.clearDefaultRouteNameTestValue);
      await launchApp(app.main);
      await pumpUntilVisible(tester, find.byType(PostCreateScreen));
      await pumpUntil(
        tester,
        () {
          final restored = tester
              .element(find.byType(PostCreateScreen))
              .read<BeaconCreateCubit>();
          return restored.state.draftId == draftId && !restored.state.isLoading;
        },
        timeout: const Duration(seconds: 30),
        label: 'server draft loaded after bootstrap',
      );
      expect(
        web.window.location.href,
        contains('$kQueryBeaconDraftId=$draftId'),
      );
      expect(
        await _visibleDraft(tester),
        expected,
        reason:
            'cold draft_id bootstrap must restore body, PendingAttachmentPreview, closed forwarding and 24 hours',
      );
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );
}

class _Files extends FilePickerPlatform {
  @override
  Future<List<PlatformFile>> pickFiles({
    String? dialogTitle,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    void Function(FilePickerStatus)? onFileLoading,
    int compressionQuality = 0,
    AndroidOptions androidOptions = const AndroidOptions(),
    WindowsOptions windowsOptions = const WindowsOptions(),
    LinuxOptions linuxOptions = const LinuxOptions(),
    WebOptions webOptions = const WebOptions(),
  }) async => [_Document()];
}

final class _Document extends PlatformFile {
  @override
  String get name => _fileName;
  @override
  Uri get uri => Uri.dataFromString('draft attachment');
  @override
  XFile get xFile => XFile.fromData(
    Uint8List.fromList(utf8.encode('draft attachment')),
    name: name,
  );
  @override
  Future<int> length() async => 16;
  @override
  Future<Uint8List> readAsBytes() async =>
      Uint8List.fromList(utf8.encode('draft attachment'));
  @override
  Stream<Uint8List> readAsByteStream() => Stream.fromFuture(readAsBytes());
}
