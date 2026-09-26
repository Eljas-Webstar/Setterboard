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

## Route und Adressprüfung (Stand 24.09.2026)

**Losfahren** öffnet die Karten-App ohne Startpunkt, dadurch setzt sie selbst
"Mein Standort" ein und rechnet die Fahrzeit mit aktuellem Verkehr. Dafür braucht
es keine kostenpflichtige Schnittstelle. Auf dem iPhone versucht `routeStarten()`
zuerst `comgooglemaps://` und springt nach 800 ms auf Apple Maps, falls die
Google-Maps-App fehlt. Erkannt wird das über `visibilitychange`.

**Adressprüfung** im Terminformular, `adrPruefen()`:
1. Nominatim strukturiert (street, postalcode, city, countrycodes=de)
2. Straßenname gleich? Dann grüner Haken
3. Andere Treffer? Als Vorschläge anbieten
4. Nichts gefunden? Photon (komoot) mit lat/lon aus der eigenen PLZ-Tabelle,
   das verträgt Tippfehler
5. Vorschläge werden sortiert: gleiche PLZ zuerst, dann nach `abstand()`,
   einer Levenshtein-Distanz über normalisierte Straßennamen (`str` = `straße`)

Beide Dienste sind kostenlos und ohne Schlüssel, Grenze etwa eine Anfrage je Sekunde.
Gesucht wird erst ab Hausnummer und Ortsangabe, verzögert um 900 ms.
Übermittelt wird nur die Adresse, kein Name und kein Pflegegrad.

Echter Fall aus dem Test: "Am Markt 3, 31515 Wunstorf" gibt es nicht.
Google Maps biegt stillschweigend auf Gehrden um, die Prüfung schlägt
"Am Alten Markt 3, 31515 Wunstorf" vor.

## Terminbestätigung und Kundenerinnerung (Stand 26.09.2026)

- Nach dem Speichern (neu oder Zeit geändert) öffnet `bestaetigungOeffnen()` den Text vom
  Setter an den Kunden. WhatsApp über `wa.me`, SMS über `sms:`, Kopieren als Rückfall.
  `istHandynummer()` erkennt Festnetz (alles außer 015/016/017).
- `termine.kunde_erinnern` = Minuten vor dem Termin. Der Auslöser legt eine Mitteilung
  "Kunden erinnern" an den Closer an. `sw.js` erkennt den Titel und öffnet `#erinnern=<id>`,
  dort sind Anrufen und fertige SMS.
- Bestätigt wird über `store.markBestaetigt()`, bewusst nicht über `terminInDb()`,
  sonst überschreibt ein älterer Stand auf einem anderen Gerät das Feld mit leer.
- Closer tragen Anrede und Handynummer in den Einstellungen ein, Spalten
  `kalender.telefon` und `kalender.anrede`.

**Falle Zeitzone:** Die Datenbank läuft auf UTC. `datum + zeit` ist deutsche Zeit.
Immer über `termin_zeitpunkt(datum, zeit)` rechnen, das wandelt nach Europe/Berlin um.
Bis zum 26.09. kam "Gleich losfahren" dadurch eine Stunde nach Terminbeginn.

**Offen aus der Recherche 26.09.:** Nominatim verbietet Suche beim Tippen, der öffentliche
Overpass-Server ist nicht für gewerbliche Nutzung. Ersatz geplant: Straßenverzeichnis der
eigenen PLZ einmal herunterladen und mitliefern. Supabase Free hat kein nutzbares Backup
und pausiert nach einer Woche ohne Nutzung.

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
