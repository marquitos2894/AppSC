import { withSupabase } from "npm:@supabase/server";
import webpush from "npm:web-push@3.6.7";

const claveVapidPublica = Deno.env.get("VAPID_PUBLIC_KEY") ?? "";
const claveVapidPrivada = Deno.env.get("VAPID_PRIVATE_KEY") ?? "";
const contacto = Deno.env.get("VAPID_SUBJECT") ?? "mailto:admin@appsc.local";

function clasificarErrorPush(error) {
  const status = Number(error?.statusCode ?? 0);
  if (status === 404 || status === 410) return "expired";
  if (status === 0 || status === 408 || status === 429 || status >= 500) return "retry";
  return "failed";
}

export default {
  fetch: withSupabase({ auth: "secret:notifications" }, async (_req, ctx) => {
    if (!claveVapidPublica || !claveVapidPrivada) {
      return Response.json({ error: "Faltan las claves VAPID" }, { status: 503 });
    }

    webpush.setVapidDetails(contacto, claveVapidPublica, claveVapidPrivada);

    const { data: entregas, error: errorEntregas } = await ctx.supabaseAdmin.rpc(
      "fn_reclamar_push_notificaciones",
      { p_limite: 50 },
    );
    if (errorEntregas) {
      return Response.json({ error: "No se pudieron reclamar las entregas" }, { status: 500 });
    }

    let enviados = 0;
    let fallidos = 0;

    for (const entrega of entregas ?? []) {
      let resultado = "sent";
      try {
        await webpush.sendNotification(
          {
            endpoint: entrega.endpoint,
            keys: { p256dh: entrega.p256dh, auth: entrega.auth_key },
          },
          JSON.stringify({
            title: entrega.titulo,
            body: entrega.mensaje,
            url: entrega.pedido_id ? `/?pedido=${entrega.pedido_id}` : "/",
            tag: `${entrega.evento_id}:${entrega.push_milestone ?? "estado"}`,
          }),
          { TTL: 86400 },
        );
      } catch (error) {
        resultado = clasificarErrorPush(error);
      }

      const { error: errorConfirmacion } = await ctx.supabaseAdmin.rpc(
        "fn_confirmar_entrega_push",
        {
          p_entrega_id: entrega.entrega_id,
          p_claim_token: entrega.claim_token,
          p_resultado: resultado,
        },
      );

      if (errorConfirmacion) {
        console.error("No se pudo confirmar una entrega push", {
          entregaId: entrega.entrega_id,
          error: errorConfirmacion.message,
        });
        return Response.json({ error: "No se pudieron confirmar todas las entregas" }, { status: 500 });
      }

      if (resultado === "sent") enviados++;
      else fallidos++;
    }

    return Response.json({ entregas: entregas?.length ?? 0, enviados, fallidos });
  }),
};
