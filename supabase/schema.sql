-- Sphere360 schema. Run in the Supabase SQL editor.
-- gen_random_uuid() is provided by pgcrypto, which Supabase enables by default.

create extension if not exists "uuid-ossp";

create table sessions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid() references auth.users,
  title text,
  started_at timestamptz default now(),
  completed_at timestamptz,
  status text not null default 'capturing' check (status in ('capturing','complete')),
  device_model text,
  latitude double precision, -- null unless the user turns location on
  longitude double precision,
  preview_path text,
  thumb_path text
);

create table captures (
  id uuid primary key default gen_random_uuid(),
  session_id uuid not null references sessions on delete cascade,
  user_id uuid not null default auth.uid() references auth.users,
  storage_path text not null,
  yaw real not null, pitch real not null, roll real,
  fov real, width int, height int,
  captured_at timestamptz default now()
);

create table if not exists hotspots (
  id uuid primary key default gen_random_uuid(),
  session_id uuid not null references sessions on delete cascade,
  user_id uuid not null default auth.uid() references auth.users,
  yaw real not null,
  pitch real not null,
  label text not null,
  created_at timestamptz default now()
);

create index on captures (session_id);
create index on sessions (user_id, started_at desc);
create index if not exists hotspots_session_id_idx on hotspots (session_id);

alter table sessions enable row level security;
alter table captures enable row level security;
alter table hotspots enable row level security;
drop policy if exists "own hotspots" on hotspots;
create policy "own sessions" on sessions for all
  to authenticated
  using (user_id = auth.uid())
  with check (user_id = auth.uid());
create policy "own captures" on captures for all
  to authenticated
  using (user_id = auth.uid())
  with check (user_id = auth.uid());
create policy "own hotspots" on hotspots for all
  to authenticated
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

-- Tables created in the SQL editor are not exposed to signed-in users until
-- these grants exist. Row level security still limits each user to their rows.
grant select, insert, update, delete on table public.sessions to authenticated;
grant select, insert, update, delete on table public.captures to authenticated;
grant select, insert, update, delete on table public.hotspots to authenticated;

-- Private bucket "panoramas".
-- Object path: {user_id}/{session_id}/{capture_id}.jpg
-- plus preview.jpg and thumb.jpg in the same session folder.
insert into storage.buckets (id, name, public)
values ('panoramas', 'panoramas', false)
on conflict (id) do update set public = excluded.public;

drop policy if exists "own panoramas select" on storage.objects;
drop policy if exists "own panoramas insert" on storage.objects;
drop policy if exists "own panoramas update" on storage.objects;
drop policy if exists "own panoramas delete" on storage.objects;

create policy "own panoramas select"
on storage.objects for select
to authenticated
using (
  bucket_id = 'panoramas'
  and (storage.foldername(name))[1] = auth.uid()::text
);

create policy "own panoramas insert"
on storage.objects for insert
to authenticated
with check (
  bucket_id = 'panoramas'
  and (storage.foldername(name))[1] = auth.uid()::text
);

create policy "own panoramas update"
on storage.objects for update
to authenticated
using (
  bucket_id = 'panoramas'
  and (storage.foldername(name))[1] = auth.uid()::text
)
with check (
  bucket_id = 'panoramas'
  and (storage.foldername(name))[1] = auth.uid()::text
);

create policy "own panoramas delete"
on storage.objects for delete
to authenticated
using (
  bucket_id = 'panoramas'
  and (storage.foldername(name))[1] = auth.uid()::text
);
