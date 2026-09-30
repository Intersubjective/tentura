-- fixture: shipped migration path may mention trust_rebuild_effective_edge
CREATE FUNCTION public.trust_rebuild_effective_edge() RETURNS void LANGUAGE sql AS $$ SELECT 1 $$;
