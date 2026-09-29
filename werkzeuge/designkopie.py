#!/usr/bin/env python3
"""Baut aus index.html eine Designkopie zum Tüfteln.

Die Kopie spricht mit keiner Datenbank. Statt Supabase steckt ein Ersatzspeicher mit
ausgedachten Kunden drin, man ist automatisch angemeldet und kann die Rolle umschalten.
Aufruf:  python3 werkzeuge/designkopie.py ZIELDATEI
"""
import io, sys, os

quelle = os.path.join(os.path.dirname(__file__), "..", "index.html")
ziel = sys.argv[1] if len(sys.argv) > 1 else "setterboard-design.html"
s = io.open(quelle, encoding="utf-8").read()

def rep(a, b):
    global s
    assert s.count(a) == 1, ("nicht eindeutig", a[:70], s.count(a))
    s = s.replace(a, b)

# Keine Datenbank, kein Hintergrunddienst
rep('<script src="https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2.45.4/dist/umd/supabase.min.js"></script>\n', '')
rep('<title>Setterboard</title>', '<title>Setterboard Design</title>')

# Jeder übrig gebliebene Datenbankaufruf läuft ins Leere statt abzustürzen
rep('var sb = FENSTER_MODUS ? fensterClient() : sbHaupt;',
    'var sb = FENSTER_MODUS ? fensterClient() : sbHaupt;\nif(!sb) sb = attrappe();')

rep('renderGate(); wire(); claudeDb(); PUSH.start();', 'renderGate(); wire(); demoStart();')

