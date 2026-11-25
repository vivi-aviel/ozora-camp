-- Motorhome rental contracts signed by customers (rv-contract.html)
create table if not exists public.rv_contracts (
  id uuid primary key default gen_random_uuid(),
  ref text not null,
  booking jsonb not null,
  signer_name text not null,
  passport text not null,
  licence text not null,
  phone text not null,
  email text,
  driver2 text,
  signature text not null,
  user_agent text,
  signed_at timestamptz not null default now()
);

alter table public.rv_contracts enable row level security;
revoke all on public.rv_contracts from anon, authenticated;
grant select, delete on public.rv_contracts to authenticated;

drop policy if exists rv_contracts_admin on public.rv_contracts;
create policy rv_contracts_admin on public.rv_contracts
  for all to authenticated using (public.is_admin()) with check (public.is_admin());

create or replace function public.sign_rv_contract(
  p_ref text, p_booking jsonb, p_name text, p_passport text, p_licence text,
  p_phone text, p_email text, p_driver2 text, p_signature text, p_agent text)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare v_id uuid;
begin
  if p_ref !~ '^[A-Za-z0-9]{4,16}$' then raise exception 'bad ref'; end if;
  if coalesce(length(trim(p_name)),0) = 0 or coalesce(length(trim(p_passport)),0) = 0
     or coalesce(length(trim(p_licence)),0) = 0 or coalesce(length(trim(p_phone)),0) = 0 then
    raise exception 'missing fields';
  end if;
  if p_signature not like 'data:image/png;base64,%' or length(p_signature) > 400000 then
    raise exception 'bad signature';
  end if;
  if length(p_booking::text) > 20000 then raise exception 'too large'; end if;
  -- simple flood guard: max 5 signatures per ref
  if (select count(*) from public.rv_contracts where ref = p_ref) >= 5 then
    raise exception 'too many';
  end if;
  insert into public.rv_contracts (ref, booking, signer_name, passport, licence, phone, email, driver2, signature, user_agent)
  values (p_ref, p_booking, left(trim(p_name),200), left(trim(p_passport),40), left(trim(p_licence),40),
          left(trim(p_phone),40), nullif(left(trim(coalesce(p_email,'')),200),''),
          nullif(left(trim(coalesce(p_driver2,'')),300),''), p_signature, left(coalesce(p_agent,''),300))
  returning id into v_id;
  return v_id;
end $$;

revoke all on function public.sign_rv_contract(text,jsonb,text,text,text,text,text,text,text,text) from public;
grant execute on function public.sign_rv_contract(text,jsonb,text,text,text,text,text,text,text,text) to anon, authenticated;
