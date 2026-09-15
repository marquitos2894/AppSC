-- Cambio de estado masivo y trazable para un subconjunto de ítems de una SC.
-- La función es atómica: si un ítem no es válido no se modifica ninguno.

create or replace function public.fn_cambiar_estado_items(
  p_pedido_id bigint,
  p_estado_id int,
  p_detalles jsonb,
  p_fecha timestamptz default now(),
  p_comentario text default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_estado_nombre text;
  v_detalle_ids bigint[];
  v_total_entrada int;
  v_total_distintos int;
  v_total_validos int;
begin
  if auth.uid() is null or coalesce(auth.jwt() -> 'app_metadata' ->> 'role', '') = 'viewer' then
    raise exception 'No tienes permiso para cambiar estados';
  end if;

  if p_detalles is null or jsonb_typeof(p_detalles) <> 'array' or jsonb_array_length(p_detalles) = 0 then
    raise exception 'Debes seleccionar al menos un ítem';
  end if;

  select nombre into v_estado_nombre
  from estados_catalogo
  where estado_id = p_estado_id
    and active
    and ambito = 'detalle';

  if v_estado_nombre is null then
    raise exception 'El estado seleccionado no es válido para un ítem';
  end if;

  select
    count(*),
    count(distinct detalle_id),
    array_agg(detalle_id)
  into v_total_entrada, v_total_distintos, v_detalle_ids
  from jsonb_to_recordset(p_detalles) as entrada(
    detalle_id bigint,
    cantidad_aprobada numeric
  );

  if v_total_entrada = 0
     or array_position(v_detalle_ids, null) is not null
     or v_total_entrada <> v_total_distintos then
    raise exception 'La selección de ítems no es válida';
  end if;

  if not exists (
    select 1 from pedido where pedido_id = p_pedido_id and active
  ) then
    raise exception 'El pedido no existe o está inactivo';
  end if;

  select count(*) into v_total_validos
  from detalle_pedido
  where pedido_id = p_pedido_id
    and active
    and detalle_id = any(v_detalle_ids);

  if v_total_validos <> v_total_entrada then
    raise exception 'Uno o más ítems no pertenecen al pedido o ya no están activos';
  end if;

  -- Bloquea la selección antes de validar sus estados para evitar cambios paralelos.
  perform 1
  from detalle_pedido
  where detalle_id = any(v_detalle_ids)
  for update;

  -- Bloquea cambios manuales de ítems atendidos antes de hacer cualquier actualización.
  if exists (
    select 1
    from detalle_pedido d
    join estados_catalogo ec on ec.estado_id = d.estado_actual_id
    where d.detalle_id = any(v_detalle_ids)
      and ec.nombre = 'Atendido'
  ) then
    raise exception 'No se puede cambiar masivamente un ítem Atendido';
  end if;

  if exists (
    select 1 from detalle_pedido
    where detalle_id = any(v_detalle_ids)
      and estado_actual_id = p_estado_id
  ) then
    raise exception 'Quita de la selección los ítems que ya tienen el estado elegido';
  end if;

  if v_estado_nombre = 'Aprobado' and exists (
    select 1
    from jsonb_to_recordset(p_detalles) as entrada(
      detalle_id bigint,
      cantidad_aprobada numeric
    )
    where cantidad_aprobada is null or cantidad_aprobada < 0
  ) then
    raise exception 'Indica una cantidad aprobada válida para cada ítem';
  end if;

  if v_estado_nombre = 'En compra' and exists (
    select 1
    from detalle_pedido d
    where d.detalle_id = any(v_detalle_ids)
      and not exists (
        select 1
        from detalle_historial_estados h
        join estados_catalogo ec on ec.estado_id = h.estado_id
        where h.detalle_id = d.detalle_id
          and ec.nombre = 'Aprobado'
      )
  ) then
    raise exception 'Todos los ítems seleccionados deben haber sido aprobados antes de pasar a En compra';
  end if;

  -- Se suprimen los disparadores por fila y se escribe un único historial común por ítem.
  perform set_config('app.skip_detalle_historial', '1', true);
  perform set_config('app.skip_pedido_recalculo', '1', true);

  update detalle_pedido d
  set estado_actual_id = p_estado_id,
      cantidad_aprobada = case
        when v_estado_nombre = 'Aprobado' then entrada.cantidad_aprobada
        else d.cantidad_aprobada
      end
  from jsonb_to_recordset(p_detalles) as entrada(
    detalle_id bigint,
    cantidad_aprobada numeric
  )
  where d.detalle_id = entrada.detalle_id;

  insert into detalle_historial_estados (detalle_id, estado_id, fecha, comentario)
  select
    entrada.detalle_id,
    p_estado_id,
    coalesce(p_fecha, now()),
    nullif(btrim(p_comentario), '')
  from jsonb_to_recordset(p_detalles) as entrada(
    detalle_id bigint,
    cantidad_aprobada numeric
  );

  perform set_config('app.skip_pedido_recalculo', '0', true);
  perform fn_recalcular_pedido_estado(p_pedido_id);
  perform fn_recalcular_pedido_atencion(p_pedido_id);
end;
$$;

revoke all on function public.fn_cambiar_estado_items(bigint, int, jsonb, timestamptz, text) from public;
grant execute on function public.fn_cambiar_estado_items(bigint, int, jsonb, timestamptz, text) to authenticated;
