-- Optional cloud sync for Stash. Run once in the Supabase SQL editor.
-- Rows mirror the app's local SQLite tables; timestamps are client epoch
-- milliseconds and deletes are tombstones (deleted = true).

create table if not exists public.folders (
  user_id uuid not null default auth.uid() references auth.users on delete cascade,
  id text not null,
  name text not null,
  emoji text not null default '📁',
  color integer not null default 0,
  sort_order integer not null default 0,
  created_at bigint not null,
  updated_at bigint not null,
  deleted boolean not null default false,
  server_updated_at timestamptz not null default now(),
  primary key (user_id, id)
);

create table if not exists public.posts (
  user_id uuid not null default auth.uid() references auth.users on delete cascade,
  id text not null,
  url text not null,
  source_url text not null,
  platform text not null,
  author text,
  author_name text,
  caption text,
  thumbnail_url text,
  note text,
  ai_description text,
  folder_id text not null,
  created_at bigint not null,
  updated_at bigint not null,
  deleted boolean not null default false,
  server_updated_at timestamptz not null default now(),
  primary key (user_id, id)
);

-- For projects created before AI descriptions existed.
alter table public.posts add column if not exists ai_description text;

create index if not exists folders_sync on public.folders (user_id, server_updated_at);
create index if not exists posts_sync on public.posts (user_id, server_updated_at);

-- Devices pull "everything changed since my cursor", so the cursor column
-- must be stamped by the server, never by a device clock.
create or replace function public.touch_server_updated_at() returns trigger
language plpgsql as $$
begin
  new.server_updated_at := now();
  return new;
end $$;

drop trigger if exists folders_touch on public.folders;
create trigger folders_touch before insert or update on public.folders
  for each row execute function public.touch_server_updated_at();

drop trigger if exists posts_touch on public.posts;
create trigger posts_touch before insert or update on public.posts
  for each row execute function public.touch_server_updated_at();

alter table public.folders enable row level security;
alter table public.posts enable row level security;

drop policy if exists "own folders" on public.folders;
create policy "own folders" on public.folders for all
  using (auth.uid() = user_id) with check (auth.uid() = user_id);

drop policy if exists "own posts" on public.posts;
create policy "own posts" on public.posts for all
  using (auth.uid() = user_id) with check (auth.uid() = user_id);
