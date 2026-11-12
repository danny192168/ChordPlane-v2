-- ChordPlane: server-backed setlist/song sharing (S1).
-- Run in the Supabase SQL editor or via `supabase db push`.

-- One row per auth user; display_name is optional for now and used by the
-- future "shared by" credit and the public library.
create table if not exists public.profiles (
  id uuid primary key references auth.users (id) on delete cascade,
  display_name text,
  created_at timestamptz not null default now()
);

-- Each share is a frozen .cpl snapshot; the token IS the secret. Anonymous
-- read access is granted by knowing the token (unguessable nanoid).
create table if not exists public.shared_bundles (
  token text primary key,
  kind text not null check (kind in ('setlist', 'song')),
  title text not null default '',
  format text not null default 'chordplane.cpl/1',
  snapshot jsonb not null,
  status text not null default 'active'
    check (status in ('active', 'under_review', 'removed')),
  revoked boolean not null default false,
  view_count integer not null default 0,
  owner uuid not null references auth.users (id) on delete cascade,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists shared_bundles_owner_idx
  on public.shared_bundles (owner);
create index if not exists shared_bundles_status_idx
  on public.shared_bundles (status) where status = 'active';

alter table public.profiles enable row level security;
alter table public.shared_bundles enable row level security;

-- Profiles: a user reads and updates only their own row.
drop policy if exists "profiles self" on public.profiles;
create policy "profiles self" on public.profiles
  for all using (auth.uid() = id) with check (auth.uid() = id);

-- Shares: owners manage their own rows (any status).
drop policy if exists "owners manage own shares" on public.shared_bundles;
create policy "owners manage own shares" on public.shared_bundles
  for all using (auth.uid() = owner) with check (auth.uid() = owner);

-- Everyone (including anon) may read shares that are live. Revoked and
-- moderated rows stay hidden; the token remains required to find anything.
drop policy if exists "anyone reads active shares" on public.shared_bundles;
create policy "anyone reads active shares" on public.shared_bundles
  for select using (status = 'active' and revoked = false);

-- Keep updated_at fresh on snapshot updates.
create or replace function public.touch_updated_at()
returns trigger language plpgsql as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists shared_bundles_touch on public.shared_bundles;
create trigger shared_bundles_touch
  before update on public.shared_bundles
  for each row execute function public.touch_updated_at();
