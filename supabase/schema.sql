-- ============================================================================
-- AppSC — Sistema de Gestión de Pedidos y Detalle
-- Script completo: tablas, seed, funciones, triggers, vista y RLS.
-- Ejecutar completo en Supabase SQL Editor. Es idempotente (safe re-run).
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. Tablas
-- ----------------------------------------------------------------------------

-- Catálogo de estados del flujo
create table if not exists estados_catalogo (
  estado_id     serial primary key,
  nombre        varchar(50) not null,
  orden         int,                 -- null para estados de excepción (Observado/Rechazado)
  es_excepcion  boolean not null default false,
  active        boolean not null default true,
  ambito        varchar(20)          -- 'pedido' | 'detalle' | 'auto' (Atendido)
);

-- Pedido (encabezado)
create table if not exists pedido (
  pedido_id        bigserial primary key,
  fecha_emision    date not null default current_date,
  motivo           text,
  grupo_costo      varchar(50),
  nro_sc           varchar(50),        -- código ERP externo (número de solicitud)
  estado_actual_id int not null references estados_catalogo(estado_id),
  estado_atencion  varchar(30),
  timestamp        timestamptz not null default now(),
  active           boolean not null default true
);

-- Columna añadida en BD existentes (idempotente)
alter table pedido add column if not exists nro_sc varchar(50);

-- Fecha/hora en que se autoriza el pedido (reemplaza al antiguo estado "Autorizado")
alter table pedido add column if not exists autorizado timestamptz;

-- Detalle de pedido (ítems)
create table if not exists detalle_pedido (
  detalle_id          bigserial primary key,
  pedido_id           bigint not null references pedido(pedido_id),
  nro_parte           varchar(50),
  material            varchar(150),
  cantidad_solicitada numeric(12,2) not null,
  cantidad_aprobada   numeric(12,2) not null default 0,
  cantidad_atendida   numeric(12,2) not null default 0,
  equipo              varchar(100),
  fecha_aprox_atencion date,
  estado_actual_id    int not null references estados_catalogo(estado_id),
  estado_atencion     varchar(30),
  timestamp           timestamptz not null default now(),
  active              boolean not null default true
);

alter table detalle_pedido add column if not exists fecha_aprox_atencion date;

-- Historial de estados del encabezado
create table if not exists solicitud_historial_estados (
  historial_id bigserial primary key,
  pedido_id    bigint not null references pedido(pedido_id),
  estado_id    int not null references estados_catalogo(estado_id),
  fecha        timestamptz not null default now(),
  comentario   text,
  timestamp    timestamptz not null default now(),
  active       boolean not null default true
);

-- Ingresos (entregas) de cada ítem del detalle
create table if not exists detalle_ingreso (
  ingreso_id bigserial primary key,
  detalle_id bigint not null references detalle_pedido(detalle_id),
  cantidad   numeric(12,2) not null,
  documento  varchar(25),          -- referencia de documento (guía/factura)
  fecha      date not null default current_date,
  timestamp  timestamptz not null default now(),
  active     boolean not null default true
);

alter table detalle_ingreso add column if not exists documento varchar(25);

-- fecha pasa de timestamp a date (solo el día de la entrega)
alter table detalle_ingreso alter column fecha type date using fecha::date;

-- Historial de estados del detalle
create table if not exists detalle_historial_estados (
  historial_id bigserial primary key,
  detalle_id   bigint not null references detalle_pedido(detalle_id),
  estado_id    int not null references estados_catalogo(estado_id),
  fecha        timestamptz not null default now(),
  comentario   text,
  timestamp    timestamptz not null default now(),
  active       boolean not null default true
);

-- ----------------------------------------------------------------------------
-- 2. Seed de estados_catalogo
-- ----------------------------------------------------------------------------

