-- ChordPlane: live, link-shared setlists with host-controlled permissions.
-- Run in the Supabase SQL editor or via `supabase db push` after 0002.

create table if not exists public.shared_setlists (
  token text primary key,
  owner uuid not null references auth.users (id) on delete cascade,
  title text not null default '',
  permission text not null default 'view'
    check (permission in ('view', 'comment', 'edit')),
  audience text not null default 'anyone'
    check (audience in ('anyone', 'signed_in')),
  revoked boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.shared_setlist_items (
  id uuid primary key default gen_random_uuid(),
  setlist_token text not null
    references public.shared_setlists (token) on delete cascade,
  song_id text not null,
  title text not null,
  artist text not null default '',
  body text not null default '',
  original_key text not null default '',
  capo integer not null default 0,
  position real not null default 0,
  note text not null default '',
  updated_by uuid references auth.users (id) on delete set null,
  updated_at timestamptz not null default now()
);

create index if not exists shared_setlist_items_order_idx
  on public.shared_setlist_items (setlist_token, position);

alter table public.shared_setlists enable row level security;
alter table public.shared_setlist_items enable row level security;

-- Helpers are security definer so policies never recurse into their own
-- select policy.
create or replace function public.shared_setlist_access(target_token text)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  row_data public.shared_setlists%rowtype;
begin
  select * into row_data
  from public.shared_setlists
  where token = target_token and revoked = false;
  if not found then
    return jsonb_build_object('visible', false, 'permission', 'none');
  end if;
  -- A signed-in-only link is not even readable anonymously. Returning
  -- visible=true here would otherwise let RLS on shared_setlist_items leak
  -- its songs before sign-in.
  if row_data.audience = 'signed_in' and auth.uid() is null then
    return jsonb_build_object(
      'visible', false,
      'permission', 'none',
      'audience', row_data.audience
    );
  end if;
  return jsonb_build_object(
    'visible', true,
    'permission',
      case when auth.uid() = row_data.owner then 'owner'
           else row_data.permission end,
    'audience', row_data.audience
  );
end;
$$;

grant execute on function public.shared_setlist_access(text) to anon, authenticated;

drop policy if exists "live setlists public read" on public.shared_setlists;
create policy "live setlists public read" on public.shared_setlists
  for select using (
    auth.uid() = owner
    or (revoked = false and (audience = 'anyone' or auth.uid() is not null))
  );

drop policy if exists "live setlists owner manages" on public.shared_setlists;
create policy "live setlists owner manages" on public.shared_setlists
  for all using (auth.uid() = owner) with check (auth.uid() = owner);

drop policy if exists "live items read" on public.shared_setlist_items;
create policy "live items read" on public.shared_setlist_items
  for select using (
    (public.shared_setlist_access(setlist_token)->>'visible') = 'true'
  );

drop policy if exists "live items add" on public.shared_setlist_items;
create policy "live items add" on public.shared_setlist_items
  for insert with check (
    (public.shared_setlist_access(setlist_token)->>'permission') = 'edit'
  );

drop policy if exists "live items edit" on public.shared_setlist_items;
create policy "live items edit" on public.shared_setlist_items
  for update using (
    (public.shared_setlist_access(setlist_token)->>'permission') in ('edit', 'comment')
  )
  with check (
    (public.shared_setlist_access(setlist_token)->>'permission') in ('edit', 'comment')
  );

drop policy if exists "live items remove" on public.shared_setlist_items;
create policy "live items remove" on public.shared_setlist_items
  for delete using (
    (public.shared_setlist_access(setlist_token)->>'permission') = 'edit'
  );

grant select on public.shared_setlists, public.shared_setlist_items to anon, authenticated;
grant insert, update, delete on public.shared_setlists to authenticated;
grant insert, update, delete on public.shared_setlist_items to authenticated;

-- Comment-only guests may change the note, but not the song itself.
create or replace function public.guard_shared_setlist_item()
returns trigger
language plpgsql
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

drop trigger if exists shared_setlist_item_guard on public.shared_setlist_items;
create trigger shared_setlist_item_guard
  before update on public.shared_setlist_items
  for each row execute function public.guard_shared_setlist_item();

create or replace function public.stamp_shared_setlist_editor()
returns trigger
language plpgsql
as $$
begin
  new.updated_by = auth.uid();
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists shared_setlist_item_stamp on public.shared_setlist_items;
create trigger shared_setlist_item_stamp
  before insert or update on public.shared_setlist_items
  for each row execute function public.stamp_shared_setlist_editor();

drop trigger if exists shared_setlists_touch on public.shared_setlists;
create trigger shared_setlists_touch
  before update on public.shared_setlists
  for each row execute function public.touch_updated_at();

-- Realtime delivery for open collaborators. The do-block keeps the migration
-- idempotent when the tables are already members of the publication.
do $$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'shared_setlist_items'
  ) then
    alter publication supabase_realtime add table public.shared_setlist_items;
  end if;
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'shared_setlists'
  ) then
    alter publication supabase_realtime add table public.shared_setlists;
  end if;
end;
$$;

-- Refresh PostgREST's schema cache after the new tables and RPCs above.
notify pgrst, 'reload schema';
