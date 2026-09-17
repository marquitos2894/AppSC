-- Un único enlace público revocable para consultar todos los pedidos.
-- Las tablas base conservan RLS: el acceso anónimo queda limitado a estas RPC.

create table if not exists public.enlace_publico_lectura (
  enlace_id bigint generated always as identity primary key,
  token uuid not null unique default gen_random_uuid(),
  activo boolean not null default true,
  creado_en timestamptz not null default now(),
  revocado_en timestamptz null
);

alter table public.enlace_publico_lectura enable row level security;
revoke all on table public.enlace_publico_lectura from anon, authenticated;

create or replace function public.fn_validar_enlace_publico(p_token uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not exists (
    select 1
    from public.enlace_publico_lectura
    where token = p_token
      and activo
      and revocado_en is null
  ) then
    raise exception 'El enlace público no es válido o fue revocado';
  end if;
end;
$$;

create or replace function public.fn_generar_enlace_publico()
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_token uuid;
begin
  if auth.uid() is null or coalesce(auth.jwt() -> 'app_metadata' ->> 'role', '') = 'viewer' then
    raise exception 'No tienes permiso para generar enlaces públicos';
  end if;

  update public.enlace_publico_lectura
  set activo = false, revocado_en = now()
  where activo;

  insert into public.enlace_publico_lectura (activo)
  values (true)
  returning token into v_token;

  return v_token;
end;
$$;

create or replace function public.fn_revocar_enlace_publico()
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if auth.uid() is null or coalesce(auth.jwt() -> 'app_metadata' ->> 'role', '') = 'viewer' then
    raise exception 'No tienes permiso para revocar enlaces públicos';
  end if;

  update public.enlace_publico_lectura
  set activo = false, revocado_en = now()
  where activo;
end;
$$;

create or replace function public.fn_listar_pedidos_publicos(p_token uuid)
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
  perform public.fn_validar_enlace_publico(p_token);

  return query
  select
    p.pedido_id,
    p.fecha_emision,
    p.motivo,
    p.grupo_costo,
    p.nro_sc,
    p.estado_atencion,
    ec.nombre,
    count(d.detalle_id) filter (where dec.nombre = 'Observado'),
    count(d.detalle_id) filter (where dec.nombre = 'Rechazado'),
    count(d.detalle_id)
  from public.pedido p
  join public.estados_catalogo ec on ec.estado_id = p.estado_actual_id
  left join public.detalle_pedido d on d.pedido_id = p.pedido_id and d.active
  left join public.estados_catalogo dec on dec.estado_id = d.estado_actual_id
  where p.active
  group by p.pedido_id, p.fecha_emision, p.motivo, p.grupo_costo, p.nro_sc, p.estado_atencion, ec.nombre
  order by p.fecha_emision desc, p.pedido_id desc;
end;
$$;

create or replace function public.fn_ver_detalle_pedido_publico(p_token uuid, p_pedido_id bigint)
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
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform public.fn_validar_enlace_publico(p_token);

  return query
  select
    d.detalle_id,
    d.nro_parte,
    d.material,
    d.equipo,
    d.cantidad_solicitada,
    d.cantidad_aprobada,
    d.cantidad_atendida,
    d.fecha_aprox_atencion,
    d.estado_atencion,
    ec.nombre
  from public.detalle_pedido d
  join public.estados_catalogo ec on ec.estado_id = d.estado_actual_id
  join public.pedido p on p.pedido_id = d.pedido_id
  where d.pedido_id = p_pedido_id
    and d.active
    and p.active
  order by d.detalle_id;
end;
$$;

revoke all on function public.fn_validar_enlace_publico(uuid) from public;
grant execute on function public.fn_generar_enlace_publico() to authenticated;
grant execute on function public.fn_revocar_enlace_publico() to authenticated;
grant execute on function public.fn_listar_pedidos_publicos(uuid) to anon, authenticated;
grant execute on function public.fn_ver_detalle_pedido_publico(uuid, bigint) to anon, authenticated;
