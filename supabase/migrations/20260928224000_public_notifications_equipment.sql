-- Consultas públicas compactas con equipo, filtro de equipo y conteo de atendidos.
-- Los RPC existentes se conservan para no romper consumidores anteriores.

create or replace function public.fn_listar_pedidos_publicos_paginado_con_equipo(
  p_busqueda_sc text default null,
  p_busqueda_item text default null,
  p_busqueda_equipo text default null,
  p_estado text default null,
  p_grupo_costo text default null,
  p_pagina integer default 1,
  p_por_pagina integer default 12
)
returns table(
  pedido_id bigint,
  fecha_emision date,
  motivo text,
  grupo_costo text,
  nro_sc text,
  estado_atencion text,
  estado_actual text,
  items_observados bigint,
  items_rechazados bigint,
  total_items bigint,
  total_registros bigint,
  items_atendidos bigint
)
language sql
stable
security definer
set search_path = ''
as $$
  with resumen as (
    select
      p.pedido_id,
      p.fecha_emision,
      p.motivo::text as motivo,
      p.grupo_costo::text as grupo_costo,
      p.nro_sc::text as nro_sc,
      p.estado_atencion::text as estado_atencion,
      ec.nombre::text as estado_actual,
      count(d.detalle_id) filter (where dec.nombre = 'Observado') as items_observados,
      count(d.detalle_id) filter (where dec.nombre = 'Rechazado') as items_rechazados,
      count(d.detalle_id) as total_items,
      count(d.detalle_id) filter (where dec.nombre = 'Atendido') as items_atendidos
    from public.pedido p
    join public.estados_catalogo ec on ec.estado_id = p.estado_actual_id
    left join public.detalle_pedido d on d.pedido_id = p.pedido_id and d.active
    left join public.estados_catalogo dec on dec.estado_id = d.estado_actual_id
    where p.active
      and (nullif(btrim(p_busqueda_sc), '') is null or p.nro_sc::text ilike '%' || btrim(p_busqueda_sc) || '%')
      and (nullif(btrim(p_estado), '') is null or ec.nombre = btrim(p_estado))
      and (nullif(btrim(p_grupo_costo), '') is null or p.grupo_costo = btrim(p_grupo_costo))
      and (
        nullif(btrim(p_busqueda_item), '') is null
        or exists (
          select 1 from public.detalle_pedido di
          where di.pedido_id = p.pedido_id and di.active
            and (coalesce(di.material, '') ilike '%' || btrim(p_busqueda_item) || '%'
              or coalesce(di.nro_parte, '') ilike '%' || btrim(p_busqueda_item) || '%')
        )
      )
      and (
        nullif(btrim(p_busqueda_equipo), '') is null
        or exists (
          select 1 from public.detalle_pedido de
          where de.pedido_id = p.pedido_id and de.active
            and coalesce(de.equipo, '') ilike '%' || btrim(p_busqueda_equipo) || '%'
        )
      )
    group by p.pedido_id, p.fecha_emision, p.motivo, p.grupo_costo, p.nro_sc, p.estado_atencion, ec.nombre
  )
  select
    resumen.pedido_id, resumen.fecha_emision, resumen.motivo, resumen.grupo_costo,
    resumen.nro_sc, resumen.estado_atencion, resumen.estado_actual,
    resumen.items_observados, resumen.items_rechazados, resumen.total_items,
    count(*) over()::bigint, resumen.items_atendidos
  from resumen
  order by resumen.fecha_emision desc, resumen.pedido_id desc
  limit least(greatest(coalesce(p_por_pagina, 12), 1), 48)
  offset (greatest(coalesce(p_pagina, 1), 1) - 1) * least(greatest(coalesce(p_por_pagina, 12), 1), 48);
$$;

