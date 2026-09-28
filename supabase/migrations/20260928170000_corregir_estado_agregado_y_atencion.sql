-- Evita que un ítem Atendido oculte otros ítems aún en proceso y que los ítems
-- sin cantidad aprobada se interpreten como completados para la atención.

create or replace function public.fn_recalcular_pedido_estado(p_pedido_id bigint)
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
  if current_setting('app.skip_pedido_recalculo', true) = '1' then
    return;
  end if;

  select
    count(*) filter (where d.active),
    count(*) filter (where d.active and ec.es_excepcion),
    count(*) filter (where d.active and ec.nombre = 'Rechazado')
    into v_total_activos, v_total_excepcion, v_total_rechazado
  from public.detalle_pedido d
  join public.estados_catalogo ec on ec.estado_id = d.estado_actual_id
  where d.pedido_id = p_pedido_id;

  if v_total_activos = 0 then
    return;
  end if;

  if v_total_excepcion = v_total_activos then
    if v_total_rechazado = v_total_activos then
      select estado_id into v_nuevo_estado from public.estados_catalogo where nombre = 'Rechazado';
    else
      select estado_id into v_nuevo_estado from public.estados_catalogo where nombre = 'Observado';
    end if;
  else
    select d.estado_actual_id into v_nuevo_estado
    from public.detalle_pedido d
    join public.estados_catalogo ec on ec.estado_id = d.estado_actual_id
    where d.pedido_id = p_pedido_id
      and d.active
      and not ec.es_excepcion
      and ec.nombre <> 'Atendido'
    order by ec.orden desc nulls last
    limit 1;

    if v_nuevo_estado is null then
      select d.estado_actual_id into v_nuevo_estado
      from public.detalle_pedido d
      join public.estados_catalogo ec on ec.estado_id = d.estado_actual_id
      where d.pedido_id = p_pedido_id
        and d.active
        and not ec.es_excepcion
      order by ec.orden desc nulls last
      limit 1;
    end if;
  end if;

  select estado_actual_id into v_actual_estado from public.pedido where pedido_id = p_pedido_id;

  if v_actual_estado is distinct from v_nuevo_estado then
    update public.pedido set estado_actual_id = v_nuevo_estado where pedido_id = p_pedido_id;
    insert into public.solicitud_historial_estados (pedido_id, estado_id)
    values (p_pedido_id, v_nuevo_estado);
  end if;
end;
$$;

create or replace function public.fn_recalcular_pedido_atencion(p_pedido_id bigint)
returns void
language plpgsql
as $$
declare
  v_normales   int;
  v_atendidos  int;
  v_pendientes int;
  v_atencion   varchar(30);
begin
  select
    count(*) filter (where d.active and not ec.es_excepcion),
    count(*) filter (where d.active and not ec.es_excepcion and d.cantidad_atendida > 0),
    count(*) filter (where d.active and not ec.es_excepcion and (
      ec.nombre <> 'Atendido'
      or (coalesce(d.cantidad_aprobada, 0) - coalesce(d.cantidad_atendida, 0)) > 0
    ))
    into v_normales, v_atendidos, v_pendientes
  from public.detalle_pedido d
  join public.estados_catalogo ec on ec.estado_id = d.estado_actual_id
  where d.pedido_id = p_pedido_id;

  if v_normales = 0 then
    v_atencion := null;
  elsif v_atendidos = 0 then
    v_atencion := 'PENDIENTE';
  elsif v_pendientes = 0 then
    v_atencion := 'COMPLETO';
  else
    v_atencion := 'PARCIAL';
  end if;

  update public.pedido set estado_atencion = v_atencion where pedido_id = p_pedido_id;
end;
$$;

-- Recalcula el pedido informado, respetando el historial de cambios.
do $$
declare
  v_pedido record;
begin
  for v_pedido in select pedido_id from public.pedido where active and nro_sc::text = '1436' loop
    perform public.fn_recalcular_pedido_estado(v_pedido.pedido_id);
    perform public.fn_recalcular_pedido_atencion(v_pedido.pedido_id);
  end loop;
end;
$$;
