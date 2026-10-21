-- APIs públicas de solo lectura para Unidad Corona Mantenimiento.
-- No aceptan grupo como parámetro, para impedir consultar otros grupos.

create or replace function public.fn_api_publica_pedidos_ucm()
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
  items_atendidos bigint
)
language sql
stable
security definer
set search_path = ''
as $$
  select
    p.pedido_id,
    p.fecha_emision,
    p.motivo::text,
    p.grupo_costo::text,
    p.nro_sc::text,
    p.estado_atencion::text,
    ep.nombre::text,
    count(d.detalle_id) filter (where ed.nombre = 'Observado'),
    count(d.detalle_id) filter (where ed.nombre = 'Rechazado'),
    count(d.detalle_id),
    count(d.detalle_id) filter (where ed.nombre = 'Atendido')
  from public.pedido p
  join public.estados_catalogo ep on ep.estado_id = p.estado_actual_id
  left join public.detalle_pedido d
    on d.pedido_id = p.pedido_id
    and d.active
  left join public.estados_catalogo ed on ed.estado_id = d.estado_actual_id
  where p.active
    and p.grupo_costo = 'Unidad Corona Mantenimiento'
  group by
    p.pedido_id,
    p.fecha_emision,
    p.motivo,
    p.grupo_costo,
    p.nro_sc,
    p.estado_atencion,
    ep.nombre
  order by p.fecha_emision desc nulls last, p.pedido_id desc;
$$;

comment on function public.fn_api_publica_pedidos_ucm() is
  'API pública de solo lectura: todos los encabezados activos del grupo Unidad Corona Mantenimiento.';

create or replace function public.fn_api_publica_detalle_ucm()
returns table(
  detalle_id bigint,
  pedido_id bigint,
  nro_sc text,
  grupo_costo text,
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
stable
security definer
set search_path = ''
as $$
  select
    d.detalle_id,
    p.pedido_id,
    p.nro_sc::text,
    p.grupo_costo::text,
    d.nro_parte::text,
    d.material::text,
    d.equipo::text,
    d.cantidad_solicitada,
    d.cantidad_aprobada,
    d.cantidad_atendida,
    d.fecha_aprox_atencion,
    d.estado_atencion::text,
    ed.nombre::text
  from public.detalle_pedido d
  join public.pedido p on p.pedido_id = d.pedido_id
  join public.estados_catalogo ed on ed.estado_id = d.estado_actual_id
  where d.active
    and p.active
    and p.grupo_costo = 'Unidad Corona Mantenimiento'
  order by p.fecha_emision desc nulls last, p.pedido_id desc, d.detalle_id;
$$;

comment on function public.fn_api_publica_detalle_ucm() is
  'API pública de solo lectura: todos los detalles activos de pedidos del grupo Unidad Corona Mantenimiento.';

revoke all on function public.fn_api_publica_pedidos_ucm() from public, anon, authenticated;
revoke all on function public.fn_api_publica_detalle_ucm() from public, anon, authenticated;
grant execute on function public.fn_api_publica_pedidos_ucm() to anon, authenticated;
grant execute on function public.fn_api_publica_detalle_ucm() to anon, authenticated;

notify pgrst, 'reload schema';
