part of '_migrations.dart';

/// Idempotency op log and per-target revision watermark for constellation
/// anchor batches (#235 U10).
///
/// Sizes are enforced by the schema: `client_op_id` is varchar(64), the
/// fingerprint is exactly a 32-byte digest and the stored result is capped.
/// `jsonb::text` renders one space after each `:` and `,`, so the cap is
/// checked against that form with one byte of slack over the 256-byte compact
/// payload. Neither table has a secondary index. The watermark is keyed by
/// target, not anchor id, so it survives anchor deletion.
final m0228 = Migration('0228', [
  r'''
CREATE TABLE public.constellation_anchor_op_log (
    viewer_id text NOT NULL,
    client_op_id character varying(64) NOT NULL,
    fingerprint bytea NOT NULL,
    result jsonb NOT NULL,
    revision bigint NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT constellation_anchor_op_log_pkey PRIMARY KEY (viewer_id, client_op_id),
    CONSTRAINT constellation_anchor_op_log_viewer_id_fkey FOREIGN KEY (viewer_id) REFERENCES public."user"(id) ON DELETE CASCADE,
    CONSTRAINT constellation_anchor_op_log__fingerprint_chk CHECK (octet_length(fingerprint) = 32),
    CONSTRAINT constellation_anchor_op_log__result_chk CHECK (octet_length(result::text) <= 257)
)
''',

  r'''
CREATE TABLE public.constellation_anchor_target_watermark (
    viewer_id text NOT NULL,
    target_kind text NOT NULL,
    target_id text NOT NULL,
    revision bigint NOT NULL,
    CONSTRAINT constellation_anchor_target_watermark_pkey PRIMARY KEY (viewer_id, target_kind, target_id),
    CONSTRAINT constellation_anchor_target_watermark_viewer_id_fkey FOREIGN KEY (viewer_id) REFERENCES public."user"(id) ON DELETE CASCADE
)
''',
]);
