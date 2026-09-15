# Setterboard

Terminkalender für das Setting im Pflegekassen-Geschäft. Setter tragen
Hausbesuche in den Kalender eines Closers ein, der zu den Kunden fährt.

Live: https://eljas-webstar.github.io/Setterboard/

## Was hier liegt

- `index.html` ist die ganze App, eine einzige Datei.
- `sw.js`, `manifest.webmanifest`, `icon-*.png` machen daraus eine App
  für den Home-Bildschirm und ermöglichen Mitteilungen.
- `sql/` enthält alles, was in Supabase unter SQL Editor ausgeführt wird.
- `funktion/push-senden.ts` ist die Edge Function, die Mitteilungen verschickt.
- `docs/push-einrichten.md` beschreibt die Einrichtung der Mitteilungen.
- `setterboard-lokal.html` ist die alte Fassung ohne Datenbank, nur zum Anschauen.

## Ändern

`index.html` bearbeiten, hochladen, fertig. GitHub Pages aktualisiert die
Seite von allein. Daten und Zugänge liegen in Supabase, nicht hier.

## Keine Geheimnisse hier hinein

In der `index.html` stehen nur die öffentliche Projektadresse, der
publishable key und der öffentliche Push-Schlüssel. Alles Geheime,
also service_role key und der private Push-Schlüssel, gehört
ausschließlich in die Einstellungen von Supabase.