insert into estados_catalogo (estado_id, nombre, orden, es_excepcion) values
  (1,  'Registrado',       1, false),
  (2,  'Confirmado',    2, false),
  (3,  'En análisis',   3, false),
  (4,  'Aprobado',      5, false),
  (5,  'En cotización', 4, false),
  (6,  'Autorizado',    null, false),
  (7,  'En compra',     6, false),
  (8,  'Atendido',      7, false),
  (9,  'Observado',  null, true),
  (10, 'Rechazado',  null, true)
on conflict (estado_id) do nothing;

select setval(
  'estados_catalogo_estado_id_seq',
  greatest((select max(estado_id) from estados_catalogo), 1),
  true
);

-- "Autorizado" deja de ser un estado del flujo: se reemplaza por pedido.autorizado.
-- Soft-delete para preservar la integridad referencial de los historiales.
update estados_catalogo set active = false where nombre = 'Autorizado';

-- Jerarquía de avance (columna orden): Registrado < Confirmado < En análisis
-- < En cotización < Aprobado < En compra < Atendido.
update estados_catalogo set orden = case nombre
  when 'Registrado'    then 1
  when 'Confirmado'    then 2
  when 'En análisis'   then 3
  when 'En cotización' then 4
  when 'Aprobado'      then 5
  when 'En compra'     then 6
  when 'Atendido'      then 7
  when 'Observado'     then null
  when 'Rechazado'     then null
  when 'Autorizado'    then null
  else orden
end;

-- Clasifica cada estado por ámbito de aplicación: pedido | detalle | auto (Atendido).
-- Se usa para filtrar dinámicamente los estados disponibles en cada select.
alter table estados_catalogo add column if not exists ambito varchar(20);
update estados_catalogo set ambito = case nombre
  when 'Registrado'    then 'pedido'
  when 'Confirmado'    then 'pedido'
  when 'En análisis'   then 'pedido'
  when 'Aprobado'      then 'detalle'
  when 'En cotización' then 'detalle'
  when 'En compra'     then 'detalle'
  when 'Observado'     then 'detalle'
  when 'Rechazado'     then 'detalle'
  when 'Atendido'      then 'auto'
  else null
end;

-- ----------------------------------------------------------------------------
-- 3. Funciones de negocio
-- ----------------------------------------------------------------------------

-- Recalcula el estado del encabezado a partir de los ítems activos.
-- Regla 1: si TODOS los ítems son excepción -> Rechazado (todos rechazados)
--          u Observado (mezcla o todos observados).
-- Regla 2: si quedan ítems en flujo normal -> estado con mayor `orden`
--          entre los ítems no-excepción (el ítem más avanzado marca la fase).
-- Inserta fila en solicitud_historial_estados solo si el resultado cambia.
create or replace function fn_recalcular_pedido_estado(p_pedido_id bigint)
returns void
language plpgsql
as $$
declare
  v_total_activos   int;
  v_total_excepcion int;
  v_total_rechazado int;
  v_nuevo_estado    int;
  v_actual_estado   int;
begin
  -- Evita recálculos espurios durante la propagación masiva de
  -- fn_cambiar_estado_pedido (que actualiza los ítems de uno en uno).
  if current_setting('app.skip_pedido_recalculo', true) = '1' then
    return;
  end if;

  select
    count(*) filter (where d.active),
    count(*) filter (where d.active and ec.es_excepcion),
    count(*) filter (where d.active and ec.nombre = 'Rechazado')
    into v_total_activos, v_total_excepcion, v_total_rechazado
  from detalle_pedido d
  join estados_catalogo ec on ec.estado_id = d.estado_actual_id
  where d.pedido_id = p_pedido_id;

  -- Sin ítems activos no hay nada que recalcular
  if v_total_activos = 0 then
    return;
  end if;

  if v_total_excepcion = v_total_activos then
    -- Regla 1: todos en excepción
    if v_total_rechazado = v_total_activos then
      select estado_id into v_nuevo_estado from estados_catalogo where nombre = 'Rechazado';
    else
      select estado_id into v_nuevo_estado from estados_catalogo where nombre = 'Observado';
    end if;
  else
    -- Regla 2: mayor orden entre ítems no-excepción
    select d.estado_actual_id into v_nuevo_estado
    from detalle_pedido d
    join estados_catalogo ec on ec.estado_id = d.estado_actual_id
    where d.pedido_id = p_pedido_id
      and d.active
      and not ec.es_excepcion
    order by ec.orden desc nulls last
    limit 1;
  end if;

  select estado_actual_id into v_actual_estado from pedido where pedido_id = p_pedido_id;

  if v_actual_estado is distinct from v_nuevo_estado then
    update pedido set estado_actual_id = v_nuevo_estado where pedido_id = p_pedido_id;
    insert into solicitud_historial_estados (pedido_id, estado_id)
    values (p_pedido_id, v_nuevo_estado);
  end if;
