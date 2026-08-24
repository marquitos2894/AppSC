# AGENTS.md

App Vue 3 SPA de gestión de pedidos + backend Supabase (Postgres/RLS/triggers).

## Comandos
- `npm run dev` — Vite (puerto 5173)
- `npm run build` — **única verificación disponible** (no hay lint/typecheck/test)
- `npm run preview` — servir build

Sin framework de tests configurado. No es repo git (sin `.git`).

## Stack y convenciones
- **JavaScript puro, sin TypeScript.** `<script setup>` Composition API.
- **PrimeVue fijado a v4.3.9 a propósito. NO subir a v5** (requiere licencia PrimeUI comercial y renombra componentes). Usar nombres v4 nuevos: `Select` (no Dropdown), `DatePicker` (no Calendar), `Drawer` (no Sidebar). Los viejos están deprecados y emiten warning.
- Auto-import de componentes PrimeVue (unplugin-vue-components + resolver en vite.config.js): componentes del template no se importan. **Composables sí se importan explícitos**: `useToast` de `primevue/usetoast`, `useConfirm` de `primevue/useconfirm`. Servicios `ToastService`/`ConfirmationService` ya registrados en `src/main.js`.
- Alias `@` → `src` (vite.config.js).
- Estados de color en `src/stores/estadosStore.js` (`ESTADO_COLORS`) — fuente única para `EstadoTag`/`EstadoStepper`. Tokens de diseño en `src/styles/main.css` (`--ink-900`, etc.). Preset Aura custom en `main.js` (definePreset).

## Backend (Supabase)
- `supabase/schema.sql` = todo el esquema (tablas, seed, funciones, triggers, vista, RLS). **Idempotente**: se puede re-ejecutar entero en el SQL Editor.
- **La lógica de negocio vive en la BD** (triggers): estado del encabezado se recalcula de los ítems; `cantidad_atendida`/`estado_atencion` se recalculan por ingreso. El frontend solo lee/escribe — nunca reimplementar en JS.
- Cambio de estado a nivel pedido (desde el listado) vía RPC `fn_cambiar_estado_pedido`: registra en `solicitud_historial_estados` y propaga a todos los ítems activos con doble registro en `detalle_historial_estados` (fecha y comentario manuales).
- Estados: seed con ids fijos 1–10 pero **resolver siempre por nombre** vía `estadosStore.byName`/`byId`; no hardcodear ids.
- Soft delete en todas las tablas (`active`); las queries filtran `active=true`.
- Vista de listado: `vw_pedidos_resumen` (PostgREST la expone como tabla).

## Auth
- Sesión obligatoria de Supabase Auth (email/password, sin auto-registro). RLS es permisiva solo para `authenticated`.
- `authStore.init()` se llama antes de `mount` en `src/main.js` (evita flash de redirect). Guard en `src/router/index.js`: sin sesión → `/login`.
- Env: `VITE_SUPABASE_URL` + `VITE_SUPABASE_ANON_KEY` en `.env`. `isConfigured` en `src/api/supabaseClient.js`; sin config la app muestra warning y no consulta.
- Para probar contra Supabase real, crear usuarios en Dashboard → Authentication → Users.

## Gotchas
- `DataTable @row-click` recibe `{ originalEvent, data, index }` → usar `event.data.pedido_id` (no `row.pedido_id`).
- `Drawer`/`Dialog` usan `v-model:visible`; con estado de store usar `storeToRefs`.
- Comentarios de cambio de estado: el trigger inserta la fila de historial; la app adjunta el comentario editando la fila más reciente (`_anotarComentario` en detallePedidoStore).
- `Password` de PrimeVue: usar prop `input-id` para el input interno (con `id` el atributo cae en el div raíz).
- Skills locales disponibles en `.agents/skills/` (primevue, frontend-design, caveman).
