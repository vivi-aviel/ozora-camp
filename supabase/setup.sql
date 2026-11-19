-- =====================================================================
-- Ozora Camp – database setup
-- Paste this whole file into Supabase → SQL Editor → New query → Run.
-- Safe to run once on a new, empty project.
-- =====================================================================

-- ---------- tables ----------
create table if not exists public.admins (
  user_id uuid primary key references auth.users(id) on delete cascade
);

create table if not exists public.seasons (
  id text primary key,
  name text not null,
  start_date date,
  end_date date,
  eur_ils numeric,            -- 1 EUR = x ILS (set by you; never assumed)
  eur_huf numeric,            -- 1 EUR = x HUF
  target_ils numeric default 50000,
  min_nights int default 7,
  price_room numeric default 80,   -- € per person per night
  price_car numeric default 50,    -- € per person per night
  kat_room numeric default 25,     -- Katalin: € per person per actual night
  kat_car numeric default 15,      -- Katalin: € per caravan per actual night
  public boolean default false,    -- the season shown on the customer website
  created_at timestamptz default now()
);

create table if not exists public.units (
  id text primary key,
  name text not null,
  type text not null check (type in ('room','caravan')),
  capacity int not null default 2,
  commercial boolean not null default true,
  sort int default 0
);

create table if not exists public.bookings (
  id uuid primary key default gen_random_uuid(),
  season_id text references public.seasons(id) on delete set null,
  unit_id text references public.units(id) on delete set null,
  status text not null default 'request' check (status in ('request','confirmed','declined')),
  req_type text check (req_type in ('room2','room3','caravan')),
  names text, phone text, email text,
  guests int,
  check_in date, check_out date,
  no_show boolean default false,
  currency text default 'EUR' check (currency in ('EUR','ILS')),
  charged numeric, received numeric,
  list_rate numeric, kat_rate numeric,
  kat_basis text check (kat_basis in ('person','unit')),
  paid_date date, method text, note text,
  source text default 'admin', lang text,
  created_at timestamptz default now(),
  approved_at timestamptz
);
create index if not exists bookings_season_idx on public.bookings(season_id);
create index if not exists bookings_unit_dates_idx on public.bookings(unit_id, check_in, check_out);

create table if not exists public.payouts (
  id uuid primary key default gen_random_uuid(),
  season_id text references public.seasons(id) on delete set null,
  amount_eur numeric not null,
  date date, note text,
  created_at timestamptz default now()
);

-- ---------- security: only admins can touch business data ----------
create or replace function public.is_admin() returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.admins where user_id = auth.uid());
$$;

alter table public.admins   enable row level security;
alter table public.seasons  enable row level security;
alter table public.units    enable row level security;
alter table public.bookings enable row level security;
alter table public.payouts  enable row level security;

drop policy if exists admin_self on public.admins;
create policy admin_self on public.admins for select to authenticated using (user_id = auth.uid());
drop policy if exists admin_all on public.seasons;
create policy admin_all on public.seasons  for all to authenticated using (public.is_admin()) with check (public.is_admin());
drop policy if exists admin_all on public.units;
create policy admin_all on public.units    for all to authenticated using (public.is_admin()) with check (public.is_admin());
drop policy if exists admin_all on public.bookings;
create policy admin_all on public.bookings for all to authenticated using (public.is_admin()) with check (public.is_admin());
drop policy if exists admin_all on public.payouts;
create policy admin_all on public.payouts  for all to authenticated using (public.is_admin()) with check (public.is_admin());

revoke all on public.admins, public.seasons, public.units, public.bookings, public.payouts from anon;
grant select on public.admins to authenticated;
grant select, insert, update, delete on public.seasons, public.units, public.bookings, public.payouts to authenticated;

-- ---------- public functions used by the customer website ----------
-- They expose ONLY: the public season's name/dates/list prices, and how many units of each type are free.
-- No names, payments, Katalin rates or profits ever leave the database through them.

create or replace function public.public_info() returns json
language sql stable security definer set search_path = public as $$
  select json_build_object('id', id, 'name', name, 'start', start_date, 'end', end_date,
    'minNights', min_nights, 'priceRoom', price_room, 'priceCar', price_car)
  from public.seasons where public order by start_date desc nulls last limit 1;
$$;

create or replace function public.free_counts(p_in date, p_out date) returns json
language plpgsql stable security definer set search_path = public as $$
declare r json;
begin
  if p_in is null or p_out is null or p_out <= p_in or p_out - p_in > 60 then return null; end if;
  select json_build_object(
    'room2',   count(*) filter (where u.type = 'room' and u.capacity >= 2),
    'room3',   count(*) filter (where u.type = 'room' and u.capacity >= 3),
    'caravan', count(*) filter (where u.type = 'caravan'))
  into r
  from public.units u
  where u.commercial
    and not exists (select 1 from public.bookings b
                    where b.unit_id = u.id and b.status = 'confirmed'
                      and b.check_in < p_out and p_in < b.check_out);
  return r;
end $$;

create or replace function public.submit_request(
  p_type text, p_guests int, p_in date, p_out date,
  p_names text, p_phone text, p_email text default null, p_note text default null, p_lang text default null)
