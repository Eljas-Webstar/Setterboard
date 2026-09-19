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
echo "$STAND" > version.txt
cp "$QUELLE" index.html

for f in index.html sw.js manifest.webmanifest icon-192.png icon-512.png version.txt .htaccess; do
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
