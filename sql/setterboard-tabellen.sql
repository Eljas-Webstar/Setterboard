-- Setterboard: Tabellen und Zugriffsregeln
-- Einfügen in Supabase unter "SQL Editor", dann auf "Run".
-- Kann gefahrlos mehrfach ausgeführt werden.

-- 1) Kalender: gehört genau einem Closer
create table if not exists kalender (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  start_strasse text,
  start_plz text,
  start_ort text,
  angelegt timestamptz default now()
);

-- 2) Personen: verweist auf den Login in auth.users
create table if not exists personen (
  id uuid primary key references auth.users(id) on delete cascade,
  name text not null,
  rolle text not null check (rolle in ('admin','closer','setter')),
  kalender_id uuid references kalender(id) on delete set null,
  angelegt timestamptz default now()
);

-- 3) Termine
create table if not exists termine (
  id uuid primary key default gen_random_uuid(),
  kalender_id uuid not null references kalender(id) on delete cascade,
  vorname text,
  nachname text,
  telefon text,
  strasse text,
  plz text,
  ort text,
  pflegegrad text,
  wohnform text,
  notiz text,
  hinweise text[],
  entscheider boolean default false,
  papiere boolean default false,
  datum date not null,
  zeit time not null,
  dauer int default 60,
  status text default 'geplant',
  setter_name text,
  geaendert_von text,
  angelegt timestamptz default now(),
  geaendert timestamptz default now()
);
create index if not exists termine_kalender_datum on termine (kalender_id, datum);

-- 4) Gestrichene Tage
create table if not exists sperrtage (
  id uuid primary key default gen_random_uuid(),
  kalender_id uuid not null references kalender(id) on delete cascade,
  datum date not null,
  grund text,
  von_name text,
  angelegt timestamptz default now(),
  unique (kalender_id, datum)
);

-- 5) Verlauf
create table if not exists ereignisse (
  id uuid primary key default gen_random_uuid(),
  kalender_id uuid references kalender(id) on delete cascade,
  termin_id uuid references termine(id) on delete cascade,
  art text,
  text text,
  von_name text,
  zeitpunkt timestamptz default now()
);
create index if not exists ereignisse_kalender_zeit on ereignisse (kalender_id, zeitpunkt desc);

-- 6) Hilfsfunktionen: wer bin ich, welcher Kalender gehört mir
create or replace function mein_kalender() returns uuid
language sql stable security definer set search_path = public as $$
  select kalender_id from personen where id = auth.uid()
$$;

create or replace function bin_admin() returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from personen where id = auth.uid() and rolle = 'admin')
$$;

-- 7) Zugriffsregeln einschalten
alter table kalender   enable row level security;
alter table personen   enable row level security;
alter table termine    enable row level security;
alter table sperrtage  enable row level security;
alter table ereignisse enable row level security;

-- Kalender: sichtbar für Admin und für die Personen dieses Kalenders
drop policy if exists kalender_lesen on kalender;
create policy kalender_lesen on kalender for select
  using (bin_admin() or id = mein_kalender());

drop policy if exists kalender_schreiben on kalender;
create policy kalender_schreiben on kalender for all
  using (bin_admin() or id = mein_kalender())
  with check (bin_admin() or id = mein_kalender());

-- Personen: jeder sieht sich selbst, Admin sieht alle, Closer sieht seine Setter
drop policy if exists personen_lesen on personen;
create policy personen_lesen on personen for select
  using (bin_admin() or id = auth.uid() or kalender_id = mein_kalender());

drop policy if exists personen_schreiben on personen;
create policy personen_schreiben on personen for all
  using (bin_admin() or kalender_id = mein_kalender())
  with check (bin_admin() or kalender_id = mein_kalender());

-- Termine, Sperrtage, Verlauf: nur der eigene Kalender, Admin alles
drop policy if exists termine_alles on termine;
create policy termine_alles on termine for all
  using (bin_admin() or kalender_id = mein_kalender())
  with check (bin_admin() or kalender_id = mein_kalender());

drop policy if exists sperrtage_alles on sperrtage;
create policy sperrtage_alles on sperrtage for all
  using (bin_admin() or kalender_id = mein_kalender())
  with check (bin_admin() or kalender_id = mein_kalender());

drop policy if exists ereignisse_alles on ereignisse;
create policy ereignisse_alles on ereignisse for all
  using (bin_admin() or kalender_id = mein_kalender())
  with check (bin_admin() or kalender_id = mein_kalender());