end;
$$;

-- Recalcula la atención agregada del pedido (pedido.estado_atencion):
--   PENDIENTE -> ningún ítem atendido
--   PARCIAL   -> al menos un ítem atendido y quedan pendientes
--   COMPLETO  -> ningún ítem pendiente (aprobada - atendida <= 0)
--   NULL      -> sin ítems activos
create or replace function fn_recalcular_pedido_atencion(p_pedido_id bigint)
returns void
language plpgsql
as $$
declare
  v_activos    int;
  v_atendidos  int;
  v_pendientes int;
  v_atencion   varchar(30);
begin
  select
    count(*) filter (where d.active),
    count(*) filter (where d.active and d.cantidad_atendida > 0),
    count(*) filter (where d.active and (coalesce(d.cantidad_aprobada, 0) - coalesce(d.cantidad_atendida, 0)) > 0)
    into v_activos, v_atendidos, v_pendientes
  from detalle_pedido d
  where d.pedido_id = p_pedido_id;

  if v_activos = 0 then
    v_atencion := null;
  elsif v_atendidos = 0 then
    v_atencion := 'PENDIENTE';
  elsif v_pendientes = 0 then
    v_atencion := 'COMPLETO';
  else
    v_atencion := 'PARCIAL';
  end if;

  update pedido set estado_atencion = v_atencion where pedido_id = p_pedido_id;
end;
$$;

-- Recalcula cantidad_atendida y estado_atencion de un ítem.
-- Con p_promover = true, si hay ingreso (cantidad_atendida > 0) y el ítem está
-- aprobado (cantidad_aprobada > 0), mueve el ítem a Atendido e inserta el
-- historial. Nunca degrada un estado ya avanzado.
create or replace function fn_recalcular_detalle_atencion(p_detalle_id bigint, p_promover boolean default false)
returns void
language plpgsql
as $$
declare
  v_total           numeric(12,2);
  v_aprobada        numeric(12,2);
  v_atencion        varchar(30);
  v_estado_atendido int;
  v_estado_actual   int;
begin
  select coalesce(sum(cantidad), 0)
    into v_total
  from detalle_ingreso
  where detalle_id = p_detalle_id and active;

  select cantidad_aprobada into v_aprobada from detalle_pedido where detalle_id = p_detalle_id;

  if v_aprobada = 0 or v_total = 0 then
    v_atencion := 'SIN_ATENDER';
  elsif v_total < v_aprobada then
    v_atencion := 'PARCIAL';
  else
    v_atencion := 'COMPLETA';
  end if;

  update detalle_pedido
     set cantidad_atendida = v_total,
         estado_atencion   = v_atencion
   where detalle_id = p_detalle_id;

  if p_promover and v_aprobada > 0 and v_total > 0 then
    select estado_id into v_estado_atendido from estados_catalogo where nombre = 'Atendido';
    select estado_actual_id into v_estado_actual from detalle_pedido where detalle_id = p_detalle_id;

    if v_estado_actual is distinct from v_estado_atendido then
      -- Evita que el trigger de historial del detalle duplique la fila
      -- y que el bloqueo de "Atendido manual" rechace esta promoción.
      perform set_config('app.skip_detalle_historial', '1', true);
      perform set_config('app.allow_atendido', '1', true);
      perform set_config('app.allow_detalle_cambio', '1', true);
      update detalle_pedido set estado_actual_id = v_estado_atendido where detalle_id = p_detalle_id;
      perform set_config('app.allow_detalle_cambio', '0', true);
      perform set_config('app.allow_atendido', '0', true);
      perform set_config('app.skip_detalle_historial', '0', true);

      insert into detalle_historial_estados (detalle_id, estado_id, comentario)
      values (p_detalle_id, v_estado_atendido, 'Atendido por ingresos');
    end if;
  end if;
