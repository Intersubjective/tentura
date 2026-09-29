part of '_migrations.dart';

/// A6: closure schema (Arch §5.4) — nine `beacon_closure*` tables (raw SQL
/// only, no Drift classes, like the m0202 trust ledger), the legacy
/// review-window data step, and the removal of the six review-era tables.
///
/// Inventory (step 1 of the unit): every object on the review tables lives in
/// the squashed baseline `m0193`; no migration m0194–m0202 touches them, and
/// no trigger, function or view references them. Dropped here (with their
/// constraints, which `DROP TABLE` takes along):
/// - tables `beacon_evaluation` (pkey `beacon_evaluation_pkey`; fkeys
///   `beacon_evaluation_beacon_id_fkey`, `beacon_evaluation_evaluated_user_id_fkey`,
///   `beacon_evaluation_evaluator_id_fkey`; column comment on `status`),
///   `beacon_evaluation_ack_tag` (pkey; fkeys `..._beacon_id_fkey`,
///   `..._evaluator_id_fkey`, `..._subject_id_fkey`),
///   `beacon_evaluation_participant` (pkey; fkeys `..._beacon_id_fkey`,
///   `..._user_id_fkey`),
///   `beacon_evaluation_visibility` (pkey; fkeys `..._beacon_id_fkey`,
///   `..._evaluator_id_fkey`, `..._participant_id_fkey`),
///   `beacon_review_status` (pkey; fkeys `..._beacon_id_fkey`,
///   `..._user_id_fkey`),
///   `beacon_review_window` (pkey; fkey `..._beacon_id_fkey`; partial index
///   `beacon_review_window_closes_at_idx`).
/// - rewritten: check constraint `notification_outbox__recipient_safe_chk`
///   (m0193) — the presentation-key allowlist keeps `room_member_removed`,
///   `offer_declined`, `offer_removed` and adds `closure_opened_bookmark_only`,
///   `closure_finalized`, `closure_cancelled`; column comment on
///   `beacon_room_message.system_message_kind` (adds kind 3 = closure story;
///   there is no kind allowlist constraint).
///
/// Dart callers that still read the dropped tables (evaluation/attention
/// repositories, mappers, Drift table classes) are removed or stubbed by the
/// later unit A18; until then they fail at runtime if exercised.
final m0203 = Migration('0203', [
  // Step 2 (legacy data): retire live review obligations of legacy
  // reviewOpen beacons exactly the way reopen does
  // (`AttentionSystemSettlementRepository.supersedeReviewObligationsOnReopen`),
  // while status = 5 still marks them. No evidence rows are minted.
  r'''
UPDATE public.notification_outbox AS outbox
SET
  settlement_kind = 'superseded',
  settled_at = now(),
  settled_by_user_id = NULL,
  settled_by_occurrence_id = NULL
FROM public.attention_occurrence AS occ
WHERE outbox.occurrence_id = occ.id
  AND occ.event_type = 'reviewOpened'
  AND outbox.requires_action
  AND outbox.settlement_kind IS NULL
  AND outbox.beacon_id IN (SELECT id FROM public.beacon WHERE status = 5)
''',
  r'''
UPDATE public.beacon SET status = 7 WHERE status = 5
''',

  // Step 3: the nine closure tables (Arch §5.4).
  r'''
CREATE TABLE public.beacon_closure (
    beacon_id text NOT NULL,
    epoch integer NOT NULL,
    status smallint NOT NULL,
    opened_at timestamp with time zone NOT NULL,
    closes_at timestamp with time zone NOT NULL,
    extensions_used smallint DEFAULT 0 NOT NULL,
    finalized_at timestamp with time zone,
    finalize_reason smallint,
    settlement_version integer,
    settlement_params jsonb,
    CONSTRAINT beacon_closure_pkey PRIMARY KEY (beacon_id, epoch),
    CONSTRAINT beacon_closure_beacon_id_fkey FOREIGN KEY (beacon_id) REFERENCES public.beacon(id) ON DELETE CASCADE,
    CONSTRAINT beacon_closure_epoch_check CHECK ((epoch >= 1)),
    CONSTRAINT beacon_closure_status_check CHECK ((status = ANY (ARRAY[0, 1, 2]))),
    CONSTRAINT beacon_closure_extensions_used_check CHECK ((extensions_used >= 0 AND extensions_used <= 2)),
    CONSTRAINT beacon_closure_finalize_reason_check CHECK ((finalize_reason = ANY (ARRAY[1, 2])))
)
''',
  r'''
CREATE UNIQUE INDEX beacon_closure_one_live ON public.beacon_closure USING btree (beacon_id) WHERE (status = ANY (ARRAY[0, 1]))
''',
  r'''
CREATE INDEX beacon_closure_due ON public.beacon_closure USING btree (closes_at) WHERE (status = 0)
''',
  r'''
CREATE TABLE public.beacon_closure_member (
    beacon_id text NOT NULL,
    epoch integer NOT NULL,
    user_id text NOT NULL,
    arrival_edge_id text,
    departure smallint,
    active_at_open boolean NOT NULL,
    CONSTRAINT beacon_closure_member_pkey PRIMARY KEY (beacon_id, epoch, user_id),
    CONSTRAINT beacon_closure_member_closure_fkey FOREIGN KEY (beacon_id, epoch) REFERENCES public.beacon_closure(beacon_id, epoch) ON DELETE CASCADE,
    CONSTRAINT beacon_closure_member_user_id_fkey FOREIGN KEY (user_id) REFERENCES public."user"(id) ON DELETE CASCADE,
    CONSTRAINT beacon_closure_member_arrival_edge_id_fkey FOREIGN KEY (arrival_edge_id) REFERENCES public.beacon_forward_edge(id) ON DELETE SET NULL,
    CONSTRAINT beacon_closure_member_departure_check CHECK ((departure = ANY (ARRAY[1, 2])))
)
''',
  r'''
CREATE INDEX beacon_closure_member_user_id ON public.beacon_closure_member USING btree (user_id)
''',
  r'''
CREATE TABLE public.beacon_closure_outcome (
    beacon_id text NOT NULL,
    helper_id text NOT NULL,
    outcome smallint,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT beacon_closure_outcome_pkey PRIMARY KEY (beacon_id, helper_id),
    CONSTRAINT beacon_closure_outcome_beacon_id_fkey FOREIGN KEY (beacon_id) REFERENCES public.beacon(id) ON DELETE CASCADE,
    CONSTRAINT beacon_closure_outcome_helper_id_fkey FOREIGN KEY (helper_id) REFERENCES public."user"(id) ON DELETE CASCADE,
    CONSTRAINT beacon_closure_outcome_outcome_check CHECK ((outcome = ANY (ARRAY[1, 2, 3])))
)
''',
  r'''
CREATE TABLE public.beacon_closure_author_split (
    beacon_id text NOT NULL,
    helper_id text NOT NULL,
    pct smallint NOT NULL,
    CONSTRAINT beacon_closure_author_split_pkey PRIMARY KEY (beacon_id, helper_id),
    CONSTRAINT beacon_closure_author_split_beacon_id_fkey FOREIGN KEY (beacon_id) REFERENCES public.beacon(id) ON DELETE CASCADE,
    CONSTRAINT beacon_closure_author_split_helper_id_fkey FOREIGN KEY (helper_id) REFERENCES public."user"(id) ON DELETE CASCADE,
    CONSTRAINT beacon_closure_author_split_pct_check CHECK ((pct >= 0 AND pct <= 100 AND pct % 5 = 0))
)
''',
  r'''
CREATE TABLE public.beacon_closure_support (
    beacon_id text NOT NULL,
    voter_id text NOT NULL,
    target_id text NOT NULL,
    version smallint NOT NULL,
    pressed_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT beacon_closure_support_pkey PRIMARY KEY (beacon_id, voter_id, target_id, version),
    CONSTRAINT beacon_closure_support_beacon_id_fkey FOREIGN KEY (beacon_id) REFERENCES public.beacon(id) ON DELETE CASCADE,
    CONSTRAINT beacon_closure_support_voter_id_fkey FOREIGN KEY (voter_id) REFERENCES public."user"(id) ON DELETE CASCADE,
    CONSTRAINT beacon_closure_support_target_id_fkey FOREIGN KEY (target_id) REFERENCES public."user"(id) ON DELETE CASCADE,
    CONSTRAINT beacon_closure_support_version_check CHECK ((version = ANY (ARRAY[0, 1]))),
    CONSTRAINT beacon_closure_support_no_self_check CHECK ((voter_id <> target_id))
)
''',
  r'''
CREATE INDEX beacon_closure_support_beacon_version ON public.beacon_closure_support USING btree (beacon_id, version)
''',
  r'''
CREATE TABLE public.beacon_closure_commit (
    beacon_id text NOT NULL,
    voter_id text NOT NULL,
    committed_at timestamp with time zone NOT NULL,
    CONSTRAINT beacon_closure_commit_pkey PRIMARY KEY (beacon_id, voter_id),
    CONSTRAINT beacon_closure_commit_beacon_id_fkey FOREIGN KEY (beacon_id) REFERENCES public.beacon(id) ON DELETE CASCADE,
    CONSTRAINT beacon_closure_commit_voter_id_fkey FOREIGN KEY (voter_id) REFERENCES public."user"(id) ON DELETE CASCADE
)
''',
  r'''
CREATE TABLE public.beacon_closure_mark (
    beacon_id text NOT NULL,
    marker_id text NOT NULL,
    target_id text NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT beacon_closure_mark_pkey PRIMARY KEY (beacon_id, marker_id, target_id),
    CONSTRAINT beacon_closure_mark_beacon_id_fkey FOREIGN KEY (beacon_id) REFERENCES public.beacon(id) ON DELETE CASCADE,
    CONSTRAINT beacon_closure_mark_marker_id_fkey FOREIGN KEY (marker_id) REFERENCES public."user"(id) ON DELETE CASCADE,
    CONSTRAINT beacon_closure_mark_target_id_fkey FOREIGN KEY (target_id) REFERENCES public."user"(id) ON DELETE CASCADE,
    CONSTRAINT beacon_closure_mark_no_self_check CHECK ((marker_id <> target_id))
)
''',
  r'''
CREATE INDEX beacon_closure_mark_target_id ON public.beacon_closure_mark USING btree (target_id)
''',
  r'''
CREATE TABLE public.beacon_closure_story (
    beacon_id text NOT NULL,
    body text NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT beacon_closure_story_pkey PRIMARY KEY (beacon_id),
    CONSTRAINT beacon_closure_story_beacon_id_fkey FOREIGN KEY (beacon_id) REFERENCES public.beacon(id) ON DELETE CASCADE,
    CONSTRAINT beacon_closure_story_body_check CHECK ((length(body) <= 2000))
)
''',
  r'''
CREATE TABLE public.beacon_closure_result (
    beacon_id text NOT NULL,
    epoch integer NOT NULL,
    user_id text NOT NULL,
    outcome smallint NOT NULL,
    band smallint NOT NULL,
    draft_flag smallint DEFAULT 0 NOT NULL,
    helped double precision NOT NULL,
    CONSTRAINT beacon_closure_result_pkey PRIMARY KEY (beacon_id, epoch, user_id),
    CONSTRAINT beacon_closure_result_closure_fkey FOREIGN KEY (beacon_id, epoch) REFERENCES public.beacon_closure(beacon_id, epoch) ON DELETE CASCADE,
    CONSTRAINT beacon_closure_result_user_id_fkey FOREIGN KEY (user_id) REFERENCES public."user"(id) ON DELETE CASCADE,
    CONSTRAINT beacon_closure_result_outcome_check CHECK ((outcome = ANY (ARRAY[1, 2, 3]))),
    CONSTRAINT beacon_closure_result_band_check CHECK ((band = ANY (ARRAY[0, 1, 2, 3]))),
    CONSTRAINT beacon_closure_result_draft_flag_check CHECK ((draft_flag = ANY (ARRAY[0, 1, 2])))
)
''',

  // Step 4: drop the six review-era tables (constraints and the
  // `beacon_review_window_closes_at_idx` index go with them).
  r'''
DROP TABLE public.beacon_evaluation_ack_tag
''',
  r'''
DROP TABLE public.beacon_evaluation_visibility
''',
  r'''
DROP TABLE public.beacon_evaluation_participant
''',
  r'''
DROP TABLE public.beacon_evaluation
''',
  r'''
DROP TABLE public.beacon_review_status
''',
  r'''
DROP TABLE public.beacon_review_window
''',

  // Step 5: extend the recipient_safe presentation-key allowlist for closure
  // notifications, preserving the existing keys.
  r'''
ALTER TABLE public.notification_outbox
    DROP CONSTRAINT notification_outbox__recipient_safe_chk,
    ADD CONSTRAINT notification_outbox__recipient_safe_chk CHECK (((access_policy <> 'recipient_safe'::text) OR ((presentation_key IS NOT NULL) AND (presentation_key = ANY (ARRAY['room_member_removed'::text, 'offer_declined'::text, 'offer_removed'::text, 'closure_opened_bookmark_only'::text, 'closure_finalized'::text, 'closure_cancelled'::text])))))
''',

  // Step 6: room system kind 3 = closure story (comment only; there is no
  // kind allowlist constraint).
  r'''
COMMENT ON COLUMN public.beacon_room_message.system_message_kind IS 'NULL for ordinary user messages; non-null marks system-authored notices (1=hierarchy lifecycle, 2=child created, 3=closure story).'
''',
]);
