-- Selbstanlage schliessen.
-- Erst ausfuehren, wenn dein Adminzugang funktioniert.
-- Danach kann sich niemand mehr selbst einen Kalender oder eine Rolle geben.
-- Zugaenge legen nur noch Admin und Closer aus der App heraus an.

drop policy if exists kalender_anlegen on kalender;
drop policy if exists personen_selbst on personen;

-- Kontrolle: hier sollten die beiden Regeln nicht mehr auftauchen
select tablename, policyname from pg_policies
where tablename in ('kalender','personen') order by tablename, policyname;
