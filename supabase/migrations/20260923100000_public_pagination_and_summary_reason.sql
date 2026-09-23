-- La consulta pública obtiene únicamente la página solicitada.
create or replace function public.fn_listar_pedidos_publicos_paginado(
  p_busqueda_sc text default null,
  p_busqueda_item text default null,
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
  total_registros bigint
)
language sql
security definer
set search_path = ''
stable
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
      count(d.detalle_id) as total_items
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
    group by p.pedido_id, p.fecha_emision, p.motivo, p.grupo_costo, p.nro_sc, p.estado_atencion, ec.nombre
  )
  select resumen.*, count(*) over()::bigint as total_registros
  from resumen
  order by fecha_emision desc, pedido_id desc
  limit least(greatest(coalesce(p_por_pagina, 12), 1), 48)
  offset (greatest(coalesce(p_pagina, 1), 1) - 1) * least(greatest(coalesce(p_por_pagina, 12), 1), 48);
$$;

create or replace function public.fn_listar_filtros_pedidos_publicos_permanente()
returns table(estado_actual text, grupo_costo text)
language sql
security definer
set search_path = ''
stable
as $$
  select distinct ec.nombre::text, p.grupo_costo::text
  from public.pedido p
  join public.estados_catalogo ec on ec.estado_id = p.estado_actual_id
  where p.active;
$$;

create or replace function public.fn_resumen_pedido_publico_permanente(p_pedido_id bigint)
returns table(
  detalle_id bigint,
  nro_parte text,
  material text,
  equipo text,
  cantidad_solicitada numeric,
  cantidad_aprobada numeric,
  cantidad_atendida numeric,
  fecha_aprox_atencion date,
  estado_atencion text,
  estado_actual text,
  comentario text
)
language sql
security definer
set search_path = ''
stable
as $$
  select
    d.detalle_id,
    d.nro_parte::text,
    d.material::text,
    d.equipo::text,
    d.cantidad_solicitada,
    d.cantidad_aprobada,
    d.cantidad_atendida,
    d.fecha_aprox_atencion,
    d.estado_atencion::text,
    ec.nombre::text,
    h.comentario::text
  from public.detalle_pedido d
  join public.estados_catalogo ec on ec.estado_id = d.estado_actual_id
  join public.pedido p on p.pedido_id = d.pedido_id
  left join lateral (
    select dh.comentario
    from public.detalle_historial_estados dh
    where dh.detalle_id = d.detalle_id
      and dh.estado_id = d.estado_actual_id
      and dh.active
    order by dh.fecha desc, dh.historial_id desc
    limit 1
  ) h on true
  where d.pedido_id = p_pedido_id and d.active and p.active
  order by d.detalle_id;
$$;

revoke all on function public.fn_listar_pedidos_publicos_paginado(text, text, text, text, integer, integer) from public;
revoke all on function public.fn_listar_filtros_pedidos_publicos_permanente() from public;
revoke all on function public.fn_resumen_pedido_publico_permanente(bigint) from public;
grant execute on function public.fn_listar_pedidos_publicos_paginado(text, text, text, text, integer, integer) to anon, authenticated;
grant execute on function public.fn_listar_filtros_pedidos_publicos_permanente() to anon, authenticated;
grant execute on function public.fn_resumen_pedido_publico_permanente(bigint) to anon, authenticated;
notify pgrst, 'reload schema';