end;
$$;

-- Revierte retroactivamente la promoción a "Atendido" cuando el ítem queda sin
-- ingresos (sum(cantidad)=0): lo devuelve al estado anterior (desde su historial)
-- y desactiva la fila de historial auto-generada "Atendido por ingresos".
create or replace function fn_revertir_atendido(p_detalle_id bigint)
returns void
language plpgsql
as $$
declare
  v_estado_atendido int;
  v_estado_actual   int;
  v_total           numeric(12,2);
  v_hist_atendido   bigint;
  v_estado_prev     int;
begin
  select estado_id into v_estado_atendido from estados_catalogo where nombre = 'Atendido';
  select estado_actual_id into v_estado_actual from detalle_pedido where detalle_id = p_detalle_id;

  if v_estado_actual is distinct from v_estado_atendido then
    return; -- solo aplica si el ítem está "Atendido"
  end if;

  select coalesce(sum(cantidad), 0) into v_total
  from detalle_ingreso
  where detalle_id = p_detalle_id and active;

  if v_total > 0 then
    return; -- aún quedan ingresos, sigue "Atendido"
  end if;

  -- Fila de historial "Atendido" más reciente (auto-generada por ingresos)
  select h.historial_id into v_hist_atendido
  from detalle_historial_estados h
  join estados_catalogo ec on ec.estado_id = h.estado_id
  where h.detalle_id = p_detalle_id and h.active and ec.nombre = 'Atendido'
  order by h.fecha desc, h.historial_id desc
  limit 1;

  -- Estado anterior al "Atendido" (última fila no-Atendido del historial)
  select ec.estado_id into v_estado_prev
  from detalle_historial_estados h
  join estados_catalogo ec on ec.estado_id = h.estado_id
  where h.detalle_id = p_detalle_id and h.active and ec.nombre <> 'Atendido'
  order by h.fecha desc, h.historial_id desc
  limit 1;

  if v_estado_prev is null then
    select estado_id into v_estado_prev from estados_catalogo where nombre = 'En compra';
  end if;

  -- Devuelve el ítem al estado anterior sin duplicar historial
  perform set_config('app.skip_detalle_historial', '1', true);
  perform set_config('app.allow_detalle_cambio', '1', true);
  update detalle_pedido set estado_actual_id = v_estado_prev where detalle_id = p_detalle_id;
  perform set_config('app.allow_detalle_cambio', '0', true);
  perform set_config('app.skip_detalle_historial', '0', true);

  -- Elimina (soft-delete) la fila "Atendido por ingresos"
  if v_hist_atendido is not null then
    update detalle_historial_estados set active = false where historial_id = v_hist_atendido;
  end if;
end;
$$;

-- ----------------------------------------------------------------------------
-- 4. Triggers
-- ----------------------------------------------------------------------------

-- 4.a Encabezado: historial inicial al crear el pedido
create or replace function trg_pedido_ai_historial()
returns trigger
language plpgsql
as $$
begin
  insert into solicitud_historial_estados (pedido_id, estado_id)
  values (new.pedido_id, new.estado_actual_id);
  return new;
end;
$$;

