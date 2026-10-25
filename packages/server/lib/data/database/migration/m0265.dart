part of '_migrations.dart';

/// Saved Field layouts (people tags C1): `constellation_layout_snapshot`.
///
/// `kind` 0 is the viewer's single favourite, 1 the rolling history (newest 20,
/// trimmed by the writer). `anchors` is the viewer's live layout as
/// `{targetKind, targetId, x, y, coordinateSpaceVersion}` objects. A snapshot
/// is private to its viewer and reachable only through the V2 API, so Hasura
/// never tracks the table.
final m0265 = Migration('0265', [
  r'''
CREATE TABLE public.constellation_layout_snapshot (
    id text NOT NULL,
    viewer_id text NOT NULL,
    kind smallint NOT NULL,
    reason smallint NOT NULL,
    anchors jsonb NOT NULL,
    anchor_count integer NOT NULL,
    client_op_id text,
    created_at timestamp with time zone DEFAULT clock_timestamp() NOT NULL,
    CONSTRAINT constellation_layout_snapshot_pkey PRIMARY KEY (id),
    CONSTRAINT constellation_layout_snapshot_kind_ck CHECK (kind IN (0, 1)),
    CONSTRAINT constellation_layout_snapshot_viewer_id_fkey FOREIGN KEY (viewer_id) REFERENCES public."user"(id) ON DELETE CASCADE
)
''',
  '''
CREATE UNIQUE INDEX constellation_layout_snapshot_favourite_uq ON public.constellation_layout_snapshot USING btree (viewer_id) WHERE (kind = 0)
''',
  '''
CREATE UNIQUE INDEX constellation_layout_snapshot_op_uq ON public.constellation_layout_snapshot USING btree (viewer_id, client_op_id) WHERE (client_op_id IS NOT NULL)
''',
  '''
CREATE INDEX constellation_layout_snapshot_viewer_created_idx ON public.constellation_layout_snapshot USING btree (viewer_id, created_at DESC)
''',
]);
