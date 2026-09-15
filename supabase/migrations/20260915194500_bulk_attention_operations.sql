-- Operaciones masivas de atención. Ambas RPC son atómicas y validan que los
-- ítems sigan perteneciendo al pedido antes de tocar información.

create table if not exists public.detalle_fecha_aprox_historial (
  historial_id bigserial primary key,
  detalle_id bigint not null references public.detalle_pedido(detalle_id),
  fecha_anterior date,
  fecha_nueva date,
  comentario text,
  usuario_id uuid,
  timestamp timestamptz not null default now()
);

alter table public.detalle_fecha_aprox_historial enable row level security;
drop policy if exists authenticated_select on public.detalle_fecha_aprox_historial;
create policy authenticated_select on public.detalle_fecha_aprox_historial
  for select to authenticated using (true);
grant select on public.detalle_fecha_aprox_historial to authenticated;

create or replace function public.fn_actualizar_fecha_aprox_items(
  p_pedido_id bigint,
  p_detalle_ids bigint[],
  p_fecha date default null,
  p_comentario text default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_total_entrada int;
  v_total_validos int;
begin
  if auth.uid() is null or coalesce(auth.jwt() -> 'app_metadata' ->> 'role', '') = 'viewer' then
    raise exception 'No tienes permiso para actualizar fechas estimadas';
  end if;

  select cardinality(p_detalle_ids), count(distinct detalle_id)
    into v_total_entrada, v_total_validos
  from unnest(p_detalle_ids) as detalle_id;
  if coalesce(v_total_entrada, 0) = 0 or v_total_entrada <> v_total_validos then
    raise exception 'La selección de ítems no es válida';
  end if;
  if not exists (select 1 from pedido where pedido_id = p_pedido_id and active) then
    raise exception 'El pedido no existe o está inactivo';
  end if;

  select count(*) into v_total_validos
  from detalle_pedido
  where pedido_id = p_pedido_id and active and detalle_id = any(p_detalle_ids);
  if v_total_validos <> v_total_entrada then
    raise exception 'Uno o más ítems no pertenecen al pedido o ya no están activos';
  end if;

  perform 1 from detalle_pedido where detalle_id = any(p_detalle_ids) for update;

  insert into detalle_fecha_aprox_historial (
    detalle_id, fecha_anterior, fecha_nueva, comentario, usuario_id
  )
  select detalle_id, fecha_aprox_atencion, p_fecha, nullif(btrim(p_comentario), ''), auth.uid()
  from detalle_pedido
  where detalle_id = any(p_detalle_ids)
    and fecha_aprox_atencion is distinct from p_fecha;

  update detalle_pedido
  set fecha_aprox_atencion = p_fecha
  where detalle_id = any(p_detalle_ids);
end;
$$;

create or replace function public.fn_registrar_ingresos_items(
  p_pedido_id bigint,
  p_ingresos jsonb,
  p_fecha date default current_date,
  p_documento text default null,
  p_comentario text default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_total_entrada int;
  v_total_distintos int;
  v_detalle_ids bigint[];
  v_total_validos int;
begin
  if auth.uid() is null or coalesce(auth.jwt() -> 'app_metadata' ->> 'role', '') = 'viewer' then
    raise exception 'No tienes permiso para registrar entregas';
  end if;
  if p_ingresos is null or jsonb_typeof(p_ingresos) <> 'array' or jsonb_array_length(p_ingresos) = 0 then
    raise exception 'Debes indicar al menos una entrega';
  end if;

  select count(*), count(distinct detalle_id), array_agg(detalle_id)
    into v_total_entrada, v_total_distintos, v_detalle_ids
  from jsonb_to_recordset(p_ingresos) as entrada(detalle_id bigint, cantidad numeric);
  if v_total_entrada = 0 or array_position(v_detalle_ids, null) is not null
     or v_total_entrada <> v_total_distintos
     or exists (select 1 from jsonb_to_recordset(p_ingresos) as entrada(detalle_id bigint, cantidad numeric) where cantidad is null or cantidad <= 0) then
    raise exception 'Cada entrega debe tener un ítem único y una cantidad mayor que cero';
  end if;
  if not exists (select 1 from pedido where pedido_id = p_pedido_id and active) then
    raise exception 'El pedido no existe o está inactivo';
  end if;

  select count(*) into v_total_validos
  from detalle_pedido
  where pedido_id = p_pedido_id and active and detalle_id = any(v_detalle_ids);
  if v_total_validos <> v_total_entrada then
    raise exception 'Uno o más ítems no pertenecen al pedido o ya no están activos';
  end if;
  perform 1 from detalle_pedido where detalle_id = any(v_detalle_ids) for update;

  if exists (
    select 1
    from detalle_pedido d
    join estados_catalogo ec on ec.estado_id = d.estado_actual_id
    where d.detalle_id = any(v_detalle_ids)
      and ec.nombre not in ('Aprobado', 'En cotización', 'En compra', 'Atendido')
  ) then
    raise exception 'Todos los ítems con entrega deben estar aprobados';
  end if;
  if exists (
    select 1
    from jsonb_to_recordset(p_ingresos) as entrada(detalle_id bigint, cantidad numeric)
    join detalle_pedido d on d.detalle_id = entrada.detalle_id
    left join lateral (
      select coalesce(sum(cantidad), 0) as atendida
      from detalle_ingreso where detalle_id = d.detalle_id and active
    ) ingresos on true
    where entrada.cantidad > d.cantidad_aprobada - ingresos.atendida
  ) then
    raise exception 'Una cantidad supera el saldo pendiente de su ítem';
  end if;

  insert into detalle_ingreso (detalle_id, cantidad, fecha, documento, comentario)
  select detalle_id, cantidad, coalesce(p_fecha, current_date), nullif(left(btrim(p_documento), 25), ''), nullif(btrim(p_comentario), '')
  from jsonb_to_recordset(p_ingresos) as entrada(detalle_id bigint, cantidad numeric);
end;
$$;

revoke all on function public.fn_actualizar_fecha_aprox_items(bigint, bigint[], date, text) from public;
revoke all on function public.fn_registrar_ingresos_items(bigint, jsonb, date, text, text) from public;
grant execute on function public.fn_actualizar_fecha_aprox_items(bigint, bigint[], date, text) to authenticated;
grant execute on function public.fn_registrar_ingresos_items(bigint, jsonb, date, text, text) to authenticated;