drop trigger if exists trg_pedido_ai_historial on pedido;
create trigger trg_pedido_ai_historial
after insert on pedido
for each row execute function trg_pedido_ai_historial();

-- 4.b Detalle: historial por ítem + recálculo del encabezado
create or replace function trg_detalle_pedido_aiud()
returns trigger
language plpgsql
as $$
begin
  if tg_op = 'INSERT' then
    insert into detalle_historial_estados (detalle_id, estado_id)
    values (new.detalle_id, new.estado_actual_id);
    perform fn_recalcular_pedido_estado(new.pedido_id);
    perform fn_recalcular_pedido_atencion(new.pedido_id);

  elsif tg_op = 'UPDATE' then
    if new.estado_actual_id is distinct from old.estado_actual_id then
      -- Si viene del trigger de ingresos, ese ya insertó su fila con comentario
      if nullif(current_setting('app.skip_detalle_historial', true), '') is null then
        insert into detalle_historial_estados (detalle_id, estado_id)
        values (new.detalle_id, new.estado_actual_id);
      end if;
    end if;

    if new.cantidad_aprobada is distinct from old.cantidad_aprobada then
      perform fn_recalcular_detalle_atencion(new.detalle_id, false);
    end if;

    perform fn_recalcular_pedido_estado(new.pedido_id);
    perform fn_recalcular_pedido_atencion(new.pedido_id);

  elsif tg_op = 'DELETE' then
    perform fn_recalcular_pedido_estado(old.pedido_id);
    perform fn_recalcular_pedido_atencion(old.pedido_id);
  end if;

  return coalesce(new, old);
end;
$$;

drop trigger if exists trg_detalle_pedido_aiud on detalle_pedido;
create trigger trg_detalle_pedido_aiud
after insert or update of estado_actual_id, cantidad_aprobada, cantidad_atendida, estado_atencion, active or delete
on detalle_pedido
for each row execute function trg_detalle_pedido_aiud();

-- 4.b-bis Detalle: valida cambios manuales de estado por ítem.
--   * Bloquea cambios si el pedido aún no registró "En análisis" en su historial.
--   * Bloquea asignar "Atendido" manualmente (solo vía ingresos).
--   * "En compra" exige que el ítem ya haya sido aprobado.
--   * Al pasar a Rechazado/Observado, anula la cantidad aprobada.
--   * "Atendido" no puede cambiarse manualmente (solo vía eliminación de entregas).
create or replace function trg_detalle_pedido_bu_validaciones()
returns trigger
language plpgsql
as $$
begin
  if new.estado_actual_id is distinct from old.estado_actual_id then
    -- Bloqueo: "Atendido" es terminal/derivado y no se cambia manualmente
    if old.estado_actual_id = (select estado_id from estados_catalogo where nombre = 'Atendido')
       and nullif(current_setting('app.allow_detalle_cambio', true), '') is null then
      raise exception 'El ítem está "Atendido" y no puede cambiarse manualmente; elimina las entregas para revertirlo';
    end if;

    -- #3: el pedido debe haber pasado por "En análisis"
    if nullif(current_setting('app.allow_detalle_cambio', true), '') is null then
      if not exists (
        select 1
        from solicitud_historial_estados h
        join estados_catalogo ec on ec.estado_id = h.estado_id
        where h.pedido_id = new.pedido_id
          and ec.nombre = 'En análisis'
      ) then
        raise exception 'No se puede cambiar el estado del detalle: el pedido aún no está en "En análisis"';
      end if;
    end if;

    -- Bloqueo de "Atendido" manual
    if new.estado_actual_id = (select estado_id from estados_catalogo where nombre = 'Atendido')
       and nullif(current_setting('app.allow_atendido', true), '') is null then
      raise exception 'El estado Atendido se calcula por ingresos y no puede asignarse manualmente';
    end if;

    -- "En compra" exige que el ítem ya haya sido aprobado (tenga "Aprobado" en su historial)
    if new.estado_actual_id = (select estado_id from estados_catalogo where nombre = 'En compra') then
      if not exists (
        select 1
        from detalle_historial_estados dh
        join estados_catalogo dec on dec.estado_id = dh.estado_id
        where dh.detalle_id = new.detalle_id
          and dec.nombre = 'Aprobado'
      ) then
        raise exception 'No se puede pasar a "En compra": el ítem no ha sido aprobado';
      end if;
    end if;
  end if;

  -- Al pasar a Rechazado/Observado se anula la cantidad aprobada
  if new.estado_actual_id in (
    select estado_id from estados_catalogo where nombre in ('Rechazado', 'Observado')
  ) then
    new.cantidad_aprobada := 0;
  end if;

  return new;