DEMO = r'''
/* ================= Designkopie: Ersatz für die Datenbank =================
   Nur in der Designkopie. Ausgedachte Kunden, nichts verlässt diese Seite. */
function attrappe(){
  var p;
  var ergebnis={ data:null, error:null };
  p=new Proxy(function(){}, {
    get:function(t,k){
      if(k==="then") return function(ok,nein){ return Promise.resolve(ergebnis).then(ok,nein); };
      if(k==="catch") return function(){ return Promise.resolve(ergebnis); };
      return p;
    },
    apply:function(){ return p; }
  });
  return p;
}

var DEMO=null;
function demoDaten(){
  var mo=mondayOf(new Date());
  function tag(n){ return ymd(addDays(mo,n)); }
  var heute=ymd(new Date());
  var kalender=[
    { id:"k1", name:"Ben Penner", start_strasse:"Podbielskistraße 40", start_plz:"30177", start_ort:"Hannover", telefon:"0170 0000001", anrede:"Herr" },
    { id:"k2", name:"Tom Ruf", start_strasse:"Bahnhofstraße 9", start_plz:"31515", start_ort:"Wunstorf", telefon:"0170 0000002", anrede:"Herr" }
  ];
  var personen=[
    { id:"p1", name:"Ben Penner", rolle:"closer", kalender_id:"k1", benutzer:"ben" },
    { id:"p2", name:"Eljakim", rolle:"setter", kalender_id:"k1", benutzer:"eljakim" },
    { id:"p3", name:"Tom Ruf", rolle:"monteur", kalender_id:"k2", benutzer:"tom" },
    { id:"p4", name:"IFBA Büro", rolle:"verwaltung", kalender_id:null, benutzer:"ifba" },
    { id:"p5", name:"Admin", rolle:"admin", kalender_id:null, benutzer:"admin" }
  ];
  function t(id,d,zeit,an,vor,nach,str,plz,ort,pg,extra){
    var a={ id:id, closer:"Ben Penner", kalender_id:"k1", anrede:an, vorname:vor, nachname:nach,
      telefon:"0170 00000"+id.slice(-2), strasse:str, plz:plz, ort:ort, pflegegrad:pg, wohnform:"",
      notiz:"", hinweise:[], entscheider:false, papiere:false, datum:d, zeit:zeit, dauer:60,
      status:"geplant", setter:"Eljakim", updatedBy:"Eljakim", art:"beratung", haushalt:"",
      kundeErinnern:1440, bestaetigtAm:"", bestaetigtVon:"" };
    for(var k in (extra||{})) a[k]=extra[k];
    return a;
  }
  // Alle Uhrzeiten verschieden, weil heute auf jeden Wochentag fallen kann
  var termine=[
    t("t01",heute,"08:30","Frau","Ute","Schmitz","Am Alten Markt 3","31515","Wunstorf","3",
      { wohnform:"eigentum", entscheider:true, papiere:true, haushalt:"ja", bestaetigtAm:new Date().toISOString(), bestaetigtVon:"Eljakim",
        notiz:"Bad im Erdgeschoss, Fliesen hell. Tochter ist beim Termin dabei." }),
    t("t02",heute,"13:00","Herr","Klaus","Holle","Deisterstraße 7","30890","Barsinghausen","2",
      { wohnform:"miete", notiz:"Vermieter ist informiert, Zustimmung bringt der Sohn mit." }),
    t("t03",tag(1),"10:00","Frau","Renate","Vogt","Lange Straße 12","31535","Neustadt am Rübenberge","antrag"),
    t("t04",tag(2),"14:30","Herr","Heinz","Kramer","Göttinger Straße 20","30982","Pattensen","4",{ papiere:true }),
    t("t05",tag(2),"16:00","Frau","Gisela","Brandt","Hauptstraße 4","31832","Springe","2",{ entscheider:true }),
    t("t06",tag(3),"11:30","Herr","Werner","Albers","Bahnhofstraße 30","30926","Seelze","3"),
    t("t07",tag(-1),"10:00","Frau","Marianne","Otte","Marktstraße 5","30159","Hannover","2",{ status:"stattgefunden" }),
    t("t08",tag(8),"15:00","Herr","Friedrich","Lange","Kirchstraße 2","31515","Wunstorf","3"),
    t("t09",tag(4),"08:30","Frau","Hildegard","Meyer","Schulstraße 11","30890","Barsinghausen","3",
      { closer:"Tom Ruf", kalender_id:"k2", art:"einbau", setter:"", kundeErinnern:null })
  ];
  var jetzt=Date.now();
  var ereignisse=[
    { id:"e1", ts:jetzt-20*60000, by:"Eljakim", kind:"neu", text:"Neuer Termin: Ute Schmitz (PG 3) bei Ben Penner", apptId:"t01", kalender:"Ben Penner" },
    { id:"e2", ts:jetzt-3*3600000, by:"Ben Penner", kind:"status", text:"Marianne Otte hat stattgefunden", apptId:"t07", kalender:"Ben Penner" },
    { id:"e3", ts:jetzt-26*3600000, by:"Eljakim", kind:"verschoben", text:"Klaus Holle verschoben auf heute 13:00", apptId:"t02", kalender:"Ben Penner" }
  ];
  var auftraege=[
    { id:"a1", termin_id:"t07", kalender_id:"k1", vorname:"Marianne", nachname:"Otte", telefon:"0170 0000007",
      strasse:"Marktstraße 5", plz:"30159", ort:"Hannover", umfang:"Dusche", status:"beantragt",
      verkauft_von:"Ben Penner", gesetzt_von:"Eljakim", angelegt:new Date(jetzt-86400000).toISOString() },
    { id:"a2", termin_id:null, kalender_id:"k1", vorname:"Hildegard", nachname:"Meyer", telefon:"0170 0000009",
      strasse:"Schulstraße 11", plz:"30890", ort:"Barsinghausen", umfang:"Wanne", status:"terminiert",
      monteur_kalender:"k2", einbau_termin_id:"t09", verkauft_von:"Ben Penner", gesetzt_von:"Eljakim",
      angelegt:new Date(jetzt-9*86400000).toISOString() }
  ];
  return { kalender:kalender, personen:personen, termine:termine, ereignisse:ereignisse, auftraege:auftraege, sperr:[] };
}

function demoStore(d){
  var cb={};
  var P=function(x){ return Promise.resolve(x); };
  function team(){ return d.personen.map(function(p){ var m=personAusDb(p); m.benutzer=p.benutzer; return m; }); }
  function feuern(){
    if(cb.team) cb.team(team());
    if(cb.appts) cb.appts(d.termine.slice());
    if(cb.act) cb.act(d.ereignisse.slice().sort(function(a,b){ return b.ts-a.ts; }));
    if(cb.sperr) cb.sperr(d.sperr.slice());
  }
  function bald(){ setTimeout(feuern,0); }
  return {
    kind:"demo",
    onTeam:function(f){ cb.team=f; bald(); },
    onAppts:function(f){ cb.appts=f; bald(); },
    onActivity:function(f){ cb.act=f; bald(); },
    onSperr:function(f){ cb.sperr=f; bald(); },
    saveAppt:function(a){
      var c={}; for(var k in a) c[k]=a[k];
      if(!c.kalender_id) c.kalender_id=KAL_ID[c.closer]||"k1";
      d.termine=d.termine.filter(function(x){ return x.id!==a.id; }).concat([c]); bald(); return P({ id:a.id });
    },
    delAppt:function(id){ d.termine=d.termine.filter(function(x){ return x.id!==id; }); bald(); return P(); },
    auftragAnlegen:function(){ return P(); },
    auftraegeLaden:function(){ return P(d.auftraege.slice()); },
    auftragAendern:function(id,daten){
      d.auftraege.forEach(function(x){ if(x.id===id) for(var k in daten) x[k]=daten[k]; }); return P();
    },
    anfragenLaden:function(){ return P([]); },
    freigabenLaden:function(){ return P([]); },
    freigeben:function(){ return P(); },
    freigabeAblehnen:function(){ return P(); },
    anfrageEntscheiden:function(){ return P(); },
    einladungAnlegen:function(){ return P("DEMO1234"); },
    saveMember:function(){ return P(); },
    delMember:function(){ return P(); },
    addEvent:function(e){ d.ereignisse=[e].concat(d.ereignisse.filter(function(x){ return x.id!==e.id; })); bald(); return P(); },
    delEvent:function(){ return P(); },
    saveSperr:function(x){ d.sperr.push({ id:uid(), datum:x.datum, closer:x.closer, grund:x.grund||"", von:x.von||"" }); bald(); return P(); },
    delSperr:function(id){ d.sperr=d.sperr.filter(function(x){ return x.id!==id; }); bald(); return P(); },
    kalenderAnlegen:function(){ return P("k9"); },
    kalenderAendern:function(){ return P(); },
    kalenderKontakt:function(){ return P(); },
    markBestaetigt:function(){ return P(); }
  };
}

function demoRolle(r){
  var p=DEMO.personen.filter(function(x){ return x.rolle===r; })[0]; if(!p) return;
  var m=personAusDb(p); m.benutzer=p.benutzer;
  S.me=m; S.view="home";
  if(typeof closeOverlay==="function") closeOverlay();
  enterApp(); render();
}

function demoLeiste(){
  var el=document.createElement("div");
  el.className="demo-leiste";
  el.innerHTML='<span>Designkopie</span><select id="demoRolle" aria-label="Ansicht als">'+
    [["closer","als Closer"],["setter","als Setter"],["monteur","als Applikateur"],["verwaltung","als Verwaltung"],["admin","als Admin"]]
      .map(function(o){ return '<option value="'+o[0]+'">'+o[1]+'</option>'; }).join("")+'</select>';
  document.body.appendChild(el);
  $("demoRolle").onchange=function(){ demoRolle(this.value); };
  var st=document.createElement("style");
  st.textContent='.demo-leiste{position:fixed;left:10px;bottom:calc(78px + env(safe-area-inset-bottom));z-index:45;'+
    'display:flex;align-items:center;gap:6px;padding:4px 6px 4px 10px;border-radius:999px;'+
    'background:var(--surface);border:1px solid var(--line);box-shadow:var(--shadow);font-size:12px;font-weight:700;color:var(--ink-3)}'+
    '.demo-leiste select{font:inherit;font-size:13px;color:var(--ink);background:var(--surface-2);border:1px solid var(--line);border-radius:999px;padding:3px 8px}';
  document.head.appendChild(st);
}

function demoStart(){
  DEMO=demoDaten();
  KAL={}; KAL_ID={};
  DEMO.kalender.forEach(function(k){ KAL[k.id]=k; KAL_ID[k.name]=k.id; });
  store=demoStore(DEMO); S.offline=false;
  connect();
  demoRolle("closer");
  demoLeiste();
  setDiag("");
}
'''
rep('/* ---------------- boot ---------------- */', DEMO + '\n/* ---------------- boot ---------------- */')

io.open(ziel, "w", encoding="utf-8").write(s)
print("Designkopie geschrieben:", ziel, len(s), "Zeichen")
