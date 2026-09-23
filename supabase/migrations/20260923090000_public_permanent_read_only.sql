-- Consulta pública permanente y de solo lectura.
-- No se habilita acceso directo a las tablas: anon solo puede ejecutar estas RPC.

create or replace function public.fn_listar_pedidos_publicos_permanente(
  p_busqueda_sc text default null,
  p_busqueda_item text default null,
  p_estado text default null,
  p_grupo_costo text default null
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
  total_items bigint
)
language plpgsql
security definer
set search_path = ''
as $$
begin
  return query
  select
    p.pedido_id,
    p.fecha_emision,
    p.motivo::text,
    p.grupo_costo::text,
    p.nro_sc::text,
    p.estado_atencion::text,
    ec.nombre::text,
    count(d.detalle_id) filter (where dec.nombre = 'Observado'),
    count(d.detalle_id) filter (where dec.nombre = 'Rechazado'),
    count(d.detalle_id)
  from public.pedido p
  join public.estados_catalogo ec on ec.estado_id = p.estado_actual_id
  left join public.detalle_pedido d on d.pedido_id = p.pedido_id and d.active
  left join public.estados_catalogo dec on dec.estado_id = d.estado_actual_id
  where p.active
    and (
      nullif(btrim(p_busqueda_sc), '') is null
      or p.nro_sc::text ilike '%' || btrim(p_busqueda_sc) || '%'
    )
    and (
      nullif(btrim(p_estado), '') is null
      or ec.nombre = btrim(p_estado)
    )
    and (
      nullif(btrim(p_grupo_costo), '') is null
      or p.grupo_costo = btrim(p_grupo_costo)
    )
    and (
      nullif(btrim(p_busqueda_item), '') is null
      or exists (
        select 1
        from public.detalle_pedido di
        where di.pedido_id = p.pedido_id
          and di.active
          and (
            coalesce(di.material, '') ilike '%' || btrim(p_busqueda_item) || '%'
            or coalesce(di.nro_parte, '') ilike '%' || btrim(p_busqueda_item) || '%'
          )
      )
    )
  group by p.pedido_id, p.fecha_emision, p.motivo, p.grupo_costo, p.nro_sc, p.estado_atencion, ec.nombre
  order by p.fecha_emision desc, p.pedido_id desc;
end;
$$;

create or replace function public.fn_ver_detalle_pedido_publico_permanente(p_pedido_id bigint)
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
  estado_actual text
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
    ec.nombre::text
  from public.detalle_pedido d
  join public.estados_catalogo ec on ec.estado_id = d.estado_actual_id
  join public.pedido p on p.pedido_id = d.pedido_id
  where d.pedido_id = p_pedido_id
    and d.active
    and p.active
  order by d.detalle_id;
$$;

revoke all on function public.fn_listar_pedidos_publicos_permanente(text, text, text, text) from public;
revoke all on function public.fn_ver_detalle_pedido_publico_permanente(bigint) from public;
grant execute on function public.fn_listar_pedidos_publicos_permanente(text, text, text, text) to anon, authenticated;
grant execute on function public.fn_ver_detalle_pedido_publico_permanente(bigint) to anon, authenticated;
