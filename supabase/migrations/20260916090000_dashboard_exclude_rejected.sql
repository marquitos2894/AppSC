-- Un pedido rechazado no representa atención pendiente, incluso cuando su
-- estado de atención heredado aún sea PENDIENTE.

create or replace function public.dashboard_kpis(
  p_desde date,
  p_hasta date,
  p_grupo_costo text default null
)
returns table(
  total_pedidos bigint,
  pedidos_pendientes bigint,
  pedidos_parciales bigint,
  pedidos_completos bigint,
  total_aprobada numeric,
  total_atendida numeric,
  total_solicitada numeric,
  items_excepcion bigint
)
language sql
set search_path = ''
as $$
  select
    count(distinct p.pedido_id),
    count(distinct p.pedido_id) filter (
      where p.estado_atencion = 'PENDIENTE' and estado_pedido.nombre <> 'Rechazado'
    ),
    count(distinct p.pedido_id) filter (where p.estado_atencion = 'PARCIAL'),
    count(distinct p.pedido_id) filter (where p.estado_atencion = 'COMPLETO'),
    coalesce(sum(d.cantidad_aprobada) filter (where d.active), 0),
    coalesce(sum(d.cantidad_atendida) filter (where d.active), 0),
    coalesce(sum(d.cantidad_solicitada) filter (where d.active), 0),
    count(*) filter (where d.active and estado_item.nombre in ('Observado', 'Rechazado'))
  from public.pedido p
  join public.estados_catalogo estado_pedido on estado_pedido.estado_id = p.estado_actual_id
  left join public.detalle_pedido d on d.pedido_id = p.pedido_id
  left join public.estados_catalogo estado_item on estado_item.estado_id = d.estado_actual_id
  where p.active
    and (p_desde is null or p.fecha_emision >= p_desde)
    and (p_hasta is null or p.fecha_emision <= p_hasta)
    and (
      p_grupo_costo is null
      or (p_grupo_costo = '__appsc_sin_grupo_costo__' and p.grupo_costo is null)
      or p.grupo_costo = p_grupo_costo
    );
$$;

create or replace view public.vw_items_pendientes
with (security_invoker = true)
as
select
  d.detalle_id,
  d.pedido_id,
  p.nro_sc,
  p.grupo_costo,
  d.nro_parte,
  d.material,
  d.equipo,
  d.cantidad_solicitada,
  d.cantidad_aprobada,
  d.cantidad_atendida,
  d.cantidad_aprobada - d.cantidad_atendida as cantidad_pendiente,
  d.estado_atencion
from public.detalle_pedido d
join public.pedido p on p.pedido_id = d.pedido_id
join public.estados_catalogo estado_pedido on estado_pedido.estado_id = p.estado_actual_id
where p.active
  and d.active
  and estado_pedido.nombre <> 'Rechazado'
  and d.cantidad_aprobada > 0
  and d.cantidad_aprobada > d.cantidad_atendida
order by (d.cantidad_aprobada - d.cantidad_atendida) desc;

grant execute on function public.dashboard_kpis(date, date, text) to authenticated;
grant select on public.vw_items_pendientes to authenticated;
