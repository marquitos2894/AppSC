# Prompt: Sistema de Gestión de Pedidos y Detalle (Supabase + Vue 3 + PrimeVue)

Construye una aplicación web full-stack para gestionar solicitudes de pedidos de materiales/repuestos industriales (Pedidos) y su detalle por ítem, con seguimiento de estados y control de cantidades con atenciones parciales.

## Stack técnico

- **Backend/BD:** Supabase (PostgreSQL + PostgREST + Row Level Security + Triggers/Functions)
- **Frontend:** Vue 3, Composition API, **JavaScript puro (sin TypeScript)**
- **Estado global:** Pinia
- **UI:** PrimeVue (tema Aura) + PrimeIcons
- **Cliente BD:** `@supabase/supabase-js`
- **Build:** Vite

---

## 1. Modelo de datos

Usa `snake_case` (convención estándar de Postgres/Supabase). Todas las tablas incluyen `timestamp` (creación del registro) y `active` (soft delete).

```sql
-- Catálogo de estados del flujo
create table estados_catalogo (
  estado_id     serial primary key,
  nombre        varchar(50) not null,
  orden         int,                 -- null para estados de excepción (Observado/Rechazado)
  es_excepcion  boolean not null default false,
  active        boolean not null default true
);

-- Pedido (encabezado)
create table pedido (
  pedido_id        bigserial primary key,
  fecha_emision    date not null default current_date,
  motivo           text,
  grupo_costo      varchar(50),
  estado_actual_id int not null references estados_catalogo(estado_id),
  estado_atencion  varchar(30),
  timestamp        timestamptz not null default now(),
  active           boolean not null default true
);

-- Detalle de pedido (ítems)
create table detalle_pedido (
  detalle_id          bigserial primary key,
  pedido_id           bigint not null references pedido(pedido_id),
  nro_parte           varchar(50),
  material            varchar(150),
  cantidad_solicitada numeric(12,2) not null,
  cantidad_aprobada   numeric(12,2) not null default 0,
  cantidad_atendida   numeric(12,2) not null default 0,
  equipo              varchar(100),
  estado_actual_id    int not null references estados_catalogo(estado_id),
  estado_atencion     varchar(30),
  timestamp           timestamptz not null default now(),
  active              boolean not null default true
);

-- Historial de estados del encabezado
create table solicitud_historial_estados (
  historial_id bigserial primary key,
  pedido_id    bigint not null references pedido(pedido_id),
  estado_id    int not null references estados_catalogo(estado_id),
  fecha        timestamptz not null default now(),
  comentario   text,
  timestamp    timestamptz not null default now(),
  active       boolean not null default true
);

-- Ingresos (entregas) de cada ítem del detalle
create table detalle_ingreso (
  ingreso_id bigserial primary key,
  detalle_id bigint not null references detalle_pedido(detalle_id),
  cantidad   numeric(12,2) not null,
  fecha      timestamptz not null default now(),
  timestamp  timestamptz not null default now(),
  active     boolean not null default true
);

-- Historial de estados del detalle
create table detalle_historial_estados (
  historial_id bigserial primary key,
  detalle_id   bigint not null references detalle_pedido(detalle_id),
  estado_id    int not null references estados_catalogo(estado_id),
  fecha        timestamptz not null default now(),
  comentario   text,
  timestamp    timestamptz not null default now(),
  active       boolean not null default true
);
```

**Seed de `estados_catalogo`** (según el flujo definido: Emisión → Confirmado → En análisis → punto de decisión → Cotización → Autorizado → Compra → Atendido):

```sql
insert into estados_catalogo (nombre, orden, es_excepcion) values
  ('Emisión', 1, false),
  ('Confirmado', 2, false),
  ('En análisis', 3, false),
  ('Aprobado', 4, false),
  ('En cotización', 5, false),
  ('Autorizado', 6, false),
  ('En compra', 7, false),
  ('Atendido', 8, false),
  ('Observado', null, true),
  ('Rechazado', null, true);
```

`es_excepcion = true` marca los estados que no cuentan para el avance normal (se usan en la Regla 1/2 más abajo, en vez de comparar strings en el trigger).

---

## 2. Lógica de negocio (implementar en BD, no en el frontend)

**a) Estado del encabezado (`pedido.estado_actual_id`)** — recalcular con un trigger cada vez que cambia `detalle_pedido.estado_actual_id`:

1. Si TODOS los ítems activos del pedido tienen `es_excepcion = true`: el encabezado toma `Rechazado` si todos son Rechazado, o `Observado` si hay mezcla o todos Observado.
2. Si NO (quedan ítems en flujo normal): el encabezado toma el estado con el **menor `orden`** entre los ítems que NO son excepción (el ítem menos avanzado marca la fase del pedido).
3. Cada vez que el resultado cambia, insertar una fila en `solicitud_historial_estados` con la fecha.
4. Los ítems en excepción no bloquean el avance del encabezado; solo se cuentan aparte (ver vista de resumen).

**b) Cantidad atendida y atenciones parciales** — trigger `AFTER INSERT` en `detalle_ingreso`:

