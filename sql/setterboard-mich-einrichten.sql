-- Richtet ein bereits registriertes Konto als Admin mit eigenem Kalender ein.
-- Nur die drei Werte in der ersten Zeile anpassen, dann alles markieren und Run.

with vorgabe as (
  select
    'eljakim@setterboard.local'::text as mail,     -- dein Benutzername plus @setterboard.local
    'Eljakim'::text                  as anzeigename,
    '30159'::text                    as start_plz,
    'Hannover'::text                 as start_ort
),
nutzer as (
  select u.id, v.* from auth.users u, vorgabe v where u.email = v.mail
),
neuer_kalender as (
  insert into kalender (name, start_plz, start_ort)
  select anzeigename, start_plz, start_ort from nutzer
  returning id
)
insert into personen (id, name, rolle, kalender_id)
select n.id, n.anzeigename, 'admin', k.id from nutzer n, neuer_kalender k
on conflict (id) do update
  set rolle = 'admin',
      name = excluded.name,
      kalender_id = excluded.kalender_id;

-- Kontrolle: hier sollte dein Name mit der Rolle admin stehen
select p.name, p.rolle, u.email, k.name as kalender
from personen p
join auth.users u on u.id = p.id
left join kalender k on k.id = p.kalender_id;

-- Falls du sehen willst, welche Konten überhaupt existieren:
-- select email, created_at from auth.users order by created_at;