create or replace function public.fn_alertas_publicas_vigentes_con_equipo(
  p_busqueda_sc text default null,
  p_busqueda_item text default null,
  p_busqueda_equipo text default null,
  p_estado text default null,
  p_grupo_costo text default null
)
returns table(
  tipo text,
  pedido_id bigint,
  detalle_id bigint,
  nro_sc text,
  grupo_costo text,
  material text,
  nro_parte text,
  estado_actual text,
  fecha_aprox_atencion date,
  dias_retraso integer,
  equipo text
)
language sql
stable
security definer
set search_path = ''
as $$
  select
    case
      when ec.nombre = 'Observado' then 'observado'
      when ec.nombre = 'Rechazado' then 'rechazado'
      when d.fecha_aprox_atencion = (now() at time zone 'America/Lima')::date then 'vence_hoy'
      when d.fecha_aprox_atencion < (now() at time zone 'America/Lima')::date then 'retraso'
      else 'sin_fecha'
    end::text,
    p.pedido_id,
    d.detalle_id,
    p.nro_sc::text,
    p.grupo_costo::text,
    d.material::text,
    d.nro_parte::text,
    ec.nombre::text,
    d.fecha_aprox_atencion,
    case when d.fecha_aprox_atencion < (now() at time zone 'America/Lima')::date then (
      select count(*)::integer
      from generate_series(d.fecha_aprox_atencion + 1, (now() at time zone 'America/Lima')::date, interval '1 day') as calendario(dia)
      where extract(isodow from calendario.dia) <> 7
    ) else 0 end,
    d.equipo::text
  from public.detalle_pedido d
  join public.pedido p on p.pedido_id = d.pedido_id and p.active
  join public.estados_catalogo ec on ec.estado_id = d.estado_actual_id
  join public.estados_catalogo pec on pec.estado_id = p.estado_actual_id
  where d.active
    and (
      ec.nombre in ('Observado', 'Rechazado')
      or (
        ec.nombre <> 'Atendido'
        and greatest(coalesce(d.cantidad_aprobada, 0) - coalesce(d.cantidad_atendida, 0), 0) > 0
        and (
          d.fecha_aprox_atencion <= (now() at time zone 'America/Lima')::date
          or (d.fecha_aprox_atencion is null and exists (
            select 1
            from public.detalle_historial_estados h
            join public.estados_catalogo aprob on aprob.estado_id = h.estado_id
            where h.detalle_id = d.detalle_id and h.active and aprob.nombre = 'Aprobado'
          ))
        )
      )
    )
    and (nullif(btrim(p_busqueda_sc), '') is null or p.nro_sc::text ilike '%' || btrim(p_busqueda_sc) || '%')
    and (nullif(btrim(p_estado), '') is null or pec.nombre = btrim(p_estado))
    and (nullif(btrim(p_grupo_costo), '') is null or p.grupo_costo = btrim(p_grupo_costo))
    and (nullif(btrim(p_busqueda_item), '') is null or
      coalesce(d.material, '') ilike '%' || btrim(p_busqueda_item) || '%' or
      coalesce(d.nro_parte, '') ilike '%' || btrim(p_busqueda_item) || '%')
    and (nullif(btrim(p_busqueda_equipo), '') is null or
      coalesce(d.equipo, '') ilike '%' || btrim(p_busqueda_equipo) || '%')
  order by case
    when ec.nombre = 'Observado' then 4
    when ec.nombre = 'Rechazado' then 5
    when d.fecha_aprox_atencion < (now() at time zone 'America/Lima')::date then 1
    when d.fecha_aprox_atencion = (now() at time zone 'America/Lima')::date then 2
    else 3 end,
    p.fecha_emision desc, d.detalle_id;
$$;

create or replace function public.fn_listar_notificaciones_con_equipo(
  p_solo_no_leidas boolean default true,
  p_limite integer default 100
)
returns table(
  evento_id uuid,
  tipo text,
  severidad text,
  pedido_id bigint,
  detalle_id bigint,
  titulo text,
  mensaje text,
  metadata jsonb,
  creado_en timestamptz,
  fecha_operativa date,
  dias_retraso integer,
  resuelto_en timestamptz,
  leido boolean,
  etiqueta_tipo text,
  nro_sc text,
  material text,
  estado_actual text,
  equipo text
)
language sql
stable
security definer
set search_path = ''
as $$
  select
    n.evento_id, n.tipo, n.severidad, n.pedido_id, n.detalle_id, n.titulo,
    n.mensaje, n.metadata, n.creado_en, n.fecha_operativa, n.dias_retraso,
    n.resuelto_en, n.leido, n.etiqueta_tipo, n.nro_sc, n.material,
    n.estado_actual,
    coalesce(
      n.metadata->>'equipo',
      d.equipo::text,
      (
        select string_agg(distinct di.equipo::text, ' · ')
        from pg_catalog.jsonb_array_elements(
          case when pg_catalog.jsonb_typeof(n.metadata->'items') = 'array'
            then n.metadata->'items' else '[]'::jsonb end
        ) as item(valor)
        join public.detalle_pedido di
          on di.detalle_id = nullif(item.valor->>'detalle_id', '')::bigint
        where nullif(di.equipo, '') is not null
      )
    )::text
  from public.fn_listar_notificaciones(p_solo_no_leidas, p_limite) n
  left join public.detalle_pedido d on d.detalle_id = n.detalle_id;
$$;

revoke all on function public.fn_listar_pedidos_publicos_paginado_con_equipo(text, text, text, text, text, integer, integer) from public;
revoke all on function public.fn_alertas_publicas_vigentes_con_equipo(text, text, text, text, text) from public;
revoke all on function public.fn_listar_notificaciones_con_equipo(boolean, integer) from public;
grant execute on function public.fn_listar_pedidos_publicos_paginado_con_equipo(text, text, text, text, text, integer, integer) to anon, authenticated;
grant execute on function public.fn_alertas_publicas_vigentes_con_equipo(text, text, text, text, text) to anon, authenticated;
grant execute on function public.fn_listar_notificaciones_con_equipo(boolean, integer) to authenticated;

notify pgrst, 'reload schema';
