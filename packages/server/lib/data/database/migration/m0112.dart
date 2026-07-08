part of '_migrations.dart';

/// Backfill legacy `need_summary` and `success_criteria` into `description`,
/// then drop the two columns.
///
/// Format (only when source text is non-empty):
/// - "\n\nWhat is needed:\n<need_summary>"
/// - "\n\nDefinition of done:\n<success_criteria>"
///
/// Must respect the DB constraint: `char_length(description) <= 2048`.
final m0112 = Migration('0112', [
  r'''
WITH src AS (
  SELECT
    id,
    COALESCE(description, '') AS description,
    NULLIF(trim(need_summary), '') AS need_summary,
    NULLIF(trim(success_criteria), '') AS success_criteria
  FROM public.beacon
),
payload AS (
  SELECT
    id,
    description AS base,
    concat(
      CASE
        WHEN need_summary IS NULL THEN ''
        ELSE E'\n\nWhat is needed:\n' || need_summary
      END,
      CASE
        WHEN success_criteria IS NULL THEN ''
        ELSE E'\n\nDefinition of done:\n' || success_criteria
      END
    ) AS extra
  FROM src
),
trimmed AS (
  SELECT
    id,
    base,
    extra,
    greatest(0, 2048 - char_length(base)) AS remaining
  FROM payload
)
UPDATE public.beacon b
SET description = t.base || substring(t.extra FROM 1 FOR t.remaining)
FROM trimmed t
WHERE b.id = t.id
  AND t.extra <> ''
  AND b.description = t.base;
''',
  r'''
ALTER TABLE public.beacon
  DROP COLUMN IF EXISTS need_summary;
''',
  r'''
ALTER TABLE public.beacon
  DROP COLUMN IF EXISTS success_criteria;
''',
]);

