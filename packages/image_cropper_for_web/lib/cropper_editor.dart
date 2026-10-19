/// Web-import-free cropper chrome (no `dart:js_interop` / `package:web`), so
/// apps can build [CropperWebTranslations] and VM tests can pump the editor.
library;

export 'src/cropper_editor_scaffold.dart' show CropperEditorScaffold;
export 'src/cropper_translations.dart';
