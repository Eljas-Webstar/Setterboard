-- Schritt 3: dich zum Admin machen
-- Erst in der App einen Zugang anlegen, DANN das hier ausführen.
-- "eljakim" durch deinen gewählten Benutzernamen ersetzen, falls anders.

update personen
set rolle = 'admin'
where id = (select id from auth.users where email = 'eljakim@setterboard.local');

-- Prüfen, ob es geklappt hat:
select p.name, p.rolle, u.email
from personen p join auth.users u on u.id = p.id;

-- Falls du das Probekonto loswerden willst:
-- delete from auth.users where email = 'probe@setterboard.local';