returns boolean
language plpgsql volatile security definer set search_path = public as $$
declare s_id text; maxg int;
begin
  if p_type not in ('room2','room3','caravan') then raise exception 'bad_type'; end if;
  maxg := case p_type when 'room3' then 3 else 2 end;
  if p_guests is null or p_guests < 1 or p_guests > maxg then raise exception 'bad_guests'; end if;
  if p_in is null or p_out is null or p_out <= p_in or p_out - p_in > 60 or p_in < current_date then raise exception 'bad_dates'; end if;
  if coalesce(length(trim(p_names)),0) < 2 or length(p_names) > 200 then raise exception 'bad_name'; end if;
  if coalesce(length(trim(p_phone)),0) < 6 or length(p_phone) > 40 then raise exception 'bad_phone'; end if;
  if length(coalesce(p_email,'')) > 200 or length(coalesce(p_note,'')) > 1000 then raise exception 'too_long'; end if;
  if (select count(*) from public.bookings where source = 'website' and created_at > now() - interval '1 hour') >= 30 then
    raise exception 'busy'; end if;
  select id into s_id from public.seasons where public order by start_date desc nulls last limit 1;
  insert into public.bookings (season_id, status, req_type, guests, check_in, check_out, names, phone, email, note, source, lang)
  values (s_id, 'request', p_type, p_guests, p_in, p_out, trim(p_names), trim(p_phone),
          nullif(trim(coalesce(p_email,'')), ''), nullif(trim(coalesce(p_note,'')), ''), 'website', p_lang);
  return true;
end $$;

-- keep-alive: touched every 3 days by GitHub so the free project is not paused
create or replace function public.ping() returns int
language sql stable security definer set search_path = public as $$
  select count(*)::int from public.seasons;
$$;

revoke execute on function public.is_admin() from public, anon;
grant execute on function public.is_admin() to authenticated;
revoke execute on function public.public_info(), public.free_counts(date,date),
  public.submit_request(text,int,date,date,text,text,text,text,text), public.ping() from public;
grant execute on function public.public_info(), public.free_counts(date,date),
  public.submit_request(text,int,date,date,text,text,text,text,text), public.ping() to anon, authenticated;

-- ---------- data: units, seasons, 2026 bookings ----------
insert into public.units (id, name, type, capacity, commercial, sort) values
  ('r1','חדר 1','room',2,true,1), ('r2','חדר 2','room',2,true,2), ('r3','חדר 3','room',2,true,3),
  ('r4','חדר 4','room',2,true,4), ('r5','חדר 5','room',2,true,5), ('r6','חדר 6','room',3,true,6),
  ('r7','חדר 7','room',3,true,7), ('r8','חדר 8','room',2,false,8),
  ('c1','קרוואן 1','caravan',2,true,9), ('c2','קרוואן 2','caravan',2,true,10)
on conflict (id) do nothing;

insert into public.seasons (id, name, start_date, end_date, target_ils, min_nights, price_room, price_car, kat_room, kat_car, public) values
  ('s2026','Ozora 2026','2026-07-22','2026-08-03',50000,7,80,50,25,15,false),
  ('s2027','Ozora 2027','2027-07-18','2027-08-05',50000,7,80,50,25,15,true)
on conflict (id) do nothing;

insert into public.bookings (season_id, unit_id, status, names, guests, check_in, check_out, currency, charged, received, list_rate, kat_rate, kat_basis, note, source) values
  ('s2026','r1','confirmed','אלבינה ואלי',2,'2026-07-24','2026-08-02','EUR',1600,1600,80,25,'person',null,'admin'),
  ('s2026','r2','confirmed','שתי נשים ממקסיקו',2,'2026-07-26','2026-08-02','EUR',1120,1120,80,25,'person',null,'admin'),
  ('s2026','r3','confirmed','שלומי ונטע',2,'2026-07-27','2026-08-02','ILS',4000,4000,80,25,'person',null,'admin'),
  ('s2026','r4','confirmed','שירלי וחברה',2,'2026-07-27','2026-08-02','ILS',4200,4200,80,25,'person',null,'admin'),
  ('s2026','r5','confirmed','אופק וחבר',2,'2026-07-26','2026-08-02','ILS',4200,4200,80,25,'person',null,'admin'),
  ('s2026','r6','confirmed','עדי, יואב והגר',3,'2026-07-27','2026-08-02','ILS',6220,6220,80,25,'person',null,'admin'),
  ('s2026','r7','confirmed','נועם ושני אורחים נוספים',3,'2026-07-26','2026-08-02','EUR',1570,1570,80,25,'person',null,'admin'),
  ('s2026','c1','confirmed','אהוד',2,'2026-07-25','2026-08-01','EUR',800,800,50,15,'unit','מספר האורחים לא נרשם – 2 הוא הערכה, לעדכן','admin'),
  ('s2026','c2','confirmed','אופיר',2,'2026-07-26','2026-08-01','EUR',800,800,50,15,'unit','מספר האורחים לא נרשם – 2 הוא הערכה, לעדכן','admin');

-- ---------- make you the administrator ----------
-- Run this AFTER you created your login user (Authentication → Users → Add user).
-- If you created the user before running this file, it already works.
insert into public.admins (user_id) select id from auth.users on conflict do nothing;
