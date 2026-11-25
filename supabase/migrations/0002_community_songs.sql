-- ChordPlane: community song library, usernames and rating eligibility.
-- Run in the Supabase SQL editor or via `supabase db push` after 0001.

-- ---------------------------------------------------------------------------
-- Profiles: a unique, case-insensitive username chosen at sign-up.
-- ---------------------------------------------------------------------------
alter table public.profiles
  add column if not exists username text,
  add column if not exists username_changed_at timestamptz;

-- Keep usernames readable by everyone so community uploads can be credited.
-- The table holds no email address or other private data.
drop policy if exists "public reads usernames" on public.profiles;
create policy "public reads usernames" on public.profiles
  for select using (true);

-- (Re)create the sign-up hook so both email and native Google accounts get a
-- profile row. The username comes from auth metadata set by the app.
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.profiles (id, display_name, username)
  values (
    new.id,
    nullif(trim(coalesce(new.raw_user_meta_data->>'display_name', '')), ''),
    nullif(lower(trim(coalesce(new.raw_user_meta_data->>'username', ''))), '')
  )
  on conflict (id) do nothing;
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- Profiles created before the trigger existed still need a row.
insert into public.profiles (id, display_name)
select id, nullif(split_part(coalesce(email, ''), '@', 1), '')
from auth.users
on conflict (id) do nothing;

-- Uniqueness is case-insensitive; null usernames are allowed while an older
-- account is being prompted to choose one.
create unique index if not exists profiles_username_unique
  on public.profiles (lower(username))
  where username is not null;

drop function if exists public.check_username_available(text);
create function public.check_username_available(candidate text)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  cleaned text := lower(trim(coalesce(candidate, '')));
begin
  if cleaned !~ '^[a-z0-9_]{3,20}$' then
    return jsonb_build_object(
      'available', false,
      'reason', 'Use 3–20 letters, numbers or underscores.'
    );
  end if;
  if exists (
    select 1 from public.profiles
    where lower(username) = cleaned and id <> auth.uid()
  ) then
    return jsonb_build_object(
      'available', false,
      'reason', 'That username is taken.'
    );
  end if;
  return jsonb_build_object('available', true, 'reason', '');
end;
$$;

grant execute on function public.check_username_available(text) to anon, authenticated;

