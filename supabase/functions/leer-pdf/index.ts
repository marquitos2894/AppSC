import { withSupabase } from "npm:@supabase/server";
import { extractText } from "npm:unpdf";

// Recibe { path } (ruta dentro del bucket "Documentos"), descarga el PDF,
// extrae el texto, estructura los campos del pedido (cabecera + tabla de ítems),
// elimina el archivo de Storage y devuelve el JSON al frontend.
export default {
  fetch: withSupabase({ auth: "user" }, async (req, ctx) => {
    let path: string | undefined;
    try {
      const body = await req.json();
      path = body?.path;
      if (!path) {
        return Response.json({ error: "Falta el parámetro 'path'" }, { status: 400 });
      }

      // 1) Descargar el PDF
      let blob: Blob;
      try {
        const { data, error: dl } = await ctx.supabaseAdmin.storage
          .from("Documentos")
          .download(path);
        if (dl || !data) {
          return Response.json(
            { error: `No se pudo descargar el PDF (${dl?.message ?? "sin datos"})` },
            { status: 404 },
          );
        }
        blob = data;
      } catch (e) {
        console.error("leer-pdf download error:", e);
        return Response.json({ error: `Error descargando: ${e?.message}` }, { status: 500 });
      }

      // 2) Extraer texto
      let text: string;
      try {
        const bytes = new Uint8Array(await blob.arrayBuffer());
        const res = await extractText(bytes, { mergePages: true });
        text = Array.isArray(res.text) ? res.text.join("\n") : res.text;
      } catch (e) {
        console.error("leer-pdf extractText error:", e);
        return Response.json({ error: `Error extrayendo texto: ${e?.message}` }, { status: 500 });
      }

      // 3) Eliminar el archivo tras extraer los datos
      try {
        await ctx.supabaseAdmin.storage.from("Documentos").remove([path]);
      } catch (e) {
        console.error("leer-pdf remove error:", e);
        console.warn("No se pudo eliminar el archivo:", path);
      }

      return Response.json({ ...parsearPedido(text), text });
    } catch (e) {
      console.error("leer-pdf handler error:", e);
      return Response.json({ error: e?.message ?? "Error al procesar el PDF" }, { status: 500 });
    }
  }),
};

interface Item {
  nro_parte: string;
  material: string;
  cantidad_solicitada: number;
  equipo: string;
}

function parsearPedido(text: string) {
  const nro_sc =
    extraer(text, /N[°º]?\s*S\.?C\.?\s*[:.\-\s]*(\d+)/i) ??
    (text.match(/\b(\d{3,6})\b/) || [])[1] ??
    null;

  const fecha =
    text.match(/FECHA DE DOCUMENTO\s*:\s*(\d{1,2}-\d{1,2}-\d{4})/i) ??
    text.match(/FECHA DE SOLICITUD\s*:\s*(\d{1,2}-\d{1,2}-\d{4})/i);

  return {
    nro_sc,
    fecha_emision: fecha?.[1] ?? null,
    motivo: extraer(text, /MOTIVO\s*\n\s*(.+)/i),
    grupo_costo: extraer(text, /GRUPO DE COSTO\s*:\s*(.+)/i),
    items: parsearItems(text),
  };
}

const ITEM_START =
  /^(\d+)\s+(\S+)\s+(\S+)\s+(.+?)\s+(\d+(?:\.\d+)?)\s+(\d+(?:\.\d+)?)\s+(\S+)$/;
const FIN_TABLA = /COMENTARIOS DEL AUTORIZADOR/i;

function parsearItems(text: string): Item[] {
  const lineas = text.split("\n").map((l) => l.trim()).filter((l) => l.length > 0);
  const items: { nro_parte: string; material: string; cantidad_solicitada: number; continuacion: string[] }[] = [];
  let actual: (typeof items)[number] | null = null;

  for (const linea of lineas) {
    if (FIN_TABLA.test(linea)) break;

    const m = linea.match(ITEM_START);
    if (m) {
      actual = {
        nro_parte: m[3],
        material: m[4],
        cantidad_solicitada: Number(m[6]) || 0,
        continuacion: [],
      };
      items.push(actual);
    } else if (actual) {
      actual.continuacion.push(linea);
    }
  }

  return items.map((it) => ({
    nro_parte: it.nro_parte,
    material: it.material,
    cantidad_solicitada: it.cantidad_solicitada,
    equipo: equipoCodigo(it.continuacion),
  }));
}

function equipoCodigo(continuacion: string[]): string {
  const todas = continuacion.join(" ");
  const m = todas.match(/[A-Z]{1,6}-\d{1,4}/);
  return m ? m[0] : "";
}

function extraer(text: string, re: RegExp) {
  const m = text.match(re);
  return m?.[1]?.trim() || null;
}
