-- Nachtrag: Erstanlage ermöglichen
-- Im SQL Editor einfügen und auf Run drücken.

-- Ein angemeldeter Nutzer darf einen Kalender anlegen.
-- Sehen kann er danach trotzdem nur seinen eigenen.
drop policy if exists kalender_anlegen on kalender;
create policy kalender_anlegen on kalender
  for insert to authenticated
  with check (true);

-- Ein angemeldeter Nutzer darf seine eigene Zeile anlegen,
-- aber nur als Closer oder Setter. Die Adminrolle vergibt nur ein Admin.
drop policy if exists personen_selbst on personen;
create policy personen_selbst on personen
  for insert to authenticated
  with check (id = auth.uid() and rolle in ('closer','setter'));
