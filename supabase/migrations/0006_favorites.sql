-- ChordPlane: per-account favorites for community songs.
-- Local favorites stay on the device; this table mirrors them for signed-in
-- accounts so they survive reinstalls and follow the account across devices.

create table if not exists public.song_favorites (
  user_id uuid not null references auth.users (id) on delete cascade,
  song_id uuid not null references public.community_songs (id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (user_id, song_id)
);

create index if not exists song_favorites_song_idx
  on public.song_favorites (song_id);

alter table public.song_favorites enable row level security;

drop policy if exists "favorites self read" on public.song_favorites;
create policy "favorites self read" on public.song_favorites
  for select using ((select auth.uid()) = user_id);

drop policy if exists "favorites self insert" on public.song_favorites;
create policy "favorites self insert" on public.song_favorites
  for insert with check ((select auth.uid()) = user_id);

drop policy if exists "favorites self delete" on public.song_favorites;
create policy "favorites self delete" on public.song_favorites
  for delete using ((select auth.uid()) = user_id);

grant select, insert, delete on public.song_favorites to authenticated;

notify pgrst, 'reload schema';
