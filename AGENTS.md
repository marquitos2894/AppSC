# AGENTS.md

App Vue 3 SPA de gestión de pedidos + backend Supabase (Postgres/RLS/triggers/Edge Functions). Repo git → GitHub `marquitos2894/AppSC` (rama `main`).

## Comandos
- `npm run dev` — Vite (puerto 5173)
- `npm run build` — **única verificación disponible** (no hay lint/typecheck/test)
- `npm run preview` — servir build
- **Supabase se opera por MCP** (`supabase_apply_migration`, `supabase_execute_sql`, `supabase_deploy_edge_function`). No hay CLI local (`supabase`/`deno` no instalados).

## Stack y convenciones
- **JavaScript puro, sin TypeScript.** `<script setup>` Composition API. (Única excepción: la Edge Function `supabase/functions/leer-pdf/index.ts` es TS/Deno.)
- **PrimeVue fijado a v4.3.9 a propósito. NO subir a v5** (requiere licencia PrimeUI comercial y renombra componentes). Usar nombres v4: `Select` (no Dropdown), `DatePicker` (no Calendar), `Drawer` (no Sidebar).
- Auto-import de componentes PrimeVue (unplugin-vue-components en vite.config.js): los del template no se importan. Directivas (`v-tooltip`, etc.) también se auto-importan. **Excepciones explícitas**: `Chart` (`import Chart from 'primevue/chart'` + registro manual de `chart.js` en `DashboardView.vue`); composables `useToast` de `primevue/usetoast`, `useConfirm` de `primevue/useconfirm` (servicios registrados en `src/main.js`).
- Alias `@` → `src`.
- **Tema claro forzado**: `main.js` usa `options: { darkModeSelector: 'none' }` (con el SO en oscuro, PrimeVue se veía dark). Rail lateral y login quedan oscuros a propósito.
- Colores de estado en `src/stores/estadosStore.js` (`ESTADO_COLORS`); tokens en `src/styles/main.css`; preset Aura custom en `main.js`.

## Backend (Supabase)
- `supabase/schema.sql` = todo el esquema (tablas, seed, funciones, triggers, vistas, RLS). **Idempotente**: re-ejecutable entero en el SQL Editor.
- **La lógica de negocio vive en la BD** (triggers/RPC). El frontend solo lee/escribe — nunca reimplementar en JS.
- Estados: **resolver siempre por nombre** (`estadosStore.byName`/`byId`), no hardcodear ids. **`estado_id` NO coincide con `orden`** (ej. Aprobado id=4/orden=5, En cotización id=5/orden=4; la jerarquía real está en `orden`). ids fijos: 1 Registrado, 2 Confirmado, 3 En análisis, 4 Aprobado, 5 En cotización, 7 En compra, 8 Atendido, 9 Observado, 10 Rechazado; **6 = `Autorizado` soft-delete** (reemplazado por `pedido.autorizado`). `estados_catalogo.ambito` ∈ `pedido|detalle|auto` (filtra selects vía `pedidoStates`/`detalleStates`).
- Encabezado del pedido = **mayor `orden`** entre ítems no-excepción (recalculado por triggers). `Atendido` es terminal/derivado: se auto-asigna si `cantidad_atendida > 0` (y `aprobada > 0`) y **no se cambia manualmente**; solo se revierte eliminando todas las entregas (`fn_revertir_atendido`).
- Reglas de ítems (triggers): ingreso solo en `Aprobado/En cotización/En compra/Atendido` y `sum(ingresos) ≤ cantidad_aprobada` (INSERT y UPDATE excluyendo la fila editada); pasar a `Rechazado/Observado` pone `cantidad_aprobada = 0`; cambiar detalle exige que el pedido ya registró `En análisis`; el pedido no se edita manualmente una vez registró `En análisis`; no re-registrar el estado actual.
- `pedido.estado_atencion` = `PENDIENTE|PARCIAL|COMPLETO` (por `fn_recalcular_pedido_atencion`); badge "Pendiente/Parcial/Completo" solo en el listado.
- `detalle_ingreso.fecha` es **`date`** (no timestamp); columna `documento varchar(25)`.
- Vistas: `vw_pedidos_resumen` (listado) y `vw_items_detalle` (ítems con `nro_sc`, para la página `/items`).
- **Dashboard** (`/dashboard`): `dashboardStore` + `DashboardView.vue`, 3 RPCs con rango de fechas (`dashboard_kpis`, `dashboard_pedidos_por_estado`, `dashboard_pedidos_por_costo`, todas `(p_desde date, p_hasta date)`) + vista `vw_items_pendientes` y gráficos Chart.js. **OJO: estos RPCs y `vw_items_pendientes` NO están en `schema.sql`** — se crearon por MCP (`supabase_apply_migration`) y solo existen en la BD remota; si se re-ejecuta `schema.sql` desde cero hay que recrearlos.

