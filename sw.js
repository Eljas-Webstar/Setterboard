/* Setterboard: Servicearbeiter für Push und Homescreen */
self.addEventListener("install", function(e){ self.skipWaiting(); });
self.addEventListener("activate", function(e){ e.waitUntil(self.clients.claim()); });

self.addEventListener("push", function(e){
  var d = {};
  try { d = e.data ? e.data.json() : {}; } catch(err){ d = { titel:"Setterboard", text: e.data ? e.data.text() : "" }; }
  var titel = d.titel || "Setterboard";
  var opt = {
    body: d.text || "",
    icon: "icon-192.png",
    badge: "icon-192.png",
    tag: d.tag || undefined,
    renotify: !!d.tag,
    data: { termin: d.termin || "", pfad: d.pfad || "./" }
  };
  e.waitUntil(self.registration.showNotification(titel, opt));
});

self.addEventListener("notificationclick", function(e){
  e.notification.close();
  var id = (e.notification.data && e.notification.data.termin) || "";
  // "Kunden erinnern" öffnet das Fenster mit Anrufen und SMS statt den Termin
  var erinnern = (e.notification.title === "Kunden erinnern");
  var anker = id ? ((erinnern ? "#erinnern=" : "#termin=") + id) : "";
  var ziel = new URL("./" + anker, self.location.href).href;
  e.waitUntil(
    self.clients.matchAll({ type:"window", includeUncontrolled:true }).then(function(liste){
      for (var i=0; i<liste.length; i++){
        var c = liste[i];
        if (c.url.indexOf(self.registration.scope) === 0 && "focus" in c){
          c.postMessage({ art:(erinnern ? "erinnern-oeffnen" : "termin-oeffnen"), id:id });
          return c.focus();
        }
      }
      return self.clients.openWindow(ziel);
    })
  );
});
