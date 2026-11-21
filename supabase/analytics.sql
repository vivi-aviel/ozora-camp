-- =====================================================================
-- Ozora Camp – visit counter
-- Paste into Supabase → SQL Editor → New query → Run. Safe to run more than once.
-- Stores no personal data: only time, where the visitor came from, language and phone/computer.
-- =====================================================================

create table if not exists public.page_views (
  id bigserial primary key,
  created_at timestamptz not null default now(),
  source text,
  lang text,
  device text
);
create index if not exists page_views_created_idx on public.page_views(created_at);

alter table public.page_views enable row level security;
drop policy if exists admin_read on public.page_views;
create policy admin_read on public.page_views for select to authenticated using (public.is_admin());
drop policy if exists admin_delete on public.page_views;
create policy admin_delete on public.page_views for delete to authenticated using (public.is_admin());
revoke all on public.page_views from anon;
grant select, delete on public.page_views to authenticated;

-- the website calls this once per visit
create or replace function public.log_visit(p_source text default null, p_lang text default null, p_device text default null)
returns void language plpgsql volatile security definer set search_path = public as $$
begin
  if (select count(*) from public.page_views where created_at > now() - interval '1 hour') >= 3000 then return; end if;
  insert into public.page_views (source, lang, device)
  values (left(coalesce(nullif(trim(p_source),''),'direct'),40),
          case when p_lang in ('he','en') then p_lang else null end,
          case when p_device in ('mobile','desktop') then p_device else null end);
end $$;

-- the admin app reads a summary (admins only)
create or replace function public.visit_stats(p_from timestamptz default null) returns json
language plpgsql stable security definer set search_path = public as $$
declare r json; tz text := 'Asia/Jerusalem';
begin
  if not public.is_admin() then return null; end if;
  select json_build_object(
    'today',   (select count(*) from page_views where (created_at at time zone tz)::date = (now() at time zone tz)::date),
    'week',    (select count(*) from page_views where created_at > now() - interval '7 days'),
    'month',   (select count(*) from page_views where created_at > now() - interval '30 days'),
    'since',   (select count(*) from page_views where p_from is null or created_at >= p_from),
    'reqWeek', (select count(*) from bookings where source='website' and created_at > now() - interval '7 days'),
    'reqMonth',(select count(*) from bookings where source='website' and created_at > now() - interval '30 days'),
    'reqSince',(select count(*) from bookings where source='website' and (p_from is null or created_at >= p_from)),
    'mobile',  (select count(*) from page_views where created_at > now() - interval '30 days' and device='mobile'),
    'sources', (select coalesce(json_agg(x order by x.n desc),'[]'::json) from
                 (select source as s, count(*) as n from page_views where created_at > now() - interval '30 days' group by source) x),
    'daily',   (select json_agg(json_build_object('d', d::date, 'n', coalesce(c.n,0)) order by d) from
                 generate_series((now() at time zone tz)::date - 13, (now() at time zone tz)::date, interval '1 day') d
                 left join (select (created_at at time zone tz)::date as day, count(*) as n from page_views
                            where created_at > now() - interval '15 days' group by 1) c on c.day = d::date)
  ) into r;
  return r;
end $$;

revoke execute on function public.log_visit(text,text,text) from public;
grant execute on function public.log_visit(text,text,text) to anon, authenticated;
revoke execute on function public.visit_stats(timestamptz) from public, anon;
grant execute on function public.visit_stats(timestamptz) to authenticated;
