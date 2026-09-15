// Setterboard: verschickt die Mitteilungen aus der Warteschlange.
// Läuft als Supabase Edge Function mit dem Namen "push-senden".

import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.4";
import webpush from "https://esm.sh/web-push@3.6.7";

const URL_SB = Deno.env.get("SUPABASE_URL")!;
const DIENST = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const OEFFENTLICH = Deno.env.get("VAPID_PUBLIC")!;
const GEHEIM = Deno.env.get("VAPID_PRIVATE")!;
const ABSENDER = Deno.env.get("VAPID_MAIL") ?? "mailto:info@setterboard.local";

webpush.setVapidDetails(ABSENDER, OEFFENTLICH, GEHEIM);
const db = createClient(URL_SB, DIENST, { auth: { persistSession: false } });

Deno.serve(async () => {
  const jetzt = new Date().toISOString();

  const { data: offen, error } = await db
    .from("push_warteschlange")
    .select("*")
    .is("gesendet", null)
    .lte("faellig", jetzt)
    .order("id")
    .limit(50);

  if (error) return new Response(JSON.stringify({ fehler: error.message }), { status: 500 });
  if (!offen?.length) return new Response(JSON.stringify({ gesendet: 0 }), { status: 200 });

  let zaehler = 0;

  for (const n of offen) {
    const { data: geraete } = await db
      .from("push_geraete")
      .select("*")
      .eq("kalender_id", n.kalender_id);

    for (const g of geraete ?? []) {
      if (n.ausser_person && g.person_id === n.ausser_person) continue;   // Absender selbst nicht

      const nutzlast = JSON.stringify({
        titel: n.titel,
        text: n.text,
        termin: n.termin_id ?? "",
        tag: n.termin_id ? ("t-" + n.termin_id) : undefined,
      });

      try {
        await webpush.sendNotification(
          { endpoint: g.endpunkt, keys: { p256dh: g.p256dh, auth: g.auth } },
          nutzlast,
        );
        zaehler++;
      } catch (e) {
        const code = (e as { statusCode?: number }).statusCode;
        // 404 und 410 heißen: dieses Gerät gibt es nicht mehr
        if (code === 404 || code === 410) {
          await db.from("push_geraete").delete().eq("endpunkt", g.endpunkt);
        }
      }
    }

    await db.from("push_warteschlange").update({ gesendet: new Date().toISOString() }).eq("id", n.id);
  }

  // Warteschlange sauber halten
  await db.from("push_warteschlange").delete()
    .not("gesendet", "is", null)
    .lt("gesendet", new Date(Date.now() - 7 * 864e5).toISOString());

  return new Response(JSON.stringify({ gesendet: zaehler }), {
    headers: { "Content-Type": "application/json" },
  });
});
