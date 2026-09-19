#!/bin/zsh
# Setterboard veröffentlichen: Version stempeln, zu All-Inkl laden, ins Repo sichern.
# Aufruf:  ./hochladen.sh "Was geändert wurde"
set -e
cd "$(dirname "$0")"
set -a; . ~/.config/setterboard/.env; set +a

QUELLE="/Users/Eljakim/Downloads/setterboard-supabase.html"
STAND=$(date +%Y-%m-%d-%H%M)

# Versionsnummer in die Datei stempeln und als version.txt ablegen
python3 - "$QUELLE" "$STAND" <<'PY'
import re, sys
pfad, stand = sys.argv[1], sys.argv[2]
s = open(pfad, encoding='utf-8').read()
if not re.search(r'var VERSION = "[^"]*";', s): raise SystemExit("VERSION nicht gefunden")
neu = re.sub(r'var VERSION = "[^"]*";', 'var VERSION = "%s";' % stand, s, count=1)
open(pfad, 'w', encoding='utf-8').write(neu)
PY
# Versionsdatei mit den Punkten, die im Feed erscheinen.
# Aufruf:  ./hochladen.sh "Titel" "Punkt eins" "Punkt zwei" ...
python3 - "$STAND" "$@" <<'PY2'
import json, sys
stand = sys.argv[1]
punkte = [p for p in sys.argv[3:] if p.strip()]
if not punkte and len(sys.argv) > 2: punkte = [sys.argv[2]]
json.dump({"stand": stand, "punkte": punkte}, open("version.json","w",encoding="utf-8"), ensure_ascii=False)
PY2
echo "$STAND" > version.txt
cp "$QUELLE" index.html

for f in index.html sw.js manifest.webmanifest icon-192.png icon-512.png version.json version.txt .htaccess; do
  [ -f "$f" ] || continue
  curl -s --ssl-reqd -T "$f" "ftp://$FTP_HOST/setterboard.de/$f" -u "$FTP_USER:$FTP_PASS" -o /dev/null \
    -w "$f %{http_code}  "
done
echo
echo "Stand $STAND ist auf https://setterboard.de"

git add -A
git commit -q -m "${1:-Aktualisierung} (Stand $STAND)

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>" || echo "nichts zu committen"
git push -q origin main
