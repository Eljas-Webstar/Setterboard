-- Setterboard: zweite Person mit Pflegegrad im Haushalt
-- Im SQL Editor einfügen und auf Run drücken. Kann mehrfach laufen.
alter table termine add column if not exists haushalt text;   -- ja, nein oder leer = nicht gefragt

select 'Feld haushalt' as was, count(*)::text as wert from information_schema.columns
 where table_name = 'termine' and column_name = 'haushalt';
