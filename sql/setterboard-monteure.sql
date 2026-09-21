-- Setterboard: Monteure und Aufträge
-- Im SQL Editor einfügen und auf Run drücken. Kann mehrfach laufen.

-- 1) Zwei neue Rollen zulassen
alter table personen drop constraint if exists personen_rolle_check;
alter table personen add constraint personen_rolle_check
  check (rolle in ('admin','verwaltung','closer','setter','monteur'));

-- 2) Termine sind entweder Beratung oder Einbau
alter table termine add column if not exists art text not null default 'beratung';
alter table termine drop constraint if exists termine_art_check;
alter table termine add constraint termine_art_check check (art in ('beratung','einbau'));

-- 3) Der Auftrag lebt zwischen Verkauf und Einbau
create table if not exists auftraege (
  id uuid primary key default gen_random_uuid(),
  termin_id uuid references termine(id) on delete set null,   -- der Beratungstermin
  kalender_id uuid references kalender(id) on delete set null,-- Kalender des Closers
  vorname text, nachname text, telefon text,
  strasse text, plz text, ort text,
  umfang text,                                                -- Dusche, Wanne, Treppe
  status text not null default 'verkauft'
    check (status in ('verkauft','beantragt','genehmigt','terminiert','erledigt','abgelehnt')),
  genehmigt_am date,
  einbau_termin_id uuid references termine(id) on delete set null,
  monteur_kalender uuid references kalender(id) on delete set null,
  verkauft_von text,        -- Name des Closers
  gesetzt_von text,         -- Name des Setters, für die Zurechnung
  notiz text,
  angelegt timestamptz default now(),
  geaendert timestamptz default now()
);
create index if not exists auftraege_status on auftraege (status, angelegt desc);

-- 4) Wer darf was sehen
create or replace function meine_rolle() returns text
language sql stable security definer set search_path = public as $$
  select rolle from personen where id = auth.uid()
$$;

alter table auftraege enable row level security;

drop policy if exists auftraege_lesen on auftraege;
create policy auftraege_lesen on auftraege for select using (
  bin_admin()
  or meine_rolle() = 'verwaltung'
  or kalender_id = mein_kalender()          -- der Closer sieht seine eigenen
  or monteur_kalender = mein_kalender()     -- der Monteur sieht die ihm zugeteilten
);

drop policy if exists auftraege_anlegen on auftraege;
create policy auftraege_anlegen on auftraege for insert to authenticated
  with check (bin_admin() or meine_rolle() = 'verwaltung' or kalender_id = mein_kalender());

drop policy if exists auftraege_aendern on auftraege;
create policy auftraege_aendern on auftraege for update using (
  bin_admin() or meine_rolle() = 'verwaltung'
  or kalender_id = mein_kalender()
  or monteur_kalender = mein_kalender()
) with check (true);

-- Die Verwaltung darf alle Kalender sehen, um Einbauten zu planen
drop policy if exists kalender_lesen on kalender;
create policy kalender_lesen on kalender for select
  using (bin_admin() or meine_rolle() = 'verwaltung' or id = mein_kalender());

drop policy if exists termine_alles on termine;
create policy termine_alles on termine for all
  using (bin_admin() or meine_rolle() = 'verwaltung' or kalender_id = mein_kalender())
  with check (bin_admin() or meine_rolle() = 'verwaltung' or kalender_id = mein_kalender());

drop policy if exists personen_lesen on personen;
create policy personen_lesen on personen for select
  using (bin_admin() or meine_rolle() = 'verwaltung' or id = auth.uid() or kalender_id = mein_kalender());

-- 5) Mitteilung an den Monteur, sobald ein Einbau für ihn steht
create or replace function push_bei_einbau() returns trigger
language plpgsql security definer set search_path = public as $$
declare wer text;
begin
  if new.art <> 'einbau' then return new; end if;
  wer := trim(coalesce(new.vorname,'') || ' ' || coalesce(new.nachname,''));
  insert into push_warteschlange (kalender_id, titel, text, termin_id)
    values (new.kalender_id, 'Neuer Einbau',
            wer || ' am ' || to_char(new.datum,'DD.MM.') || ' um ' || to_char(new.zeit,'HH24:MI')
                || ' in ' || coalesce(new.ort,'?'), new.id);
  -- Erinnerung am Vortag um 18 Uhr, der Monteur fährt früh los
  insert into push_warteschlange (kalender_id, titel, text, termin_id, faellig)
    values (new.kalender_id, 'Morgen Einbau',
            wer || ' um ' || to_char(new.zeit,'HH24:MI') || ' in ' || coalesce(new.ort,'?'),
            new.id, (new.datum - 1) + time '18:00');
  return new;
end $$;

drop trigger if exists einbau_push on termine;
create trigger einbau_push after insert on termine
  for each row execute function push_bei_einbau();

-- Kontrolle
select 'Rollen erlaubt' as was, pg_get_constraintdef(oid) as wert
  from pg_constraint where conname = 'personen_rolle_check'
union all
select 'Tabelle auftraege', count(*)::text from information_schema.tables where table_name='auftraege'
union all
select 'Feld art in termine', count(*)::text from information_schema.columns
  where table_name='termine' and column_name='art';
