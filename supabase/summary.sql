-- =====================================================================
-- Ozora Camp – booking summary page for guests
-- Paste into Supabase → SQL Editor → New query → Run. Safe to run more than once.
-- A guest can see ONLY their own confirmed booking, and only with its secret link.
-- =====================================================================
create or replace function public.guest_summary(p_id uuid) returns json
language sql stable security definer set search_path = public as $$
  select json_build_object(
    'name', split_part(trim(coalesce(b.names,'')), ' ', 1),
    'guests', b.guests, 'checkIn', b.check_in, 'checkOut', b.check_out,
    'unitType', u.type, 'unitNo', regexp_replace(coalesce(u.name,''), '\D', '', 'g'),
    'lang', b.lang)
  from public.bookings b left join public.units u on u.id = b.unit_id
  where b.id = p_id and b.status = 'confirmed';
$$;
revoke execute on function public.guest_summary(uuid) from public;
grant execute on function public.guest_summary(uuid) to anon, authenticated;