end;
$$;

drop trigger if exists trg_detalle_pedido_bu_no_atendido_manual on detalle_pedido;
drop function if exists trg_detalle_pedido_bu_no_atendido_manual();

drop trigger if exists trg_detalle_pedido_bu_validaciones on detalle_pedido;
create trigger trg_detalle_pedido_bu_validaciones
before update of estado_actual_id on detalle_pedido
for each row execute function trg_detalle_pedido_bu_validaciones();

-- 4.c Ingresos: atenciones parciales
create or replace function trg_detalle_ingreso_aiud()
returns trigger
language plpgsql
as $$
begin
  if tg_op = 'INSERT' then
    perform fn_recalcular_detalle_atencion(new.detalle_id, true);
  elsif tg_op = 'UPDATE' then
    perform fn_recalcular_detalle_atencion(new.detalle_id, false);
    perform fn_revertir_atendido(new.detalle_id);
  elsif tg_op = 'DELETE' then
    perform fn_recalcular_detalle_atencion(old.detalle_id, false);
    perform fn_revertir_atendido(old.detalle_id);
  end if;
  return coalesce(new, old);
end;
$$;

drop trigger if exists trg_detalle_ingreso_aiud on detalle_ingreso;
create trigger trg_detalle_ingreso_aiud
after insert or update or delete on detalle_ingreso
for each row execute function trg_detalle_ingreso_aiud();

-- 4.c-bis Ingresos: valida cantidad de un ingreso.
--   * En INSERT: el ítem debe estar en fase aprobada.
--   * En INSERT y UPDATE: la cantidad total no puede superar la aprobada
--     (en UPDATE excluye la fila que se está editando).
create or replace function trg_detalle_ingreso_bi_aprobado()
returns trigger
language plpgsql
as $$
declare
  v_nombre   varchar(50);
  v_aprobada numeric(12,2);
  v_atendida numeric(12,2);
  v_total    numeric(12,2);
begin
  select ec.nombre, d.cantidad_aprobada into v_nombre, v_aprobada
  from detalle_pedido d
  join estados_catalogo ec on ec.estado_id = d.estado_actual_id
  where d.detalle_id = new.detalle_id;

  if tg_op = 'INSERT' then
    if v_nombre not in ('Aprobado', 'En cotización', 'En compra', 'Atendido') then
      raise exception 'No se puede registrar ingreso: el ítem no está aprobado';
    end if;
    select coalesce(sum(cantidad), 0) into v_atendida
    from detalle_ingreso
    where detalle_id = new.detalle_id and active;
    v_total := v_atendida + new.cantidad;
  else
    -- UPDATE: excluye la fila editada (permite editar entregas aunque el ítem ya esté Atendido)
    select coalesce(sum(cantidad), 0) into v_atendida
    from detalle_ingreso
    where detalle_id = new.detalle_id and active and ingreso_id <> new.ingreso_id;
    v_total := v_atendida + new.cantidad;
  end if;

  if v_total > v_aprobada then
    raise exception 'La cantidad atendida no puede superar la cantidad aprobada (aprobada=%, ya atendida=%, nuevo=%)', v_aprobada, v_atendida, new.cantidad;
  end if;

  return new;
end;
$$;

