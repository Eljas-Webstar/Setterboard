-- Setterboard: Terminbestätigung, Kundenerinnerung und richtige Zeitzone
-- Im SQL Editor einfügen und auf Run drücken. Kann mehrfach laufen.

-- 1) Neue Felder
alter table termine  add column if not exists anrede text;             -- Herr oder Frau
alter table termine  add column if not exists kunde_erinnern int;      -- Minuten vor dem Termin, leer = keine
alter table termine  add column if not exists bestaetigt_am timestamptz;
alter table termine  add column if not exists bestaetigt_von text;
alter table kalender add column if not exists telefon text;            -- Nummer des Closers
alter table kalender add column if not exists anrede text;             -- Herr oder Frau

-- 2) Termine stehen in deutscher Zeit, die Datenbank rechnet in UTC.
--    Ohne diese Umrechnung käme "Gleich losfahren" im Sommer zwei Stunden zu spät.
create or replace function termin_zeitpunkt(d date, z time) returns timestamptz
language sql stable as $$
  select (d + z) at time zone 'Europe/Berlin'
$$;

-- 3) Erinnerung an den Closer, den Kunden anzurufen oder anzuschreiben
create or replace function kunden_erinnerung_setzen(t termine) returns void
language plpgsql security definer set search_path = public as $$
declare wann timestamptz; wer text; tag text;
begin
  delete from push_warteschlange
   where termin_id = t.id and gesendet is null and titel = 'Kunden erinnern';
  if t.kunde_erinnern is null or t.status = 'abgesagt' then return; end if;
  wann := termin_zeitpunkt(t.datum, t.zeit) - make_interval(mins => t.kunde_erinnern);
  if wann <= now() then return; end if;      -- schon vorbei, der Kunde hat gerade erst zugesagt
  wer := case when coalesce(t.anrede,'') <> '' and coalesce(t.nachname,'') <> ''
              then t.anrede || ' ' || t.nachname
              else trim(coalesce(t.vorname,'') || ' ' || coalesce(t.nachname,'')) end;
  tag := case when t.kunde_erinnern >= 2880 then 'übermorgen'
              when t.kunde_erinnern >= 1440 then 'morgen'
              else 'heute' end;
  insert into push_warteschlange (kalender_id, titel, text, termin_id, faellig)
    values (t.kalender_id, 'Kunden erinnern',
            wer || ', ' || tag || ' ' || to_char(t.zeit,'HH24:MI') || ' in ' || coalesce(t.ort,'?')
                || '. Tippen zum Anrufen oder für die SMS.',
            t.id, wann);
end $$;

-- 4) Der bestehende Auslöser, jetzt mit Zeitzone und Kundenerinnerung
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
    insert into push_warteschlange (kalender_id, titel, text, termin_id, faellig)
      values (new.kalender_id, 'Gleich losfahren',
              trim(wer) || ' um ' || to_char(new.zeit,'HH24:MI') || ' in ' || coalesce(new.ort,'?'),
              new.id, termin_zeitpunkt(new.datum, new.zeit) - interval '60 minutes');
    perform kunden_erinnerung_setzen(new);
    return new;
  end if;
  if (TG_OP = 'UPDATE') then
    wer := coalesce(new.vorname,'') || ' ' || coalesce(new.nachname,'');
    if (new.datum, new.zeit) is distinct from (old.datum, old.zeit) then
      insert into push_warteschlange (kalender_id, ausser_person, titel, text, termin_id)
        values (new.kalender_id, auth.uid(), 'Termin verschoben',
                trim(wer) || ' jetzt ' || to_char(new.datum,'DD.MM.') || ' um ' || to_char(new.zeit,'HH24:MI'), new.id);
      delete from push_warteschlange
        where termin_id = new.id and gesendet is null and titel = 'Gleich losfahren';
      insert into push_warteschlange (kalender_id, titel, text, termin_id, faellig)
        values (new.kalender_id, 'Gleich losfahren',
                trim(wer) || ' um ' || to_char(new.zeit,'HH24:MI') || ' in ' || coalesce(new.ort,'?'),
                new.id, termin_zeitpunkt(new.datum, new.zeit) - interval '60 minutes');
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
    -- Kundenerinnerung neu setzen, wenn sich Zeit, Wahl oder Status geändert hat
    if (new.datum, new.zeit, new.kunde_erinnern, new.status)
       is distinct from (old.datum, old.zeit, old.kunde_erinnern, old.status) then
      perform kunden_erinnerung_setzen(new);
    end if;
    return new;
  end if;
  return null;
end $$;

drop trigger if exists termin_push on termine;
create trigger termin_push after insert or update on termine
  for each row execute function push_bei_termin();

-- 5) Einbau-Erinnerung am Vortag um 18 Uhr, ebenfalls in deutscher Zeit
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
  insert into push_warteschlange (kalender_id, titel, text, termin_id, faellig)
    values (new.kalender_id, 'Morgen Einbau',
            wer || ' um ' || to_char(new.zeit,'HH24:MI') || ' in ' || coalesce(new.ort,'?'),
            new.id, termin_zeitpunkt(new.datum - 1, time '18:00'));
  return new;
end $$;

-- 6) Erinnerungen, die schon in der Warteschlange stehen, auf die richtige Zeit setzen
update push_warteschlange w
   set faellig = termin_zeitpunkt(t.datum, t.zeit) - interval '60 minutes'
  from termine t
 where w.termin_id = t.id and w.gesendet is null and w.titel = 'Gleich losfahren';

update push_warteschlange w
   set faellig = termin_zeitpunkt(t.datum - 1, time '18:00')
  from termine t
 where w.termin_id = t.id and w.gesendet is null and w.titel = 'Morgen Einbau';

-- 7) Kontrolle
select 'Zeitzone der Datenbank' as was, current_setting('TimeZone') as wert
union all
select 'Neue Felder in termine', count(*)::text from information_schema.columns
 where table_name = 'termine' and column_name in ('anrede','kunde_erinnern','bestaetigt_am','bestaetigt_von')
union all
select 'Neue Felder in kalender', count(*)::text from information_schema.columns
 where table_name = 'kalender' and column_name in ('telefon','anrede')
union all
select 'Offene Losfahr-Erinnerungen', count(*)::text from push_warteschlange
 where gesendet is null and titel = 'Gleich losfahren';
