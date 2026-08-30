# Referencia de contexto AppSC

Detalles que no necesitan cargarse en cada tarea. Consultar solo cuando el cambio afecte al subsistema correspondiente.

## Supabase y modelo de datos

- `supabase/schema.sql` contiene tablas, seed, funciones, triggers, vistas y RLS. Es idempotente y se puede reejecutar completo en SQL Editor.
- La lógica de negocio vive en la base de datos. No reimplementar triggers/RPC en JavaScript.
- Resolver estados por nombre (`estadosStore.byName`/`byId`). `estado_id` no equivale a `orden`: Aprobado es id 4/orden 5 y En cotización id 5/orden 4. Estados fijos: 1 Registrado, 2 Confirmado, 3 En análisis, 4 Aprobado, 5 En cotización, 7 En compra, 8 Atendido, 9 Observado, 10 Rechazado. El 6 (`Autorizado`) está soft-delete y fue sustituido por `pedido.autorizado`.
- `estados_catalogo.ambito` puede ser `pedido`, `detalle` o `auto`; los selects usan `pedidoStates`/`detalleStates`.
- El estado del encabezado se recalcula por el mayor `orden` entre ítems normales. `Atendido` es derivado y terminal: se asigna cuando hay cantidad atendida y se revierte al eliminar todas las entregas.
- Triggers: ingreso permitido en Aprobado/En cotización/En compra/Atendido con suma de ingresos ≤ cantidad aprobada; Observado/Rechazado pone cantidad aprobada en cero; cambios de detalle requieren haber pasado por En análisis; no se repite el estado actual.
- `pedido.estado_atencion` es `PENDIENTE|PARCIAL|COMPLETO`, calculado por trigger. `detalle_ingreso.fecha` es `date` y `documento` es `varchar(25)`.
- Vistas principales: `vw_pedidos_resumen` para listado y `vw_items_detalle` para `/items`.
- Dashboard `/dashboard`: `dashboardStore`, `DashboardView.vue`, RPCs `dashboard_kpis`, `dashboard_pedidos_por_estado`, `dashboard_pedidos_por_costo` y vista `vw_items_pendientes`. Estos RPCs/vistas se crearon remotamente por MCP y no están en `schema.sql`; recrearlos si se reconstruye la BD.

## Edge Function `leer-pdf`

- Ubicación `supabase/functions/leer-pdf/`; usa Deno, `@supabase/server` y `unpdf`. `supabase/config.toml` tiene `verify_jwt = false`.
- Recibe POST `{ path }`, descarga desde el bucket privado `Documentos`, extrae texto, elimina el archivo y devuelve cabecera/ítems JSON. Auth `auth: "user"`.
- Cambios/despliegue solo por MCP `supabase_deploy_edge_function` con `index.ts` y `deno.json`. El frontend invoca `supabase.functions.invoke('leer-pdf', { body: { path } })`.
- El parser usa la línea ancla `^(\d+)\s+(\S+)\s+(\S+)\s+(.+?)\s+(\d+\.?\d*)\s+(\d+\.?\d*)\s+(\S+)$`; `nro_parte` es `m[3]`, la cantidad solicitada corresponde a la Cantidad Aprobada del PDF y `equipo` detecta códigos cortos con guion.

## Storage y Auth

- Bucket privado `Documentos`, políticas `documentos_insert`/`documentos_select` para `authenticated`. Las subidas usan `${nro_sc}/${file.name}` y el acceso privado usa URL firmada.
- La sesión es obligatoria por email/password, sin auto-registro. RLS permite acceso a `authenticated`.
- Ejecutar `authStore.init()` antes de `mount`; el router tiene guard. Variables: `VITE_SUPABASE_URL` y `VITE_SUPABASE_ANON_KEY` publishable. Proyecto remoto: `https://qhsizmayuhnlvcjcomlx.supabase.co`.

## Notas del frontend

- `nroSc` usa `InputNumber`, por lo que pierde ceros a la izquierda; es intencional.
- El listado busca por `nro_sc`; `/items` filtra material, nro. de parte, nro. SC y estado.
- Las mutaciones del detalle refrescan el listado mediante `_recargarTodo`.
- `EstadoTag` abre el diálogo de cambio, excepto cuando el ítem está Atendido.
- `DataTable @row-click` entrega `{ originalEvent, data, index }`; usar `event.data.pedido_id`.
- `Drawer`/`Dialog` usan `v-model:visible`; con stores usar `storeToRefs`.
- El comentario de cambio de estado se adjunta a la fila de historial más reciente mediante `_anotarMovimiento`.
- PrimeVue `Password` requiere `input-id`; las skills locales están en `.agents/skills/`.
