part of '_migrations.dart';

final m0007 = Migration(
  '0007',
  [
    // Tables
    //
    '''
DROP TABLE IF EXISTS public.message;
''',
    '''
ALTER TABLE IF EXISTS public.user_vsids SET LOGGED;
''',
    //
    '''
CREATE UNLOGGED TABLE IF NOT EXISTS public.user_presence (
  user_id text NOT NULL,
  last_seen_at timestamp with time zone DEFAULT now() NOT NULL,
  last_notified_at timestamp with time zone DEFAULT now() NOT NULL,
  status smallint DEFAULT 0 NOT NULL,
  PRIMARY KEY (user_id),
  CONSTRAINT user_presence_user_id_fkey FOREIGN KEY (user_id)
    REFERENCES public."user"(id) ON UPDATE RESTRICT ON DELETE CASCADE
);
''',
    //
    '''
CREATE TABLE IF NOT EXISTS public.p2p_message (
  client_id uuid NOT NULL,
  server_id uuid NOT NULL,
  sender_id text NOT NULL,
  receiver_id text NOT NULL,
  content text NOT NULL,
  created_at timestamp with time zone NOT NULL,
  delivered_at timestamp with time zone,
  PRIMARY KEY (client_id, server_id),
  CONSTRAINT p2p_message_sender_id_fkey FOREIGN KEY (sender_id)
    REFERENCES public."user"(id) ON UPDATE RESTRICT ON DELETE CASCADE,
  CONSTRAINT p2p_message_receiver_id_fkey FOREIGN KEY (receiver_id)
    REFERENCES public."user"(id) ON UPDATE RESTRICT ON DELETE CASCADE
);
''',
    '''
CREATE TABLE IF NOT EXISTS public.fcm_token (
  user_id text NOT NULL,
  app_id uuid NOT NULL,
  token text NOT NULL,
  platform text NOT NULL,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  PRIMARY KEY (user_id, app_id),
  CONSTRAINT fcm_token_user_id_fkey FOREIGN KEY (user_id)
    REFERENCES public."user"(id) ON UPDATE RESTRICT ON DELETE CASCADE
);
''',
    // Data
    '''
INSERT INTO public.user_presence (user_id)
  SELECT id FROM public."user" ON CONFLICT (user_id) DO NOTHING;
''',
    // Function
    r'''
CREATE OR REPLACE FUNCTION public.on_user_created()
  RETURNS trigger
  LANGUAGE plpgsql
  AS $$
BEGIN
  INSERT INTO user_vsids VALUES (NEW.id, DEFAULT, DEFAULT);
  INSERT INTO user_presence (user_id) VALUES (NEW.id);
  RETURN NEW;
END;
$$;
''',
  ],
);
