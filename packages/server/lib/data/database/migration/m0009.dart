part of '_migrations.dart';

final m0009 = Migration(
  '0009',
  [
    // Tables
    '''
CREATE TABLE IF NOT EXISTS public.complaint (
  id text NOT NULL,
  user_id text NOT NULL,
  email text NOT NULL,
  details text NOT NULL,
  type smallint NOT NULL,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  CONSTRAINT complaint_pkey PRIMARY KEY (id, user_id),
  CONSTRAINT complaint_user_id_fkey FOREIGN KEY (user_id)
    REFERENCES public."user"(id) ON UPDATE RESTRICT ON DELETE CASCADE
);
''',
  ],
);
