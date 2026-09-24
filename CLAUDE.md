# Setterboard

Terminkalender für das Setting im Pflegekassen-Geschäft. Setter telefonieren Werbe-Leads
ab und tragen Hausbesuche in den Kalender eines Closers ein, der zu den Kunden fährt.

Live: https://eljas-webstar.github.io/Setterboard/
Repo: git@github-setterboard:Eljas-Webstar/Setterboard.git (Deploy Key, Push direkt möglich)

## Aufbau

Eine einzige HTML-Datei, kein Build-Schritt, Vanilla JS in einer IIFE.

| Datei | Zweck |
|---|---|
| `index.html` | die ganze App |
| `sw.js` | Hintergrunddienst für Push und Homescreen |
| `manifest.webmanifest`, `icon-*.png` | App-Symbol und Start als App |
| `sql/` | alles, was im Supabase SQL Editor läuft |
| `funktion/push-senden.ts` | Edge Function, verschickt die Mitteilungen |
| `docs/push-einrichten.md` | Anleitung, ohne Schlüssel |

Seit dem Aufräumen am 22.09.2026 gibt es keine getrennte Arbeitskopie mehr.
Gebaut wird direkt in `index.html` in diesem Ordner, veröffentlicht mit `./hochladen.sh`.
Der Projektordner liegt unter `/Users/Eljakim/Downloads/setterboard/`.
`setterboard-lokal.html` ist ein Altstand von Mitte September, nicht anfassen.

## Supabase

Projekt `zdacotoynkvzlagwfdxp`, Region Frankfurt. In der App stehen nur die
Projektadresse, der publishable key und der öffentliche Push-Schlüssel.
service_role key und privater Push-Schlüssel gehören ausschließlich in Supabase.

Tabellen: `kalender`, `personen`, `termine`, `sperrtage`, `ereignisse`,
`push_geraete`, `push_warteschlange`, `anfragen`, `einladungen`.
Zugriff über RLS, Hilfsfunktionen `mein_kalender()` und `bin_admin()`.

Benutzername wird intern zu `benutzer@setterboard.local`.

## Rollen und Freigabe (Stand 21.09.2026)

Jeder legt sich seinen Zugang selbst an und wählt dabei die Rolle.

| Rolle | Kalender | Kommt rein, sobald |
|---|---|---|
| Setter | fremder | ein Closer die Anfrage annimmt |
| Closer | eigener | ein Admin freigibt |
| Applikateur | eigener | ein Admin freigibt |
| Verwaltung | keiner, sieht alles | ein Admin freigibt |

Closer und Applikateur geben ihre Startadresse schon bei der Anmeldung an, sie landet
in `personen.wunsch_strasse/_plz/_ort`. Beim Freigeben legt der Admin-Client daraus
den Kalender an und leert die Wunschfelder.

`personen.freigegeben` steuert das Tor. Wichtig: der Trigger `personen_schutz`
verbietet jedem außer dem Admin, `rolle` oder `freigegeben` zu ändern. Ohne den
könnte sich jeder Setter über die Browserkonsole selbst zum Admin machen.
Die Insert-Policy lässt `admin` als Wunschrolle gar nicht erst zu.

SQL dazu: `sql/setterboard-freigabe.sql`, setzt `sql/setterboard-monteure.sql` voraus.

**Wortwahl:** Was der Nutzer als **Applikateur** sieht, heißt in der Datenbank weiter
`monteur` (Rolle, Spalte `auftraege.monteur_kalender`, Funktion `istMonteur()`).
Umbenannt wurde nur die Oberfläche, weil Constraint, Policies und Trigger daran hängen.
Neue Texte also immer Applikateur, neuer Code weiter `monteur`.

## Fallen, die schon einmal Zeit gekostet haben

- **Edge Function heißt in der Adresse `pusch-senden`**, angezeigt wird `push-senden`.
  Der Cronjob muss auf die Adresse zeigen, sonst 404.
