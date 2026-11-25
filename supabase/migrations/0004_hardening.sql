-- ChordPlane: hardening pass after the first community/live migrations.
-- Safe to re-run. Keeps fresh installs and already-migrated projects aligned.

-- Pin search paths on every function that touches tables or is used by a
-- constraint. This prevents an caller-controlled search_path from resolving a
-- different table or operator.
create or replace function public.touch_updated_at()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

create or replace function public.is_allowed_youtube_link(value text)
returns boolean
language sql
immutable
set search_path = public
as $$
  select coalesce(value, '') = ''
      or value ~* '^https?://(www\.)?(youtube\.com|youtu\.be)(/|$)'
      or value ~* '^https?://(m|music)\.youtube\.com(/|$)';
$$;

create or replace function public.guard_community_song()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if new.owner <> old.owner or new.created_at <> old.created_at then
    raise exception 'This column is managed by ChordPlane.';
  end if;
  return new;
end;
$$;

create or replace function public.guard_shared_setlist_item()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if (public.shared_setlist_access(new.setlist_token)->>'permission') = 'comment'
     and (
       new.song_id is distinct from old.song_id
       or new.title is distinct from old.title
       or new.artist is distinct from old.artist
       or new.body is distinct from old.body
       or new.original_key is distinct from old.original_key
       or new.capo is distinct from old.capo
       or new.position is distinct from old.position
     ) then
    raise exception 'This link only allows comments.';
  end if;
  return new;
end;
$$;

create or replace function public.stamp_shared_setlist_editor()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  new.updated_by = auth.uid();
  new.updated_at = now();
  return new;
end;
$$;

-- Username availability only reads a public profile column, so it does not
-- need to bypass RLS.
create or replace function public.check_username_available(candidate text)
returns jsonb
language plpgsql
stable
security invoker
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

-- Internal trigger helpers and validators should never be callable as an API.
revoke execute on function public.handle_new_user() from public, anon, authenticated;
revoke execute on function public.apply_rating_change() from public, anon, authenticated;
revoke execute on function public.refresh_song_rating(uuid) from public, anon, authenticated;
revoke execute on function public.guard_community_song() from public, anon, authenticated;
revoke execute on function public.guard_shared_setlist_item() from public, anon, authenticated;
revoke execute on function public.stamp_shared_setlist_editor() from public, anon, authenticated;
revoke execute on function public.is_allowed_youtube_link(text) from public, anon, authenticated;

-- Signed-in-only RPCs: remove the implicit PUBLIC grant inherited by anon.
revoke execute on function public.set_username(text) from public, anon, authenticated;
grant execute on function public.set_username(text) to authenticated;
revoke execute on function public.record_active_day() from public, anon, authenticated;
grant execute on function public.record_active_day() to authenticated;

-- These three are intentionally public RPCs.
grant execute on function public.check_username_available(text) to anon, authenticated;
grant execute on function public.can_rate_songs() to anon, authenticated;
grant execute on function public.shared_setlist_access(text) to anon, authenticated;

-- Covering indexes for foreign keys created by 0002/0003.
create index if not exists song_ratings_user_idx on public.song_ratings (user_id);
create index if not exists shared_setlists_owner_idx on public.shared_setlists (owner);
create index if not exists shared_setlist_items_updated_by_idx
  on public.shared_setlist_items (updated_by);

-- Cache the current user once per statement instead of once per row.
drop policy if exists "profiles self" on public.profiles;
create policy "profiles self" on public.profiles
  for all using ((select auth.uid()) = id) with check ((select auth.uid()) = id);

drop policy if exists "owners manage own shares" on public.shared_bundles;
create policy "owners manage own shares" on public.shared_bundles
  for all using ((select auth.uid()) = owner) with check ((select auth.uid()) = owner);

drop policy if exists "activity days self" on public.user_activity_days;
create policy "activity days self" on public.user_activity_days
  for all using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);

drop policy if exists "community songs owner manages" on public.community_songs;
create policy "community songs owner manages" on public.community_songs
  for all using ((select auth.uid()) = owner)
  with check ((select auth.uid()) = owner);

drop policy if exists "ratings self read" on public.song_ratings;
create policy "ratings self read" on public.song_ratings
  for select using ((select auth.uid()) = user_id);

drop policy if exists "eligible users rate" on public.song_ratings;
create policy "eligible users rate" on public.song_ratings
  for insert with check (
    (select auth.uid()) = user_id
    and (public.can_rate_songs()->>'allowed') = 'true'
  );

drop policy if exists "rating owners update" on public.song_ratings;
create policy "rating owners update" on public.song_ratings
  for update using ((select auth.uid()) = user_id)
  with check (
    (select auth.uid()) = user_id
    and (public.can_rate_songs()->>'allowed') = 'true'
  );

drop policy if exists "rating owners delete" on public.song_ratings;
create policy "rating owners delete" on public.song_ratings
  for delete using ((select auth.uid()) = user_id);

drop policy if exists "live setlists public read" on public.shared_setlists;
create policy "live setlists public read" on public.shared_setlists
  for select using (
    (select auth.uid()) = owner
    or (revoked = false and (audience = 'anyone' or (select auth.uid()) is not null))
  );

drop policy if exists "live setlists owner manages" on public.shared_setlists;
create policy "live setlists owner manages" on public.shared_setlists
  for all using ((select auth.uid()) = owner)
  with check ((select auth.uid()) = owner);

notify pgrst, 'reload schema';
