# AppSC · Gestión de Pedidos y Detalle

Aplicación full-stack para gestionar solicitudes de pedidos de materiales/repuestos industriales, con seguimiento de estados por ítem y atenciones parciales (entregas múltiples por ítem).

- **Backend/BD:** Supabase (PostgreSQL + PostgREST + RLS + triggers/functions)
- **Frontend:** Vue 3 (Composition API, JavaScript puro) + Pinia + PrimeVue (tema Aura) + Vite

## Estructura

```
supabase/schema.sql     # tablas, seed, triggers, vista, RLS
src/
  api/supabaseClient.js
  stores/               # pedidosStore, detallePedidoStore, estadosStore
  components/           # PedidosTable, PedidoDetailPanel, EstadoStepper, dialogs...
  views/PedidosView.vue
  styles/main.css       # sistema de diseño
```

## Setup

### 1. Base de datos (Supabase)

1. Crear un proyecto en [supabase.com](https://supabase.com).
2. Abrir **SQL Editor** y ejecutar el contenido completo de `supabase/schema.sql`.
   - Crea tablas, seed de `estados_catalogo`, funciones/triggers, vista `vw_pedidos_resumen` y policies RLS permisivas para `authenticated`.
   - Es idempotente: se puede volver a ejecutar sin duplicar datos.
3. Ejecutar el SQL crea tablas, seed, triggers, vista y policies RLS (idempotente).

### 2. Frontend

```bash
npm install
cp .env.example .env      # en Windows: copy .env.example .env
```

Editar `.env` con los valores de tu proyecto (**Project Settings → API**):

```
VITE_SUPABASE_URL=https://tu-proyecto.supabase.co
VITE_SUPABASE_ANON_KEY=tu-anon-key
```

```bash
npm run dev      # desarrollo (http://localhost:5173)
npm run build    # build de producción
npm run preview  # servir el build
```

### 3. Autenticación (Supabase Auth)

La app usa sesión de Supabase Auth (email/password) y las policies RLS aplican para el rol `authenticated`.

1. En el dashboard: **Authentication → Sign In / Providers → Email** (activado por defecto).
2. Crear usuarios en **Authentication → Users → Add user** (email + contraseña).
3. Entrar en la app con esas credenciales. La sesión persiste en el navegador; "Salir" cierra sesión y redirige al login.

## Lógica de negocio (en la BD, no en el frontend)

- **Estado del encabezado** (`pedido.estado_actual_id`): se recalcula por trigger cada vez que cambia el estado de un ítem.
  - Si todos los ítems activos son excepción: `Rechazado` (todos rechazados) u `Observado` (mezcla o todos observados).
  - Si quedan ítems en flujo normal: estado con el menor `orden` entre los no-excepción.
  - Cada cambio inserta una fila en `solicitud_historial_estados`.
- **Atenciones parciales**: cada entrega es una fila nueva en `detalle_ingreso`. Un trigger recalcula `cantidad_atendida` y `estado_atencion` (`SIN_ATENDER`/`PARCIAL`/`COMPLETA`); al completar, mueve el ítem a `Atendido` y registra el historial.
- La cantidad pendiente se calcula siempre (`cantidad_aprobada - cantidad_atendida`), nunca se guarda.

## Flujo de estados

```
Emisión → Confirmado → En análisis → Aprobado → En cotización → Autorizado → En compra → Atendido
                          ├→ Observado (excepción)
                          └→ Rechazado (excepción)
```

## Uso

- El listado muestra todos los pedidos activos con contadores de ítems observados/rechazados.
- Click en una fila abre el panel lateral con el detalle: stepper del flujo, ítems con cantidades, cambio de estado por ítem, registro de ingresos parciales y timeline de historial.
- **Nuevo pedido** abre el diálogo de alta (encabezado + ítems).
- Borrados son lógicos (`active = false`).