-- A signed-in user may change their own username. Credits are read from the
-- profile, so past uploads follow the new name.
create or replace function public.set_username(candidate text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  checked jsonb := public.check_username_available(candidate);
  cleaned text := lower(trim(candidate));
begin
  if auth.uid() is null then
    return jsonb_build_object('ok', false, 'reason', 'Sign in first.');
  end if;
  if (checked->>'available') <> 'true' then
    return jsonb_build_object('ok', false, 'reason', checked->>'reason');
  end if;
  update public.profiles
     set username = cleaned,
         username_changed_at = now()
   where id = auth.uid();
  if not found then
    -- Very old accounts may not have a profile row yet.
    insert into public.profiles (id, username, username_changed_at)
    values (auth.uid(), cleaned, now())
    on conflict (id) do update
      set username = excluded.username,
          username_changed_at = excluded.username_changed_at;
  end if;
  return jsonb_build_object('ok', true, 'username', cleaned);
end;
$$;

grant execute on function public.set_username(text) to authenticated;

-- Shared validator for song links. Keep in step with
-- lib/core/validation/youtube_link.dart in the app.
create or replace function public.is_allowed_youtube_link(value text)
returns boolean
language sql
immutable
as $$
  select coalesce(value, '') = ''
      or value ~* '^https?://(www\.)?(youtube\.com|youtu\.be)(/|$)'
      or value ~* '^https?://(m|music)\.youtube\.com(/|$)';
$$;

grant execute on function public.is_allowed_youtube_link(text) to anon, authenticated;

-- ---------------------------------------------------------------------------
-- Rating eligibility: signed in, account at least 3 days old, one active day.
-- ---------------------------------------------------------------------------
create table if not exists public.user_activity_days (
  user_id uuid not null references auth.users (id) on delete cascade,
  day date not null default (now() at time zone 'utc')::date,
  primary key (user_id, day)
);

alter table public.user_activity_days enable row level security;

drop policy if exists "activity days self" on public.user_activity_days;
create policy "activity days self" on public.user_activity_days
  for all using (auth.uid() = user_id) with check (auth.uid() = user_id);

create or replace function public.record_active_day()
returns void
language sql
security definer
set search_path = public
as $$
  insert into public.user_activity_days (user_id)
  values (auth.uid())
  on conflict do nothing;
$$;

grant execute on function public.record_active_day() to authenticated;

create or replace function public.can_rate_songs()
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  uid uuid := auth.uid();
  account_age integer := 0;
  active_days integer := 0;
  reasons jsonb := '[]'::jsonb;
begin
  if uid is null then
    return jsonb_build_object(
      'allowed', false,
      'reasons', jsonb_build_array('Sign in to rate songs.')
    );
  end if;

  select greatest(0, floor(extract(epoch from (now() - created_at)) / 86400)::integer)
    into account_age
  from auth.users
  where id = uid;

  select count(*) into active_days
  from public.user_activity_days
  where user_id = uid;

  if account_age < 3 then
    reasons := reasons || jsonb_build_array(
      'Your account needs to be 3 days old (' || account_age || '/3).'
    );
  end if;
  if active_days < 1 then
    reasons := reasons || jsonb_build_array(
      'Use the app at least once before rating.'
    );
  end if;

  return jsonb_build_object(
    'allowed', jsonb_array_length(reasons) = 0,
    'reasons', reasons,
    'accountAgeDays', account_age,
    'activeDays', active_days
  );
end;
$$;

grant execute on function public.can_rate_songs() to anon, authenticated;

-- ---------------------------------------------------------------------------
-- Community songs. `owner` stays server-side even on anonymous uploads.
-- ---------------------------------------------------------------------------
create table if not exists public.community_songs (
  id uuid primary key default gen_random_uuid(),
  owner uuid not null references auth.users (id) on delete cascade,
  title text not null,
  artist text not null default '',
  body text not null,
  original_key text not null default '',
  chord_detection_mode text not null default 'auto',
  capo integer not null default 0,
  tempo integer,
  instrument text not null default 'guitar',
  tuning text not null default 'standard',
  youtube_url text not null default '',
  tags text not null default '',
  anonymous boolean not null default false,
  moderation_status text not null default 'published'
    check (moderation_status in ('published', 'pending', 'removed')),
  rating_sum integer not null default 0,
  rating_count integer not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- A named relation to profiles makes `profiles(username)` an unambiguous
-- PostgREST embed even though both tables also reference auth.users.
alter table public.community_songs
  drop constraint if exists community_songs_owner_profile_fkey;
alter table public.community_songs
  add constraint community_songs_owner_profile_fkey
  foreign key (owner) references public.profiles (id) on delete cascade;

create index if not exists community_songs_created_idx
  on public.community_songs (created_at desc)
  where moderation_status = 'published';
create index if not exists community_songs_owner_idx
  on public.community_songs (owner);
create index if not exists community_songs_search_idx
  on public.community_songs using gin (
    to_tsvector('simple', title || ' ' || artist || ' ' || tags)
  );

-- Artist is mandatory for new songs. Old rows are backfilled so the
-- constraint can be added without breaking an existing catalog.
update public.community_songs
   set artist = 'Unknown artist'
 where btrim(artist) = '';

alter table public.community_songs
  drop constraint if exists community_songs_artist_required;
alter table public.community_songs
  add constraint community_songs_artist_required
  check (btrim(artist) <> '');

alter table public.community_songs
  drop constraint if exists community_songs_youtube_link_valid;
alter table public.community_songs
  add constraint community_songs_youtube_link_valid
  check (public.is_allowed_youtube_link(youtube_url));

alter table public.community_songs enable row level security;

drop policy if exists "community songs public read" on public.community_songs;
create policy "community songs public read" on public.community_songs
  for select using (moderation_status = 'published');

drop policy if exists "community songs owner manages" on public.community_songs;
create policy "community songs owner manages" on public.community_songs
  for all using (auth.uid() = owner) with check (auth.uid() = owner);

grant select on public.community_songs to anon, authenticated;
grant insert, update, delete on public.community_songs to authenticated;
-- Clients may edit the song content, never server-owned counters or identity.
revoke update on public.community_songs from authenticated;
grant update (
  title, artist, body, original_key, chord_detection_mode, capo, tempo,
  instrument, tuning, youtube_url, tags, anonymous
) on public.community_songs to authenticated;

-- The remaining server-owned columns may not be changed by clients.
create or replace function public.guard_community_song()
returns trigger
language plpgsql
as $$
begin
  if new.owner <> old.owner or new.created_at <> old.created_at then
    raise exception 'This column is managed by ChordPlane.';
  end if;
  return new;
end;
$$;

drop trigger if exists community_songs_guard on public.community_songs;
create trigger community_songs_guard
  before update on public.community_songs
  for each row execute function public.guard_community_song();

drop trigger if exists community_songs_touch on public.community_songs;
create trigger community_songs_touch
  before update on public.community_songs
  for each row execute function public.touch_updated_at();

-- ---------------------------------------------------------------------------
-- Ratings: one 1–5 accuracy score per user per song, gated in the database.
-- ---------------------------------------------------------------------------
create table if not exists public.song_ratings (
  id uuid primary key default gen_random_uuid(),
  song_id uuid not null references public.community_songs (id) on delete cascade,
  user_id uuid not null references auth.users (id) on delete cascade,
  score integer not null check (score between 1 and 5),
  comment text not null default '',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (song_id, user_id)
);

create index if not exists song_ratings_song_idx on public.song_ratings (song_id);

alter table public.song_ratings enable row level security;

drop policy if exists "ratings self read" on public.song_ratings;
create policy "ratings self read" on public.song_ratings
  for select using (auth.uid() = user_id);

drop policy if exists "eligible users rate" on public.song_ratings;
create policy "eligible users rate" on public.song_ratings
  for insert with check (
    auth.uid() = user_id
    and (public.can_rate_songs()->>'allowed') = 'true'
  );

drop policy if exists "rating owners update" on public.song_ratings;
create policy "rating owners update" on public.song_ratings
  for update using (auth.uid() = user_id)
  with check (
    auth.uid() = user_id
    and (public.can_rate_songs()->>'allowed') = 'true'
  );

drop policy if exists "rating owners delete" on public.song_ratings;
create policy "rating owners delete" on public.song_ratings
  for delete using (auth.uid() = user_id);

grant select, insert, update, delete on public.song_ratings to authenticated;

create or replace function public.refresh_song_rating(song uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  update public.community_songs
     set rating_sum = coalesce((
           select sum(score) from public.song_ratings where song_id = song
         ), 0),
         rating_count = (
           select count(*) from public.song_ratings where song_id = song
         )
   where id = song;
end;
$$;

create or replace function public.apply_rating_change()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  perform public.refresh_song_rating(coalesce(new.song_id, old.song_id));
  return null;
end;
$$;

drop trigger if exists song_ratings_changed on public.song_ratings;
create trigger song_ratings_changed
  after insert or update or delete on public.song_ratings
  for each row execute function public.apply_rating_change();

-- Make the new tables, columns and RPCs visible to PostgREST immediately.
notify pgrst, 'reload schema';