- **Verify JWT ist bei der Funktion aus**, der Zeitplan ruft ohne Schlüssel auf.
- **VAPID_MAIL muss eine echte Domain haben.** Mit `mailto:info@setterboard.local`
  antwortet Apple mit `403 BadJwtToken` und nichts kommt an. Jetzt steht
  `mailto:tempjo91@gmail.com` in den Secrets.
- **Die Sendefunktion verschluckte Fehler.** Seit Version 3 schreibt sie
  `zugestellt` und `fehler` in `push_warteschlange` und gibt einen Bericht zurück.
  Aufruf mit `?pruefen=1` zeigt, ob die Secrets ankommen.
- **Geräte hängen am Kalender, nicht am Menschen.** Wer an Kalender A hängt,
  bekommt nichts aus Kalender B. Bei "kommt nichts an" immer zuerst
  `push_geraete.kalender_id` gegen `push_warteschlange.kalender_id` prüfen.

## Offen, für später vorgemerkt

**Route und Fahrzeit über einen echten Dienst.** Heute ist beides selbst gerechnet:
Luftlinie mal Umwegfaktor, Tempo nach Entfernung gestaffelt. Kein Verkehr, keine echten Straßen.
Der Knopf "Losfahren" öffnet nur Maps mit dem Ziel, den Startpunkt setzt die Karten-App selbst.
Was fehlt:
- Standort des Geräts abfragen und als echten Start verwenden, mit dem hinterlegten
  Startpunkt als Rückfall, wenn der Nutzer den Zugriff verweigert
- echte Fahrzeit mit Stau, dafür braucht es die Google Routes API oder einen
  vergleichbaren Dienst, kostenpflichtig ab einer gewissen Zahl von Abfragen
- die Fahrzeitwarnung im Kalender würde dann auf echten Werten beruhen statt auf einer Schätzung
Vor der Umsetzung klären, wie viele Abfragen am Tag anfallen und was das kostet.

## Eigener Supabase-Zugang

Token liegt in `~/.config/setterboard/.env` (`SUPABASE_PAT`, `SUPABASE_REF`).
Lesen per Management API:

```bash
set -a; . ~/.config/setterboard/.env; set +a
curl -s -X POST "https://api.supabase.com/v1/projects/$SUPABASE_REF/database/query" \
  -H "Authorization: Bearer $SUPABASE_PAT" -H "Content-Type: application/json" \
  -d '{"query":"select ..."}'
```

Funktion neu deployen:

```bash
curl -s -X POST "https://api.supabase.com/v1/projects/$SUPABASE_REF/functions/deploy?slug=pusch-senden" \
  -H "Authorization: Bearer $SUPABASE_PAT" \
  -F 'metadata={"name":"push-senden","entrypoint_path":"source/index.ts","verify_jwt":false};type=application/json' \
  -F "file=@setterboard-funktion/index.ts;filename=source/index.ts;type=application/typescript"
```

Schreibende SQL-Befehle blockt der Auto-Modus. Die führt Eljakim im SQL Editor aus.
- **Klassennamen prüfen, bevor neue vergeben werden.** `.marke` gab es doppelt,
  die Überschrift bekam den Chip-Hintergrund.
- **Beim Ausschneiden großer Blöcke mit Python-Indexen** kann ein ganzer Abschnitt
  verschwinden oder sich verdoppeln. Danach immer prüfen, welche Funktionen fehlen:
  `python3` Regex über `^function (\w+)` im alten und neuen Stand vergleichen.
- **Anmeldung pro Fenster:** zwei Supabase-Clients, einer auf localStorage,
  einer auf sessionStorage mit eigenem storageKey. `signOut` immer mit
  `scope:"local"`, sonst fliegt das Handy mit raus.
- **Store greift auf die globale Variable `sb` zu**, ein Client-Wechsel wirkt
  deshalb sofort, ohne Neuaufbau.

## Testen

Lokaler Server über `.claude/launch.json` (python http.server auf 8765),
Testkopie nach `scratchpad/web/sb.html`. Für zwei Rollen gleichzeitig zwei Tabs,
im zweiten unter Zugänge auf "Hier anderes Konto".

Testzugänge: `testfenster` und `testsetter2`, Passwort `Test123456`.
Beide löschen, sobald sie nicht mehr gebraucht werden.
