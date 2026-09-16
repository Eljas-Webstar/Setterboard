// Setterboard: verschickt die Mitteilungen aus der Warteschlange.
// Läuft als Supabase Edge Function unter der Adresse "pusch-senden".

import { createClient } from "jsr:@supabase/supabase-js@2";
import webpush from "npm:web-push@3.6.7";

const URL_SB = Deno.env.get("SUPABASE_URL")!;
const DIENST = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const OEFFENTLICH = Deno.env.get("VAPID_PUBLIC")!;
const GEHEIM = Deno.env.get("VAPID_PRIVATE")!;
const ABSENDER = Deno.env.get("VAPID_MAIL") ?? "mailto:info@setterboard.local";

const db = createClient(URL_SB, DIENST, { auth: { persistSession: false } });

Deno.serve(async (req) => {
  // Aufruf mit ?pruefen=1 meldet nur, ob die Schlüssel da sind
  const adresse = new URL(req.url);
  if (adresse.searchParams.get("pruefen")) {
    return new Response(JSON.stringify({
      vapid_public: OEFFENTLICH ? OEFFENTLICH.slice(0, 12) + "…" : "FEHLT",
      vapid_private: GEHEIM ? "gesetzt" : "FEHLT",
      absender: ABSENDER,
    }), { headers: { "Content-Type": "application/json" } });
  }

  if (!OEFFENTLICH || !GEHEIM) {
    return new Response(JSON.stringify({ fehler: "VAPID_PUBLIC oder VAPID_PRIVATE fehlt in den Secrets" }), { status: 500 });
  }
  webpush.setVapidDetails(ABSENDER, OEFFENTLICH, GEHEIM);

  const jetzt = new Date().toISOString();
  const { data: offen, error } = await db
    .from("push_warteschlange")
    .select("*")
    .is("gesendet", null)
    .lte("faellig", jetzt)
    .order("id")
    .limit(50);

  if (error) return new Response(JSON.stringify({ fehler: error.message }), { status: 500 });
  if (!offen?.length) return new Response(JSON.stringify({ gesendet: 0, hinweis: "nichts faellig" }), { status: 200 });

  const bericht: unknown[] = [];

  for (const n of offen) {
    const { data: geraete } = await db
      .from("push_geraete").select("*").eq("kalender_id", n.kalender_id);

    let ok = 0;
    const fehler: string[] = [];

    for (const g of geraete ?? []) {
      if (n.ausser_person && g.person_id === n.ausser_person) continue;

      const nutzlast = JSON.stringify({
        titel: n.titel, text: n.text,
        termin: n.termin_id ?? "",
        tag: n.termin_id ? ("t-" + n.termin_id) : undefined,
      });

      try {
        await webpush.sendNotification(
          { endpoint: g.endpunkt, keys: { p256dh: g.p256dh, auth: g.auth } },
          nutzlast,
        );
        ok++;
      } catch (e) {
        const code = (e as { statusCode?: number }).statusCode;
        const text = (e as { body?: string }).body || (e as Error).message || String(e);
        fehler.push((code ?? "?") + ": " + String(text).slice(0, 160));
        if (code === 404 || code === 410) {
          await db.from("push_geraete").delete().eq("endpunkt", g.endpunkt);
        }
      }
    }

    await db.from("push_warteschlange").update({
      gesendet: new Date().toISOString(),
      zugestellt: ok,
      fehler: fehler.length ? fehler.join(" | ") : null,
    }).eq("id", n.id);

    bericht.push({ id: n.id, titel: n.titel, geraete: (geraete ?? []).length, zugestellt: ok, fehler });
  }

  await db.from("push_warteschlange").delete()
    .not("gesendet", "is", null)
    .lt("gesendet", new Date(Date.now() - 7 * 864e5).toISOString());

  return new Response(JSON.stringify({ verarbeitet: offen.length, bericht }, null, 2), {
    headers: { "Content-Type": "application/json" },
  });
});
