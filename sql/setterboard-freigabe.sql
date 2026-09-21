-- Setterboard: Jeder meldet sich selbst an, Admin gibt frei
-- Im SQL Editor einfügen und auf Run drücken. Kann mehrfach laufen.
-- Setzt voraus, dass setterboard-monteure.sql schon gelaufen ist.

-- 1) Neue Felder in personen
alter table personen add column if not exists freigegeben boolean not null default false;
alter table personen add column if not exists wunsch_strasse text;
alter table personen add column if not exists wunsch_plz text;
alter table personen add column if not exists wunsch_ort text;

-- Alle, die es heute schon gibt, sind freigegeben
update personen set freigegeben = true where freigegeben = false;

-- 2) Rollen: admin bleibt dem Admin vorbehalten, die vier anderen kann man wählen
alter table personen drop constraint if exists personen_rolle_check;
alter table personen add constraint personen_rolle_check
  check (rolle in ('admin','verwaltung','closer','setter','monteur'));

-- 3) Selbstanlage: Rolle frei wählbar, aber niemals admin und niemals selbst freigegeben.
--    Setter braucht keine Admin-Freigabe, er wartet auf die Zusage seines Closers.
drop policy if exists personen_selbstanlage on personen;
create policy personen_selbstanlage on personen for insert to authenticated
  with check (
    id = auth.uid()
    and kalender_id is null
    and (
      (rolle = 'setter' and freigegeben = true)
      or (rolle in ('closer','monteur','verwaltung') and freigegeben = false)
    )
  );

-- 4) Rolle und Freigabe darf nur ein Admin ändern.
--    Ohne das könnte sich jeder im Browser selbst zum Admin machen.
create or replace function personen_schutz() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null or bin_admin() then return new; end if;
  if new.rolle is distinct from old.rolle then
    raise exception 'Die Rolle vergibt nur ein Admin.';
  end if;
  if new.freigegeben is distinct from old.freigegeben then
    raise exception 'Die Freigabe erteilt nur ein Admin.';
  end if;
  return new;
end $$;

drop trigger if exists personen_schutz_trigger on personen;
create trigger personen_schutz_trigger before update on personen
  for each row execute function personen_schutz();

-- 5) Kalenderliste für die Closer-Auswahl: nur freigegebene Closer.
--    Vorher standen dort auch Monteurkalender drin.
create or replace function kalender_liste()
returns table (id uuid, name text)
language sql stable security definer set search_path = public as $$
  select k.id, k.name from kalender k
   where exists (
     select 1 from personen p
      where p.kalender_id = k.id and p.rolle = 'closer' and p.freigegeben
   )
   order by k.name
$$;
revoke all on function kalender_liste() from public;
grant execute on function kalender_liste() to authenticated;

-- 6) Wer wartet auf Freigabe. Liest der Admin, sonst niemand.
create or replace function freigabe_liste()
returns table (id uuid, name text, rolle text, strasse text, plz text, ort text, angelegt timestamptz)
language sql stable security definer set search_path = public as $$
  select p.id, p.name, p.rolle, p.wunsch_strasse, p.wunsch_plz, p.wunsch_ort, p.angelegt
    from personen p
   where p.freigegeben = false and bin_admin()
   order by p.angelegt
$$;
revoke all on function freigabe_liste() from public;
grant execute on function freigabe_liste() to authenticated;

-- 7) Mitteilung an jeden Admin, sobald sich jemand anmeldet und wartet
create or replace function push_bei_freigabewunsch() returns trigger
language plpgsql security definer set search_path = public as $$
declare was text;
begin
  if new.freigegeben then return new; end if;
  was := case new.rolle
           when 'closer' then 'Closer'
           when 'monteur' then 'Monteur'
           when 'verwaltung' then 'Verwaltung'
           else new.rolle end;
  insert into push_warteschlange (kalender_id, ausser_person, titel, text)
    select p.kalender_id, new.id, 'Neue Anmeldung',
           new.name || ' will als ' || was || ' dazu und wartet auf deine Freigabe'
      from personen p
     where p.rolle = 'admin' and p.kalender_id is not null;
  return new;
end $$;

drop trigger if exists freigabewunsch_push on personen;
create trigger freigabewunsch_push after insert on personen
  for each row execute function push_bei_freigabewunsch();

-- 8) Kontrolle
select 'Wartet auf Freigabe' as was, count(*)::text as wert from personen where freigegeben = false
union all
select 'Freigegeben', count(*)::text from personen where freigegeben = true
union all
select 'Closer in der Auswahl', count(*)::text from kalender_liste();
