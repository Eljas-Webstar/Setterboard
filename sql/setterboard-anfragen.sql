-- Setterboard: Setter melden sich selbst an
-- Im SQL Editor einfügen und auf Run drücken. Kann mehrfach laufen.

-- 1) Anfragen von Settern an einen Closer
create table if not exists anfragen (
  id uuid primary key default gen_random_uuid(),
  person_id uuid not null references personen(id) on delete cascade,
  kalender_id uuid not null references kalender(id) on delete cascade,
  status text not null default 'offen' check (status in ('offen','angenommen','abgelehnt','zurueckgezogen')),
  angelegt timestamptz default now(),
  entschieden timestamptz
);
create index if not exists anfragen_offen on anfragen (kalender_id, status);

-- 2) Einladungen, die ein Closer per WhatsApp verschickt
create table if not exists einladungen (
  code text primary key,
  kalender_id uuid not null references kalender(id) on delete cascade,
  von_person uuid references personen(id) on delete set null,
  angelegt timestamptz default now(),
  laeuft_ab timestamptz default (now() + interval '14 days'),
  eingeloest_von uuid references personen(id) on delete set null,
  eingeloest_am timestamptz
);

-- 3) Namen der Kalender, damit ein neuer Setter seinen Closer auswählen kann.
--    Gibt nur Name und Kennung heraus, keine Adressen und keine Termine.
create or replace function kalender_liste()
returns table (id uuid, name text)
language sql stable security definer set search_path = public as $$
  select k.id, k.name from kalender k order by k.name
$$;
revoke all on function kalender_liste() from public;
grant execute on function kalender_liste() to authenticated;

-- 4) Einladung einlösen: ordnet den angemeldeten Nutzer dem Kalender zu
create or replace function einladung_einloesen(code_ein text)
returns text
language plpgsql security definer set search_path = public as $$
declare e record;
begin
  select * into e from einladungen where code = code_ein;
  if not found then return 'unbekannt'; end if;
  if e.laeuft_ab < now() then return 'abgelaufen'; end if;
  if e.eingeloest_am is not null then return 'schon benutzt'; end if;

  update personen set kalender_id = e.kalender_id, rolle = 'setter'
   where id = auth.uid() and rolle = 'setter';
  if not found then return 'kein setterzugang'; end if;

  update einladungen set eingeloest_von = auth.uid(), eingeloest_am = now()
   where code = code_ein;

  update anfragen set status = 'angenommen', entschieden = now()
   where person_id = auth.uid() and status = 'offen';

  return 'ok';
end $$;
revoke all on function einladung_einloesen(text) from public;
grant execute on function einladung_einloesen(text) to authenticated;

-- 5) Selbstanlage als Setter ohne Kalender wieder erlauben
drop policy if exists personen_selbstanlage on personen;
create policy personen_selbstanlage on personen for insert to authenticated
  with check (id = auth.uid() and rolle = 'setter' and kalender_id is null);

-- Der eigene Eintrag darf gelesen werden, auch ohne Kalender
drop policy if exists personen_lesen on personen;
create policy personen_lesen on personen for select
  using (bin_admin() or id = auth.uid() or kalender_id = mein_kalender());

-- 6) Zugriff auf die Anfragen
alter table anfragen enable row level security;

drop policy if exists anfragen_stellen on anfragen;
create policy anfragen_stellen on anfragen for insert to authenticated
  with check (person_id = auth.uid());

drop policy if exists anfragen_lesen on anfragen;
create policy anfragen_lesen on anfragen for select
  using (person_id = auth.uid() or bin_admin() or kalender_id = mein_kalender());

-- Der Setter darf nur zurückziehen, der Closer entscheidet
drop policy if exists anfragen_aendern on anfragen;
create policy anfragen_aendern on anfragen for update
  using (person_id = auth.uid() or bin_admin() or kalender_id = mein_kalender())
  with check (person_id = auth.uid() or bin_admin() or kalender_id = mein_kalender());

-- 7) Zugriff auf die Einladungen
alter table einladungen enable row level security;

drop policy if exists einladungen_anlegen on einladungen;
create policy einladungen_anlegen on einladungen for insert to authenticated
  with check (bin_admin() or kalender_id = mein_kalender());

drop policy if exists einladungen_lesen on einladungen;
create policy einladungen_lesen on einladungen for select
  using (bin_admin() or kalender_id = mein_kalender());

drop policy if exists einladungen_loeschen on einladungen;
create policy einladungen_loeschen on einladungen for delete
  using (bin_admin() or kalender_id = mein_kalender());

-- 8) Wenn der Closer eine Anfrage annimmt, bekommt der Setter seinen Kalender
create or replace function anfrage_entschieden() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if new.status = 'angenommen' and old.status <> 'angenommen' then
    update personen set kalender_id = new.kalender_id where id = new.person_id;
    new.entschieden := now();
  elsif new.status in ('abgelehnt','zurueckgezogen') and old.status = 'offen' then
    new.entschieden := now();
  end if;
  return new;
end $$;

drop trigger if exists anfrage_wirkt on anfragen;
create trigger anfrage_wirkt before update on anfragen
  for each row execute function anfrage_entschieden();

-- 9) Mitteilung an den Closer, sobald eine Anfrage hereinkommt
create or replace function push_bei_anfrage() returns trigger
language plpgsql security definer set search_path = public as $$
declare wer text;
begin
  select name into wer from personen where id = new.person_id;
  insert into push_warteschlange (kalender_id, ausser_person, titel, text)
    values (new.kalender_id, new.person_id, 'Neue Anfrage',
            coalesce(wer,'Jemand') || ' möchte für dich Termine eintragen');
  return new;
end $$;

drop trigger if exists anfrage_push on anfragen;
create trigger anfrage_push after insert on anfragen
  for each row execute function push_bei_anfrage();

-- Kontrolle
select 'Tabellen' as was, count(*)::text as anzahl from information_schema.tables
 where table_name in ('anfragen','einladungen')
union all
select 'Funktionen', count(*)::text from pg_proc
 where proname in ('kalender_liste','einladung_einloesen');