drop trigger if exists trg_detalle_ingreso_bi_aprobado on detalle_ingreso;
create trigger trg_detalle_ingreso_bi_aprobado
before insert or update of cantidad, detalle_id on detalle_ingreso
for each row execute function trg_detalle_ingreso_bi_aprobado();

-- 4.d Cambio de estado a nivel pedido desde el listado (RPC):
-- registra en solicitud_historial_estados (fecha + comentario manuales),
-- actualiza el encabezado y propaga a todos los ítems activos con
-- doble registro en detalle_historial_estados.
create or replace function fn_cambiar_estado_pedido(
  p_pedido_id bigint,
  p_estado_id int,
  p_fecha timestamptz default now(),
  p_comentario text default null
)
returns void
language plpgsql
security invoker
as $$
declare
  v_existe int;
  it record;
begin
  select estado_id into v_existe from estados_catalogo where estado_id = p_estado_id;
  if v_existe is null then
    raise exception 'Estado inexistente (estado_id=%)', p_estado_id;
  end if;

  if not exists (select 1 from estados_catalogo where estado_id = p_estado_id and ambito = 'pedido') then
    raise exception 'Este estado no puede asignarse manualmente al pedido';
  end if;

  if not exists (select 1 from pedido where pedido_id = p_pedido_id and active) then
    raise exception 'Pedido inexistente o inactivo (pedido_id=%)', p_pedido_id;
  end if;

  if exists (
    select 1
    from solicitud_historial_estados h
    join estados_catalogo ec on ec.estado_id = h.estado_id
    where h.pedido_id = p_pedido_id
      and ec.nombre = 'En análisis'
  ) then
    raise exception 'El pedido ya registró "En análisis" y su estado ya no puede editarse manualmente';
  end if;

  if (select estado_actual_id from pedido where pedido_id = p_pedido_id) = p_estado_id then
    raise exception 'El pedido ya se encuentra en este estado';
  end if;

  insert into solicitud_historial_estados (pedido_id, estado_id, fecha, comentario)
  values (p_pedido_id, p_estado_id, coalesce(p_fecha, now()), p_comentario);

  update pedido set estado_actual_id = p_estado_id where pedido_id = p_pedido_id;

  perform set_config('app.skip_detalle_historial', '1', true);
  perform set_config('app.skip_pedido_recalculo', '1', true);
  perform set_config('app.allow_detalle_cambio', '1', true);
  for it in
    select detalle_id from detalle_pedido where pedido_id = p_pedido_id and active
  loop
    update detalle_pedido set estado_actual_id = p_estado_id where detalle_id = it.detalle_id;
    insert into detalle_historial_estados (detalle_id, estado_id, fecha, comentario)
    values (it.detalle_id, p_estado_id, coalesce(p_fecha, now()), p_comentario);
  end loop;
  perform set_config('app.allow_detalle_cambio', '0', true);
  perform set_config('app.skip_pedido_recalculo', '0', true);
  perform set_config('app.skip_detalle_historial', '0', true);
end;
$$;

grant execute on function fn_cambiar_estado_pedido(bigint, int, timestamptz, text) to authenticated;

-- ----------------------------------------------------------------------------
-- 5. Índices
-- ----------------------------------------------------------------------------

create index if not exists idx_detalle_pedido_pedido     on detalle_pedido (pedido_id) where active;
create index if not exists idx_detalle_pedido_estado     on detalle_pedido (estado_actual_id) where active;
create index if not exists idx_detalle_ingreso_detalle   on detalle_ingreso (detalle_id) where active;
create index if not exists idx_solicitud_hist_pedido     on solicitud_historial_estados (pedido_id);
create index if not exists idx_detalle_hist_detalle      on detalle_historial_estados (detalle_id);

-- ----------------------------------------------------------------------------
-- 6. Vista de resumen para el listado
-- ----------------------------------------------------------------------------