1. Recalcular `detalle_pedido.cantidad_atendida = sum(detalle_ingreso.cantidad)` para ese `detalle_id`.
2. Si `cantidad_atendida >= cantidad_aprobada`, mover `detalle_pedido.estado_actual_id` a `Atendido` e insertar en `detalle_historial_estados`.
3. La cantidad pendiente (`cantidad_aprobada - cantidad_atendida`) es siempre calculada, no se guarda: cada entrega parcial es una fila nueva en `detalle_ingreso`, dando trazabilidad completa sin duplicar filas en `detalle_pedido`.

**c) Vista de resumen para el listado:**

```sql
create view vw_pedidos_resumen as
select
  p.pedido_id,
  p.fecha_emision,
  p.motivo,
  ec.nombre as estado_actual,
  count(d.detalle_id) filter (where dec.nombre = 'Observado') as items_observados,
  count(d.detalle_id) filter (where dec.nombre = 'Rechazado') as items_rechazados,
  count(d.detalle_id) as total_items
from pedido p
join estados_catalogo ec on ec.estado_id = p.estado_actual_id
left join detalle_pedido d on d.pedido_id = p.pedido_id and d.active
left join estados_catalogo dec on dec.estado_id = d.estado_actual_id
where p.active
group by p.pedido_id, p.fecha_emision, p.motivo, ec.nombre;
```

**d) RLS:** habilitar Row Level Security en todas las tablas; definir policies según el modelo de usuarios/roles de la app (no especificado aún — usar policies permisivas para `authenticated` como punto de partida y ajustar).

---

## 3. Frontend (Vue 3 + Pinia + PrimeVue)

**Estructura sugerida:**
```
src/
  api/supabaseClient.js
  stores/
    pedidosStore.js        # listado (vw_pedidos_resumen), filtros
    detallePedidoStore.js  # detalle de un pedido: ítems, ingresos, cambio de estado
    estadosStore.js        # catálogo de estados (cache)
  components/
    PedidosTable.vue
    PedidoDetailPanel.vue  # panel lateral (Sidebar)
    EstadoTag.vue          # tag de color por estado
    EstadoStepper.vue      # progreso del flujo con la rama de decisión
    IngresoForm.vue
    HistorialTimeline.vue
  views/
    PedidosView.vue
  App.vue / main.js / router
```

**Interacción clave:** el detalle **no navega a otra ruta** — un click en la fila del `DataTable` abre un `Sidebar` de PrimeVue (`position="right"`) con el detalle del pedido. Esto mantiene al usuario en el contexto del listado, que es justamente el pedido de "diseño tipo panel lateral".

**Componentes PrimeVue a usar:** `DataTable` + `Column`, `Sidebar`, `Tag`, `Timeline`, `Steps`/`Stepper`, `Dialog`, `InputNumber`, `Calendar`, `Textarea`, `Button`, `Toast`, `ConfirmDialog`, `Skeleton` (loading states).

---

## 4. Dirección de diseño

Pensado para un panel interno de uso frecuente por personal técnico/operativo (no una landing comercial): prioriza legibilidad de datos densos y distinción clara de estados por color, con una identidad propia (evitar el azul genérico de dashboard SaaS).

- **Paleta base:** `#1E2A38` (azul acero oscuro — sidebar/header), `#F5F7FA` (fondo de contenido), `#3B6E8F` (acento primario — acero azulado, botones/nav activo)
- **Estados de excepción** (mantener la convención semáforo que ya usas): Observado `#E8A33D`, Rechazado `#D64545`, Aprobado `#3F9142`
- **Estados de flujo normal:** tonos neutros de la paleta base (gris-azulado), para diferenciar visualmente "fase del proceso" de "alerta/decisión"
- **Tipografía:** Inter para UI y tablas (alta legibilidad en tamaños pequeños); una monoespaciada (JetBrains Mono / IBM Plex Mono) para códigos (`NroParte`, `PedidoID`) — distingue identificadores de texto libre
- **Elemento distintivo:** el `EstadoStepper` del panel lateral — línea de progreso horizontal que, al llegar a "En análisis", muestra visualmente la bifurcación hacia Observado/Rechazado/Aprobado (replicando la lógica de decisión de tu flujo), en vez de un stepper lineal genérico

---

## 5. Alcance funcional mínimo

- Listado de Pedidos (`vw_pedidos_resumen`) con filtro por estado y buscador, mostrando contadores de ítems Observado/Rechazado
- Panel lateral de detalle: tabla de ítems con cantidades, cambio de estado por ítem, registro de ingresos (entregas parciales), timeline de historial de estados (encabezado y por ítem)
- Cálculo de estado del encabezado y de cantidad atendida resuelto en BD (triggers), el frontend solo lee y muestra
- CRUD de Pedido + ítems (alta de solicitud)

## 6. Entregables esperados

1. Script SQL completo (tablas, triggers, vista, seed de `estados_catalogo`)
2. Proyecto Vue 3 + Vite funcional, conectado a Supabase vía variables de entorno (`VITE_SUPABASE_URL`, `VITE_SUPABASE_ANON_KEY`)
3. README con instrucciones de setup local
