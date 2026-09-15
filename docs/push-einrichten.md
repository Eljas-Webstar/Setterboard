# Mitteilungen aufs Handy einrichten

Vier Schritte. Der erste ist schon erledigt, die Schlüssel sind erzeugt.

## Schritt 1: Schlüssel (erledigt)

Der öffentliche Schlüssel steht bereits in der App.

    VAPID_PUBLIC   <öffentlicher Schlüssel, steht in der index.html unter PUSH_KEY>
    VAPID_PRIVATE  <privater Schlüssel, liegt nur in Supabase unter Secrets>

Der private Schlüssel gehört nur auf den Server und nirgendwo sonst hin.
Nicht ins Repo, nicht in die HTML-Datei.

## Schritt 2: Tabellen anlegen

In Supabase unter **SQL Editor** die Datei `setterboard-push.sql` einfügen
und auf **Run** drücken. Das legt an:

- `push_geraete`, die angemeldeten Handys
- `push_warteschlange`, was verschickt werden soll
- Auslöser für neue, verschobene und abgesagte Termine, für Ergebnisse und gestrichene Tage
- die Erinnerung 60 Minuten vor dem Termin
- das Morgenbriefing um 7 Uhr

## Schritt 3: Sendefunktion anlegen

1. In Supabase links auf **Edge Functions**, dann **Deploy a new function**
   und **Via Editor**.
2. Als Namen genau `push-senden` eintragen.
3. Den Inhalt von `setterboard-funktion/index.ts` hineinkopieren, alles ersetzen.
4. Auf **Deploy** drücken.

Danach die beiden Schlüssel hinterlegen: **Edge Functions**, oben **Secrets**,
dann zwei Einträge anlegen.

    VAPID_PUBLIC    <öffentlicher Schlüssel, steht in der index.html unter PUSH_KEY>
    VAPID_PRIVATE   <privater Schlüssel, liegt nur in Supabase unter Secrets>

Wahlweise noch `VAPID_MAIL` mit deiner Mailadresse, die sehen nur die Push-Server.

## Schritt 4: Zeitplan einschalten

Ganz unten in `setterboard-push.sql` steht ein auskommentierter Block.
Die Kommentarzeichen entfernen und zwei Werte einsetzen:

- `PROJEKT` wird zu `zdacotoynkvzlagwfdxp`
- `DIENSTSCHLUESSEL` ist der **service_role key** aus
  **Project Settings**, **API Keys**. Der ist geheim, nur hier verwenden.

Dann diesen Block im SQL Editor ausführen. Ab jetzt schaut der Server alle
fünf Minuten in die Warteschlange und verschickt, was fällig ist.

## Prüfen, ob es läuft

1. Die Seite auf dem Handy öffnen, bei iPhone vorher über Teilen
   **Zum Home-Bildschirm** hinzufügen und von dort starten.
2. Unten auf **Kalender**, oben rechts auf den eigenen Namen, dann
   **Mitteilungen einschalten** und die Nachfrage des Handys erlauben.
3. Am Rechner einen Termin eintragen. Innerhalb von fünf Minuten kommt
   die Mitteilung. Antippen öffnet genau diesen Termin.

Wenn nichts kommt: In Supabase unter **Edge Functions** auf `push-senden`
und dort in die **Logs** schauen. Meistens fehlt eines der beiden Secrets.

## Was verschickt wird

Mitteilung bekommen alle, die im selben Kalender arbeiten, außer dem,
der die Änderung selbst gemacht hat.

- Neuer Termin
- Termin verschoben
- Termin abgesagt
- Ergebnis eingetragen
- Tag gestrichen
- Erinnerung 60 Minuten vor dem Termin
- Morgens um 7 die Übersicht des Tages an den Closer

Nur im Verlauf, ohne Mitteilung: Notiz, Stichworte, Pflegegrad, Telefonnummer.
