part of '_migrations.dart';

/// Cover card thumbnail: separate cropped image id (not in beacon_image gallery).
final m0132 = Migration('0132', [
  r'''
ALTER TABLE public.beacon
  ADD COLUMN cover_thumb_image_id UUID NULL
    REFERENCES public.image(id) ON DELETE SET NULL;
''',
]);