-- create or replace no permite renombrar columnas de la vista; drop previo mantiene
-- el archivo idempotente cuando la vista vieja no tenía nro_sc.
drop view if exists vw_pedidos_resumen;

create or replace view vw_pedidos_resumen
with (security_invoker = true)
as
select
  p.pedido_id,
  p.fecha_emision,
  p.motivo,
  p.grupo_costo,
  p.nro_sc,
  p.autorizado,
  p.estado_atencion,
  ec.nombre as estado_actual,
  exists (
    select 1
    from solicitud_historial_estados h
    join estados_catalogo hec on hec.estado_id = h.estado_id
    where h.pedido_id = p.pedido_id
      and hec.nombre = 'En análisis'
  ) as paso_por_analisis,
  count(d.detalle_id) filter (where dec.nombre = 'Observado') as items_observados,
  count(d.detalle_id) filter (where dec.nombre = 'Rechazado') as items_rechazados,
  count(d.detalle_id) as total_items
from pedido p
join estados_catalogo ec on ec.estado_id = p.estado_actual_id
left join detalle_pedido d on d.pedido_id = p.pedido_id and d.active
left join estados_catalogo dec on dec.estado_id = d.estado_actual_id
where p.active
group by p.pedido_id, p.fecha_emision, p.motivo, p.grupo_costo, p.nro_sc, p.autorizado, p.estado_atencion, ec.nombre;

-- Vista de ítems (detalle) de todos los pedidos activos, con su N° SC.
drop view if exists vw_items_detalle;

create or replace view vw_items_detalle
with (security_invoker = true)
as
select
  d.detalle_id,
  d.pedido_id,
  p.nro_sc,
  d.nro_parte,
  d.material,
  d.equipo,
  d.fecha_aprox_atencion,
  d.cantidad_solicitada,
  d.cantidad_aprobada,
  d.cantidad_atendida,
  d.estado_atencion,
  ec.nombre as estado
from detalle_pedido d
join pedido p on p.pedido_id = d.pedido_id
join estados_catalogo ec on ec.estado_id = d.estado_actual_id
where p.active and d.active;

-- ----------------------------------------------------------------------------
-- 7. RLS — policies permisivas para authenticated (punto de partida)
-- ----------------------------------------------------------------------------

alter table estados_catalogo              enable row level security;
alter table pedido                        enable row level security;
alter table detalle_pedido                enable row level security;
alter table solicitud_historial_estados   enable row level security;
alter table detalle_ingreso               enable row level security;
alter table detalle_historial_estados     enable row level security;

drop policy if exists "authenticated_all" on estados_catalogo;
drop policy if exists "authenticated_all" on pedido;
drop policy if exists "authenticated_all" on detalle_pedido;
drop policy if exists "authenticated_all" on solicitud_historial_estados;
drop policy if exists "authenticated_all" on detalle_ingreso;
drop policy if exists "authenticated_all" on detalle_historial_estados;

create policy "authenticated_all" on estados_catalogo
  for all to authenticated using (true) with check (true);
create policy "authenticated_all" on pedido
  for all to authenticated using (true) with check (true);
create policy "authenticated_all" on detalle_pedido
  for all to authenticated using (true) with check (true);
create policy "authenticated_all" on solicitud_historial_estados
  for all to authenticated using (true) with check (true);
create policy "authenticated_all" on detalle_ingreso
  for all to authenticated using (true) with check (true);
create policy "authenticated_all" on detalle_historial_estados
  for all to authenticated using (true) with check (true);

-- ----------------------------------------------------------------------------
-- 8. Grants explícitos
-- ----------------------------------------------------------------------------

grant usage, select on all sequences in schema public to authenticated;
grant select, insert, update, delete on estados_catalogo,
  pedido, detalle_pedido, solicitud_historial_estados,
  detalle_ingreso, detalle_historial_estados to authenticated;
grant select on vw_pedidos_resumen to authenticated;
grant select on vw_items_detalle to authenticated;
