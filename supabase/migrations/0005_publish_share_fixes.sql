-- ChordPlane: restore publishing and live setlist item writes after hardening.
-- 0004 revoked EXECUTE on the YouTube validator that the community_songs CHECK
-- constraint calls, and live item policies only accepted `edit` even though
-- shared_setlist_access() reports `owner` for the host.

-- The validator is an immutable helper used by a table constraint. It must be
-- callable by signed-in writers, but not by anonymous API clients.
revoke execute on function public.is_allowed_youtube_link(text) from public, anon, authenticated;
grant execute on function public.is_allowed_youtube_link(text) to authenticated;

-- Hosts must be able to add, edit and remove items in their own live setlist.
drop policy if exists "live items add" on public.shared_setlist_items;
create policy "live items add" on public.shared_setlist_items
  for insert with check (
    (public.shared_setlist_access(setlist_token)->>'permission') in ('owner', 'edit')
  );

drop policy if exists "live items edit" on public.shared_setlist_items;
create policy "live items edit" on public.shared_setlist_items
  for update using (
    (public.shared_setlist_access(setlist_token)->>'permission') in ('owner', 'edit', 'comment')
  )
  with check (
    (public.shared_setlist_access(setlist_token)->>'permission') in ('owner', 'edit', 'comment')
  );

drop policy if exists "live items remove" on public.shared_setlist_items;
create policy "live items remove" on public.shared_setlist_items
  for delete using (
    (public.shared_setlist_access(setlist_token)->>'permission') in ('owner', 'edit')
  );

notify pgrst, 'reload schema';
