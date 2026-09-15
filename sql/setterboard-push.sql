-- Setterboard: Mitteilungen aufs Handy
-- Im SQL Editor einfügen und auf Run drücken. Kann mehrfach laufen.

-- 1) Angemeldete Geräte
create table if not exists push_geraete (
  id uuid primary key default gen_random_uuid(),
  person_id uuid not null references personen(id) on delete cascade,
  kalender_id uuid references kalender(id) on delete cascade,
  endpunkt text not null unique,
  p256dh text not null,
  auth text not null,
  geraet text,
  angelegt timestamptz default now()
);
create index if not exists push_kalender on push_geraete (kalender_id);

alter table push_geraete enable row level security;

drop policy if exists push_eigene on push_geraete;
create policy push_eigene on push_geraete for all
  using (person_id = auth.uid() or bin_admin())
  with check (person_id = auth.uid());

-- 2) Warteschlange: hier landet, was verschickt werden soll
create table if not exists push_warteschlange (
  id bigserial primary key,
  kalender_id uuid references kalender(id) on delete cascade,
  ausser_person uuid,                 -- wer es ausgelöst hat, bekommt selbst nichts
  titel text not null,
  text text not null,
  termin_id uuid,
  faellig timestamptz default now(),  -- erst ab dann verschicken
  gesendet timestamptz,
  angelegt timestamptz default now()
);
create index if not exists push_offen on push_warteschlange (gesendet, faellig);

alter table push_warteschlange enable row level security;
-- Niemand aus der App liest oder schreibt hier. Nur die Funktion mit Dienstschlüssel.

-- 3) Auslöser: wichtige Änderungen an Terminen
create or replace function push_bei_termin() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  wer text;
  wann text;
begin
  if (TG_OP = 'INSERT') then
    wer := coalesce(new.vorname,'') || ' ' || coalesce(new.nachname,'');
    wann := to_char(new.datum,'DD.MM.') || ' um ' || to_char(new.zeit,'HH24:MI');
    insert into push_warteschlange (kalender_id, ausser_person, titel, text, termin_id)
      values (new.kalender_id, auth.uid(), 'Neuer Termin',
              trim(wer) || ', ' || wann || ' in ' || coalesce(new.ort,'?'), new.id);
    -- Erinnerung 60 Minuten vorher
    insert into push_warteschlange (kalender_id, titel, text, termin_id, faellig)
      values (new.kalender_id, 'Gleich losfahren',
              trim(wer) || ' um ' || to_char(new.zeit,'HH24:MI') || ' in ' || coalesce(new.ort,'?'),
              new.id, (new.datum + new.zeit) - interval '60 minutes');
    return new;
  end if;

  if (TG_OP = 'UPDATE') then
    wer := coalesce(new.vorname,'') || ' ' || coalesce(new.nachname,'');
    if (new.datum, new.zeit) is distinct from (old.datum, old.zeit) then
      insert into push_warteschlange (kalender_id, ausser_person, titel, text, termin_id)
        values (new.kalender_id, auth.uid(), 'Termin verschoben',
                trim(wer) || ' jetzt ' || to_char(new.datum,'DD.MM.') || ' um ' || to_char(new.zeit,'HH24:MI'), new.id);
      -- alte Erinnerung weg, neue setzen
      delete from push_warteschlange
        where termin_id = new.id and gesendet is null and titel = 'Gleich losfahren';
      insert into push_warteschlange (kalender_id, titel, text, termin_id, faellig)
        values (new.kalender_id, 'Gleich losfahren',
                trim(wer) || ' um ' || to_char(new.zeit,'HH24:MI') || ' in ' || coalesce(new.ort,'?'),
                new.id, (new.datum + new.zeit) - interval '60 minutes');
    elsif new.status is distinct from old.status then
      if new.status = 'abgesagt' then
        insert into push_warteschlange (kalender_id, ausser_person, titel, text, termin_id)
          values (new.kalender_id, auth.uid(), 'Termin abgesagt',
                  trim(wer) || ' am ' || to_char(new.datum,'DD.MM.'), new.id);
        delete from push_warteschlange
          where termin_id = new.id and gesendet is null and titel = 'Gleich losfahren';
      else
        insert into push_warteschlange (kalender_id, ausser_person, titel, text, termin_id)
          values (new.kalender_id, auth.uid(), 'Ergebnis eingetragen',
                  trim(wer) || ': ' || new.status, new.id);
      end if;
    end if;
    return new;
  end if;

  return null;
end $$;

drop trigger if exists termin_push on termine;
create trigger termin_push after insert or update on termine
  for each row execute function push_bei_termin();

-- Gestrichener Tag
create or replace function push_bei_sperrtag() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  insert into push_warteschlange (kalender_id, ausser_person, titel, text)
    values (new.kalender_id, auth.uid(), 'Tag gestrichen',
            to_char(new.datum,'DD.MM.') || coalesce(': ' || new.grund, ''));
  return new;
end $$;

drop trigger if exists sperrtag_push on sperrtage;
create trigger sperrtag_push after insert on sperrtage
  for each row execute function push_bei_sperrtag();

-- 4) Morgenbriefing: legt für jeden Kalender eine Nachricht an
create or replace function push_morgenbriefing() returns void
language plpgsql security definer set search_path = public as $$
declare
  k record;
  anzahl int;
  erster text;
  letzter text;
begin
  for k in select id, name from kalender loop
    select count(*),
           min(to_char(zeit,'HH24:MI') || ' ' || coalesce(ort,'')),
           max(to_char(zeit,'HH24:MI') || ' ' || coalesce(ort,''))
      into anzahl, erster, letzter
      from termine
     where kalender_id = k.id and datum = current_date and status <> 'abgesagt';

    if anzahl > 0 then
      insert into push_warteschlange (kalender_id, titel, text)
        values (k.id, 'Guten Morgen ' || k.name,
                case when anzahl = 1
                     then 'Heute 1 Termin: ' || erster
                     else 'Heute ' || anzahl || ' Termine, erster ' || erster || ', letzter ' || letzter
                end);
    end if;
  end loop;
end $$;

-- 5) Zeitplan. Braucht die Erweiterungen pg_cron und pg_net.
create extension if not exists pg_cron;
create extension if not exists pg_net;

-- Morgens um 7 Uhr deutscher Zeit (5 Uhr UTC im Sommer, 6 im Winter)
select cron.unschedule('setterboard-briefing') where exists (
  select 1 from cron.job where jobname = 'setterboard-briefing');
select cron.schedule('setterboard-briefing','0 5 * * *', $$ select push_morgenbriefing(); $$);

-- Alle fünf Minuten die Warteschlange abarbeiten.
-- WICHTIG: PROJEKT und DIENSTSCHLUESSEL unten ersetzen, siehe push-einrichten.md
-- select cron.unschedule('setterboard-senden') where exists (
--   select 1 from cron.job where jobname = 'setterboard-senden');
-- select cron.schedule('setterboard-senden','*/5 * * * *', $$
--   select net.http_post(
--     url := 'https://PROJEKT.supabase.co/functions/v1/push-senden',
--     headers := '{"Content-Type":"application/json","Authorization":"Bearer DIENSTSCHLUESSEL"}'::jsonb,
--     body := '{}'::jsonb
--   );
-- $$);