## Edge Function `leer-pdf`
- Local en `supabase/functions/leer-pdf/` (Deno, `@supabase/server`, `unpdf`); config en `supabase/config.toml` (`verify_jwt = false`).
- Flujo: POST `{ path }` → `supabaseAdmin.storage.from('Documentos').download(path)` → `extractText(bytes, { mergePages: true })` → **borra el archivo** (`remove`) → parsea cabecera + tabla de ítems → JSON. Auth `auth: "user"`.
- **Desplegar/cambiar vía MCP** `supabase_deploy_edge_function` (`name=leer-pdf`, `verify_jwt=false`, `import_map_path="deno.json"`, `files` = `index.ts` + `deno.json`). El frontend la llama con `supabase.functions.invoke('leer-pdf', { body: { path } })`.
- Parseo de ítems: línea ancla `^(\d+)\s+(\S+)\s+(\S+)\s+(.+?)\s+(\d+\.?\d*)\s+(\d+\.?\d*)\s+(\S+)$`; columnas `Nº | Código ERP | Nro. Parte | Material | Solic. | Aprob. | Unidad | …`. `nro_parte` = `m[3]`; `cantidad_solicitada` = la "Cantidad Aprobada" del PDF; `equipo` = código corto con guion (`[A-Z]{1,6}-\d{1,4}`) en las líneas de continuación.

## Storage
- Bucket **"Documentos"** (privado); políticas `documentos_insert`/`documentos_select` para `authenticated` (se crean vía SQL sobre `storage.objects`).
- Subida desde `PedidoFormDialog`: `supabase.storage.from('Documentos').upload(\`${nro_sc}/${file.name}\`, file)` → ruta `Documentos/{nro_sc}/{nombre}.pdf`. No se guarda referencia en BD ni preview. Acceso a privados vía URL firmada (`createSignedUrl`).

## Auth
- Sesión obligatoria (email/password, sin auto-registro); RLS permisiva solo para `authenticated`.
- `authStore.init()` antes de `mount` en `src/main.js` (evita flash); guard en `src/router/index.js`.
- Env en `.env`: `VITE_SUPABASE_URL` + `VITE_SUPABASE_ANON_KEY` (**publishable** `sb_publishable_...`). Proyecto remoto `https://qhsizmayuhnlvcjcomlx.supabase.co`.
- `isConfigured` en `src/api/supabaseClient.js` (sin config, la app muestra warning).

## Frontend — notas
- `nroSc` es `InputNumber` → **pierde ceros a la izquierda** (`001040` → `1040`), aceptado.
- Búsqueda del listado filtra por `nro_sc` (quita prefijo "SC"). Página `/items` (Ítems) filtra por material/nro parte/nro_sc/estado.
- Mutaciones del detalle refrescan el listado (`detallePedidoStore._recargarTodo` → `pedidosStore.fetchPedidos`).
- Clic en el `EstadoTag` del ítem abre "Cambiar estado" (no hay lápiz); bloqueado si está "Atendido".

## Gotchas
- `DataTable @row-click` recibe `{ originalEvent, data, index }` → usar `event.data.pedido_id`.
- `Drawer`/`Dialog` usan `v-model:visible`; con estado de store usar `storeToRefs`.
- Comentarios de cambio de estado: la app adjunta el comentario editando la fila más reciente (`detallePedidoStore._anotarMovimiento`).
- `Password` de PrimeVue: usar prop `input-id` (con `id` cae en el div raíz).
- Skills locales en `.agents/skills/` (primevue, frontend-design, caveman, impeccable, supabase-server).
