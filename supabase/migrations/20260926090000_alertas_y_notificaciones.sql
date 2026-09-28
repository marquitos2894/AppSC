-- Centro de alertas AppSC. Las alertas operativas se actualizan diariamente;
-- las lecturas y suscripciones se aíslan por usuario.

create extension if not exists pg_cron;
create extension if not exists pg_net with schema extensions;
create extension if not exists supabase_vault with schema vault;

create table if not exists public.notificacion_evento (
  evento_id uuid primary key default gen_random_uuid(),
  tipo text not null,
  severidad text not null default 'info',
  pedido_id bigint references public.pedido(pedido_id) on delete cascade,
  detalle_id bigint references public.detalle_pedido(detalle_id) on delete cascade,
  operacion_id uuid,
  titulo text not null,
  mensaje text not null,
  metadata jsonb not null default '{}'::jsonb,
  fecha_operativa date,
  dias_retraso integer,
  resuelto_en timestamptz,
  push_milestone integer,
  push_sent_milestone integer not null default -1,
  push_status text not null default 'none'
    check (push_status in ('none', 'pending', 'processing', 'sent', 'failed')),
  push_claimed_at timestamptz,
  creado_en timestamptz not null default now()
);

create unique index if not exists notificacion_evento_operacion_uidx
  on public.notificacion_evento(operacion_id) where operacion_id is not null;
create unique index if not exists notificacion_evento_alerta_activa_uidx
  on public.notificacion_evento(detalle_id, tipo)
  where detalle_id is not null and resuelto_en is null
    and tipo in ('vence_hoy', 'retraso', 'sin_fecha', 'observado', 'rechazado');
create index if not exists notificacion_evento_recientes_idx
  on public.notificacion_evento(creado_en desc);
create index if not exists notificacion_evento_operativas_idx
  on public.notificacion_evento(pedido_id, resuelto_en, tipo)
  where detalle_id is not null;

create table if not exists public.notificacion_lectura (
  usuario_id uuid not null references auth.users(id) on delete cascade,
  evento_id uuid not null references public.notificacion_evento(evento_id) on delete cascade,
  leido_en timestamptz not null default now(),
  primary key (usuario_id, evento_id)
);

create table if not exists public.push_suscripcion (
  suscripcion_id bigint generated always as identity primary key,
  usuario_id uuid not null references auth.users(id) on delete cascade,
  endpoint text not null,
  p256dh text not null,
  auth text not null,
  active boolean not null default true,
  creado_en timestamptz not null default now(),
  actualizado_en timestamptz not null default now(),
  unique (usuario_id, endpoint)
);

create table if not exists public.push_entrega (
  entrega_id uuid primary key default gen_random_uuid(),
  evento_id uuid not null references public.notificacion_evento(evento_id) on delete cascade,
  suscripcion_id bigint not null references public.push_suscripcion(suscripcion_id) on delete cascade,
  endpoint text not null,
  hito integer not null default -1,
  estado text not null default 'pending'
    check (estado in ('pending', 'processing', 'retry', 'sent', 'expired', 'failed', 'cancelled')),
  intentos integer not null default 0,
  claim_token uuid,
  reclamado_en timestamptz,
  proximo_intento timestamptz not null default now(),
  enviado_en timestamptz,
  unique(evento_id, hito, endpoint)
);
create index if not exists push_entrega_pendientes_idx
  on public.push_entrega(proximo_intento) where estado in ('pending', 'retry', 'processing');
alter table public.push_entrega enable row level security;
revoke all on public.push_entrega from public, anon, authenticated;

alter table public.notificacion_evento enable row level security;
alter table public.notificacion_lectura enable row level security;
alter table public.push_suscripcion enable row level security;

drop policy if exists notificacion_evento_authenticated_read on public.notificacion_evento;
create policy notificacion_evento_authenticated_read on public.notificacion_evento
  for select to authenticated using (true);
drop policy if exists notificacion_lectura_own_read on public.notificacion_lectura;
create policy notificacion_lectura_own_read on public.notificacion_lectura
  for select to authenticated using (usuario_id = (select auth.uid()));
drop policy if exists push_suscripcion_own_read on public.push_suscripcion;
create policy push_suscripcion_own_read on public.push_suscripcion
  for select to authenticated using (usuario_id = (select auth.uid()));

revoke all on public.notificacion_evento, public.notificacion_lectura, public.push_suscripcion from anon, authenticated;
grant select on public.notificacion_evento, public.notificacion_lectura, public.push_suscripcion to authenticated;

create or replace function public.trg_notificacion_estado()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_estado text;
  v_nro_sc text;
  v_pedido_id bigint;
  v_material text;
  v_detalle_id bigint;
  v_operacion_id uuid;
  v_cantidad integer;
begin
  select ec.nombre into v_estado
  from public.estados_catalogo ec where ec.estado_id = new.estado_id;

  if v_estado is null then return new; end if;
  if tg_table_name = 'solicitud_historial_estados' then
    if v_estado = 'Registrado' and not exists (
      select 1 from public.solicitud_historial_estados h
      where h.pedido_id = new.pedido_id and h.historial_id <> new.historial_id
    ) then return new; end if;
    select p.pedido_id, p.nro_sc into v_pedido_id, v_nro_sc
    from public.pedido p where p.pedido_id = new.pedido_id;
    v_operacion_id := md5(txid_current()::text || ':' || v_pedido_id::text)::uuid;
    insert into public.notificacion_evento as actual (
      tipo, severidad, pedido_id, operacion_id, titulo, mensaje, metadata, push_status
    ) values (
      'cambio_estado', 'info', v_pedido_id, v_operacion_id,
      'Cambió el estado del pedido',
      format('SC%s pasó a %s', coalesce(v_nro_sc, v_pedido_id::text), v_estado),
      jsonb_build_object('estado', v_estado, 'nro_sc', v_nro_sc, 'items', '[]'::jsonb), 'pending'
    ) on conflict (operacion_id) where operacion_id is not null do update
      set titulo = case
            when jsonb_array_length(coalesce(actual.metadata->'items', '[]'::jsonb)) > 0
              then actual.titulo
            else 'Cambió el estado del pedido' end,
          mensaje = case
            when jsonb_array_length(coalesce(actual.metadata->'items', '[]'::jsonb)) > 0
              then actual.mensaje
            else excluded.mensaje end,
          metadata = actual.metadata ||
            jsonb_build_object('estado', excluded.metadata->>'estado', 'nro_sc', excluded.metadata->>'nro_sc');
    return new;
  end if;

  if v_estado = 'Registrado' and not exists (
    select 1 from public.detalle_historial_estados h
    where h.detalle_id = new.detalle_id and h.historial_id <> new.historial_id
  ) then return new; end if;

  select d.pedido_id, d.detalle_id, d.material
    into v_pedido_id, v_detalle_id, v_material
  from public.detalle_pedido d where d.detalle_id = new.detalle_id;
  select p.nro_sc into v_nro_sc from public.pedido p where p.pedido_id = v_pedido_id;
  if v_pedido_id is null then return new; end if;
  v_operacion_id := md5(txid_current()::text || ':' || v_pedido_id::text)::uuid;

  select count(*) into v_cantidad
  from public.detalle_historial_estados h
  where h.xmin::text::bigint = (txid_current() % 4294967296)
    and h.detalle_id in (
      select d.detalle_id from public.detalle_pedido d where d.pedido_id = v_pedido_id
    );

  insert into public.notificacion_evento as actual (
    tipo, severidad, pedido_id, detalle_id, operacion_id, titulo, mensaje, metadata, push_status
  ) values (
    'cambio_estado', 'info', v_pedido_id, v_detalle_id, v_operacion_id,
    case when v_cantidad > 1 then 'Cambió el estado de varios ítems' else 'Cambió el estado de un ítem' end,
    case when v_cantidad > 1
      then format('SC%s: %s ítems pasaron a %s', coalesce(v_nro_sc, v_pedido_id::text), v_cantidad, v_estado)
      else format('SC%s: %s pasó a %s', coalesce(v_nro_sc, v_pedido_id::text), coalesce(v_material, 'Ítem'), v_estado)
    end,
    jsonb_build_object(
      'estado', v_estado,
      'nro_sc', v_nro_sc,
      'items', coalesce((
        select jsonb_agg(jsonb_build_object('detalle_id', d.detalle_id, 'material', d.material))
        from public.detalle_historial_estados h
        join public.detalle_pedido d on d.detalle_id = h.detalle_id
        where h.xmin::text::bigint = (txid_current() % 4294967296) and d.pedido_id = v_pedido_id
      ), '[]'::jsonb)
    ), 'pending'
  ) on conflict (operacion_id) where operacion_id is not null do update
    set titulo = excluded.titulo,
        mensaje = excluded.mensaje,
        detalle_id = case when v_cantidad = 1 then excluded.detalle_id else null end,
        metadata = actual.metadata || excluded.metadata,
        push_status = case when actual.push_status = 'sent'
          then 'sent' else 'pending' end;
  return new;
end;
$$;

drop trigger if exists trg_notificacion_solicitud_historial on public.solicitud_historial_estados;
create trigger trg_notificacion_solicitud_historial
after insert on public.solicitud_historial_estados
for each row when (new.active)
execute function public.trg_notificacion_estado();
drop trigger if exists trg_notificacion_detalle_historial on public.detalle_historial_estados;
create trigger trg_notificacion_detalle_historial
after insert on public.detalle_historial_estados
for each row when (new.active)
execute function public.trg_notificacion_estado();

create or replace function public.fn_listar_notificaciones(
  p_solo_no_leidas boolean default true,
  p_limite integer default 100
)
returns table(
  evento_id uuid, tipo text, severidad text, pedido_id bigint, detalle_id bigint,
  titulo text, mensaje text, metadata jsonb, creado_en timestamptz,
  fecha_operativa date, dias_retraso integer, resuelto_en timestamptz, leido boolean,
  etiqueta_tipo text, nro_sc text, material text, estado_actual text
)
language sql stable security definer set search_path = ''
as $$
  select e.evento_id, e.tipo, e.severidad, e.pedido_id, e.detalle_id,
    e.titulo, e.mensaje, e.metadata, e.creado_en, e.fecha_operativa,
    e.dias_retraso, e.resuelto_en, l.evento_id is not null,
    case e.tipo
      when 'cambio_estado' then 'Cambio de estado'
      when 'vence_hoy' then 'Vence hoy'
      when 'retraso' then 'Retraso'
      when 'sin_fecha' then 'Sin fecha'
      when 'observado' then 'Observado'
      when 'rechazado' then 'Rechazado'
      else e.tipo end,
    coalesce(e.metadata->>'nro_sc', p.nro_sc::text),
    coalesce(e.metadata->>'material', (select d.material from public.detalle_pedido d where d.detalle_id = e.detalle_id)),
    coalesce(e.metadata->>'estado', e.metadata->>'estado_nuevo')
  from public.notificacion_evento e
  left join public.pedido p on p.pedido_id = e.pedido_id
  left join public.notificacion_lectura l
    on l.evento_id = e.evento_id and l.usuario_id = (select auth.uid())
  where (select auth.uid()) is not null
    and (not p_solo_no_leidas or l.evento_id is null)
  order by e.creado_en desc
  limit least(greatest(coalesce(p_limite, 100), 1), 200);
$$;

create or replace function public.fn_contar_notificaciones_no_leidas()
returns bigint language sql stable security definer set search_path = ''
as $$
  select count(*) from public.notificacion_evento e
  where (select auth.uid()) is not null
    and not exists (
      select 1 from public.notificacion_lectura l
      where l.evento_id = e.evento_id and l.usuario_id = (select auth.uid())
    );
$$;

create or replace function public.fn_marcar_notificacion_leida(p_evento_id uuid)
returns void language plpgsql security definer set search_path = ''
as $$
begin
  if auth.uid() is null then raise exception 'Se requiere iniciar sesión'; end if;
  insert into public.notificacion_lectura(usuario_id, evento_id)
  select auth.uid(), e.evento_id from public.notificacion_evento e
  where e.evento_id = p_evento_id
  on conflict (usuario_id, evento_id) do nothing;
end;
$$;

create or replace function public.fn_marcar_todas_notificaciones_leidas()
returns void language plpgsql security definer set search_path = ''
as $$
begin
  if auth.uid() is null then raise exception 'Se requiere iniciar sesión'; end if;
  insert into public.notificacion_lectura(usuario_id, evento_id)
  select auth.uid(), e.evento_id from public.notificacion_evento e
  on conflict (usuario_id, evento_id) do nothing;
end;
$$;

create or replace function public.fn_registrar_suscripcion_push(p_suscripcion jsonb)
returns void language plpgsql security definer set search_path = ''
as $$
declare v_usuario uuid := auth.uid();
begin
  if v_usuario is null then raise exception 'Se requiere iniciar sesión'; end if;
  if nullif(p_suscripcion->>'endpoint', '') is null
    or nullif(p_suscripcion#>>'{keys,p256dh}', '') is null
    or nullif(p_suscripcion#>>'{keys,auth}', '') is null then
    raise exception 'La suscripción push está incompleta';
  end if;
  insert into public.push_suscripcion(usuario_id, endpoint, p256dh, auth, active, actualizado_en)
  values (v_usuario, p_suscripcion->>'endpoint', p_suscripcion#>>'{keys,p256dh}',
    p_suscripcion#>>'{keys,auth}', true, now())
  on conflict (usuario_id, endpoint) do update
    set p256dh = excluded.p256dh, auth = excluded.auth,
        active = true, actualizado_en = now();
end;
$$;

create or replace function public.fn_eliminar_suscripcion_push(p_endpoint text)
returns void language plpgsql security definer set search_path = ''
as $$
begin
  if auth.uid() is null then raise exception 'Se requiere iniciar sesión'; end if;
  update public.push_suscripcion set active = false, actualizado_en = now()
  where usuario_id = auth.uid() and endpoint = p_endpoint;
end;
$$;

create or replace function public.fn_alerta_evento_vigente(p_evento_id uuid)
returns boolean language sql stable security definer set search_path = ''
as $$
  select coalesce((
    select case when e.tipo = 'cambio_estado' then true
      else e.resuelto_en is null and d.active and p.active and (
        (e.tipo = 'observado' and ec.nombre = 'Observado')
        or (e.tipo = 'rechazado' and ec.nombre = 'Rechazado')
        or (ec.nombre not in ('Atendido', 'Observado', 'Rechazado')
          and d.cantidad_aprobada > d.cantidad_atendida
          and (
            (e.tipo = 'vence_hoy' and d.fecha_aprox_atencion = (now() at time zone 'America/Lima')::date
              and e.fecha_operativa = d.fecha_aprox_atencion)
            or (e.tipo = 'retraso' and d.fecha_aprox_atencion < (now() at time zone 'America/Lima')::date
              and e.fecha_operativa = d.fecha_aprox_atencion)
            or (e.tipo = 'sin_fecha' and d.fecha_aprox_atencion is null and exists (
              select 1 from public.detalle_historial_estados h
              join public.estados_catalogo aprob on aprob.estado_id = h.estado_id
              where h.detalle_id = d.detalle_id and h.active and aprob.nombre = 'Aprobado'
            ))
          )
        )
      ) end
    from public.notificacion_evento e
    left join public.detalle_pedido d on d.detalle_id = e.detalle_id
    left join public.pedido p on p.pedido_id = e.pedido_id
    left join public.estados_catalogo ec on ec.estado_id = d.estado_actual_id
    where e.evento_id = p_evento_id
  ), false);
$$;

create or replace function public.trg_resolver_alertas_operativas()
returns trigger language plpgsql security definer set search_path = ''
as $$
begin
  if tg_table_name = 'detalle_pedido' then
    update public.notificacion_evento e
    set resuelto_en = now(), push_status = 'none'
    where e.detalle_id = new.detalle_id and e.resuelto_en is null
      and e.tipo <> 'cambio_estado' and not public.fn_alerta_evento_vigente(e.evento_id);
  else
    update public.notificacion_evento e
    set resuelto_en = now(), push_status = 'none'
    where e.pedido_id = new.pedido_id and e.resuelto_en is null
      and e.tipo <> 'cambio_estado' and not public.fn_alerta_evento_vigente(e.evento_id);
  end if;
  return new;
end;
$$;
drop trigger if exists trg_resolver_alertas_detalle on public.detalle_pedido;
create trigger trg_resolver_alertas_detalle
after update of estado_actual_id, fecha_aprox_atencion, cantidad_aprobada, cantidad_atendida, active
on public.detalle_pedido for each row execute function public.trg_resolver_alertas_operativas();
drop trigger if exists trg_resolver_alertas_pedido on public.pedido;
create trigger trg_resolver_alertas_pedido after update of active on public.pedido
for each row execute function public.trg_resolver_alertas_operativas();

create or replace function public.fn_reclamar_push_notificaciones(p_limite integer default 50)
returns table(entrega_id uuid, claim_token uuid, evento_id uuid, titulo text, mensaje text,
  pedido_id bigint, push_milestone integer, endpoint text, p256dh text, auth_key text)
language plpgsql security definer set search_path = ''
as $$
begin
  -- Snapshot de destinatarios por hito. Un mismo endpoint recibe una entrega,
  -- aunque haya sido registrado por más de un usuario del mismo navegador.
  with eventos as (
    select e.evento_id, coalesce(e.push_milestone, -1) as hito
    from public.notificacion_evento e
    where e.push_status = 'pending' and public.fn_alerta_evento_vigente(e.evento_id)
    order by e.creado_en limit 100 for update skip locked
  ), suscripciones as (
    select distinct on (s.endpoint) s.suscripcion_id, s.endpoint
    from public.push_suscripcion s where s.active
    order by s.endpoint, s.suscripcion_id
  )
  insert into public.push_entrega(evento_id, suscripcion_id, endpoint, hito)
  select ev.evento_id, s.suscripcion_id, s.endpoint, ev.hito
  from eventos ev cross join suscripciones s
  on conflict (evento_id, hito, endpoint) do nothing;

  update public.notificacion_evento e set push_status = 'processing'
  where e.push_status = 'pending' and exists (
    select 1 from public.push_entrega pe
    where pe.evento_id = e.evento_id and pe.hito = coalesce(e.push_milestone, -1)
  );

  update public.push_entrega pe set estado = 'cancelled', claim_token = null
  where pe.estado in ('pending', 'processing', 'retry')
    and not public.fn_alerta_evento_vigente(pe.evento_id);

  return query
  with seleccion as (
    select pe.entrega_id from public.push_entrega pe
    join public.notificacion_evento e on e.evento_id = pe.evento_id
    join public.push_suscripcion s on s.suscripcion_id = pe.suscripcion_id and s.active
    where ((pe.estado in ('pending', 'retry') and pe.proximo_intento <= now())
      or (pe.estado = 'processing' and pe.reclamado_en < now() - interval '5 minutes'))
      and pe.hito = coalesce(e.push_milestone, -1)
      and public.fn_alerta_evento_vigente(e.evento_id)
    order by pe.proximo_intento
    limit least(greatest(coalesce(p_limite, 50), 1), 50)
    for update of pe skip locked
  ), reclamados as (
    update public.push_entrega pe
    set estado = 'processing', reclamado_en = now(), claim_token = gen_random_uuid(), intentos = pe.intentos + 1
    from seleccion sel where pe.entrega_id = sel.entrega_id
    returning pe.entrega_id, pe.claim_token, pe.evento_id, pe.suscripcion_id, pe.hito
  ) select r.entrega_id, r.claim_token, r.evento_id, e.titulo, e.mensaje, e.pedido_id,
      nullif(r.hito, -1), s.endpoint, s.p256dh, s.auth
    from reclamados r
    join public.notificacion_evento e on e.evento_id = r.evento_id
    join public.push_suscripcion s on s.suscripcion_id = r.suscripcion_id;
end;
$$;

create or replace function public.fn_confirmar_entrega_push(
  p_entrega_id uuid, p_claim_token uuid, p_resultado text
)
returns boolean language plpgsql security definer set search_path = ''
as $$
declare v_entrega public.push_entrega%rowtype;
begin
  if p_resultado not in ('sent', 'expired', 'retry', 'failed') then
    raise exception 'Resultado de entrega no válido';
  end if;
  select pe.* into v_entrega from public.push_entrega pe
  where pe.entrega_id = p_entrega_id and pe.claim_token = p_claim_token and pe.estado = 'processing'
  for update;
  if not found then return false; end if;
  update public.push_entrega
  set estado = case when p_resultado = 'retry' and v_entrega.intentos >= 5 then 'failed' else p_resultado end,
      claim_token = null,
      proximo_intento = now() + interval '1 minute' * least(60, power(2, least(v_entrega.intentos, 6))::integer),
      enviado_en = case when p_resultado = 'sent' then now() else null end
  where entrega_id = p_entrega_id;
  if p_resultado = 'expired' then
    update public.push_suscripcion set active = false, actualizado_en = now()
    where endpoint = v_entrega.endpoint;
    update public.push_entrega set estado = 'expired', claim_token = null
    where endpoint = v_entrega.endpoint and estado in ('pending', 'retry');
  end if;
  update public.notificacion_evento e
  set push_status = case
      when exists (select 1 from public.push_entrega pe where pe.evento_id = e.evento_id
        and pe.hito = v_entrega.hito and pe.estado in ('pending', 'retry', 'processing')) then 'processing'
      when exists (select 1 from public.push_entrega pe where pe.evento_id = e.evento_id
        and pe.hito = v_entrega.hito and pe.estado = 'failed') then 'failed'
      else 'sent' end,
    push_sent_milestone = case when v_entrega.hito >= 0 and not exists (
      select 1 from public.push_entrega pe where pe.evento_id = e.evento_id
      and pe.hito = v_entrega.hito and pe.estado in ('pending', 'retry', 'processing', 'failed')
    ) then greatest(e.push_sent_milestone, v_entrega.hito) else e.push_sent_milestone end
  where e.evento_id = v_entrega.evento_id and coalesce(e.push_milestone, -1) = v_entrega.hito
    and public.fn_alerta_evento_vigente(e.evento_id);
  return true;
end;
$$;

create or replace function public.fn_revisar_alertas_operativas()
returns integer language plpgsql security definer set search_path = ''
as $$
declare
  v_hoy date := (now() at time zone 'America/Lima')::date;
  v_creados integer := 0;
begin
  create temporary table if not exists appsc_alertas_candidatas (
    tipo text, severidad text, pedido_id bigint, detalle_id bigint,
    titulo text, mensaje text, fecha_operativa date, dias_retraso integer,
    push_milestone integer
  ) on commit drop;
  truncate appsc_alertas_candidatas;

  insert into appsc_alertas_candidatas
  select tipo, severidad, pedido_id, detalle_id, titulo, mensaje, fecha_operativa, dias_retraso, push_milestone
  from (
    select
      case
        when ec.nombre = 'Observado' then 'observado'
        when ec.nombre = 'Rechazado' then 'rechazado'
        when d.fecha_aprox_atencion = v_hoy then 'vence_hoy'
        when d.fecha_aprox_atencion < v_hoy then 'retraso'
        else 'sin_fecha'
      end as tipo,
      case when ec.nombre in ('Observado', 'Rechazado') or d.fecha_aprox_atencion < v_hoy then 'danger'
        when d.fecha_aprox_atencion = v_hoy then 'warn' else 'warn' end as severidad,
      p.pedido_id, d.detalle_id,
      case
        when ec.nombre = 'Observado' then 'Ítem observado'
        when ec.nombre = 'Rechazado' then 'Ítem rechazado'
        when d.fecha_aprox_atencion = v_hoy then 'Ítem vence hoy'
        when d.fecha_aprox_atencion < v_hoy then 'Ítem retrasado'
        else 'Ítem aprobado sin fecha'
      end as titulo,
      format('SC%s · %s · estado: %s', coalesce(p.nro_sc, p.pedido_id::text),
        coalesce(d.material, d.nro_parte, 'Ítem'), ec.nombre) as mensaje,
      d.fecha_aprox_atencion as fecha_operativa,
      case when d.fecha_aprox_atencion < v_hoy then (
        select count(*)::integer from generate_series(d.fecha_aprox_atencion + 1, v_hoy, interval '1 day') as calendario(dia)
        where extract(isodow from calendario.dia) <> 7
      ) else 0 end as dias_retraso,
      case
        when d.fecha_aprox_atencion = v_hoy then 0
        when d.fecha_aprox_atencion < v_hoy then
          case
            when (select count(*)::integer from generate_series(d.fecha_aprox_atencion + 1, v_hoy, interval '1 day') as calendario(dia) where extract(isodow from calendario.dia) <> 7) < 3 then null
            when (select count(*)::integer from generate_series(d.fecha_aprox_atencion + 1, v_hoy, interval '1 day') as calendario(dia) where extract(isodow from calendario.dia) <> 7) < 7 then 3
            when (select count(*)::integer from generate_series(d.fecha_aprox_atencion + 1, v_hoy, interval '1 day') as calendario(dia) where extract(isodow from calendario.dia) <> 7) < 15 then 7
            when (select count(*)::integer from generate_series(d.fecha_aprox_atencion + 1, v_hoy, interval '1 day') as calendario(dia) where extract(isodow from calendario.dia) <> 7) < 30 then 15
            else 30 + (((select count(*)::integer from generate_series(d.fecha_aprox_atencion + 1, v_hoy, interval '1 day') as calendario(dia) where extract(isodow from calendario.dia) <> 7) - 30) / 30) * 30
          end
        else null
      end as push_milestone
    from public.detalle_pedido d
    join public.pedido p on p.pedido_id = d.pedido_id and p.active
    join public.estados_catalogo ec on ec.estado_id = d.estado_actual_id
    where d.active
      and (
        ec.nombre in ('Observado', 'Rechazado')
        or (
          ec.nombre <> 'Atendido'
          and greatest(coalesce(d.cantidad_aprobada, 0) - coalesce(d.cantidad_atendida, 0), 0) > 0
          and (
            d.fecha_aprox_atencion <= v_hoy
            or (d.fecha_aprox_atencion is null and exists (
              select 1 from public.detalle_historial_estados h
              join public.estados_catalogo aprob on aprob.estado_id = h.estado_id
              where h.detalle_id = d.detalle_id and h.active and aprob.nombre = 'Aprobado'
            ))
          )
        )
      )
  ) candidatos;

  update public.notificacion_evento e
  set resuelto_en = now(), push_status = 'none'
  where e.tipo in ('vence_hoy', 'retraso', 'sin_fecha', 'observado', 'rechazado')
    and e.resuelto_en is null
    and not exists (
      select 1 from appsc_alertas_candidatas c
      where c.detalle_id = e.detalle_id and c.tipo = e.tipo
    );

  insert into public.notificacion_evento as actual (
    tipo, severidad, pedido_id, detalle_id, titulo, mensaje,
    fecha_operativa, dias_retraso, push_milestone, push_status, metadata
  )
  select c.tipo, c.severidad, c.pedido_id, c.detalle_id, c.titulo, c.mensaje,
    c.fecha_operativa, c.dias_retraso, c.push_milestone,
    case when c.push_milestone is not null then 'pending' else 'none' end,
    jsonb_build_object('nro_sc', p.nro_sc, 'material', d.material, 'nro_parte', d.nro_parte, 'estado', ec.nombre)
  from appsc_alertas_candidatas c
  join public.detalle_pedido d on d.detalle_id = c.detalle_id
  join public.pedido p on p.pedido_id = c.pedido_id
  join public.estados_catalogo ec on ec.estado_id = d.estado_actual_id
  on conflict (detalle_id, tipo) where detalle_id is not null and resuelto_en is null
    and tipo in ('vence_hoy', 'retraso', 'sin_fecha', 'observado', 'rechazado')
  do update set
    severidad = excluded.severidad,
    titulo = excluded.titulo,
    mensaje = excluded.mensaje,
    fecha_operativa = excluded.fecha_operativa,
    dias_retraso = excluded.dias_retraso,
    metadata = excluded.metadata,
    push_status = case
      when excluded.push_milestone is not null
        and excluded.push_milestone > actual.push_sent_milestone
        and excluded.push_milestone > coalesce(actual.push_milestone, -1)
        then 'pending'
      else actual.push_status
    end,
    push_milestone = coalesce(excluded.push_milestone, actual.push_milestone),
    push_claimed_at = case when excluded.push_milestone is not null
      and excluded.push_milestone > actual.push_sent_milestone
      and excluded.push_milestone > coalesce(actual.push_milestone, -1)
      then null else actual.push_claimed_at end;

  get diagnostics v_creados = row_count;
  delete from public.notificacion_evento
  where tipo = 'cambio_estado' and creado_en < now() - interval '90 days';
  return v_creados;
end;
$$;

create or replace function public.fn_alertas_publicas_vigentes(
  p_busqueda_sc text default null,
  p_busqueda_item text default null,
  p_estado text default null,
  p_grupo_costo text default null
)
returns table(
  tipo text, pedido_id bigint, detalle_id bigint, nro_sc text, grupo_costo text,
  material text, nro_parte text, estado_actual text, fecha_aprox_atencion date,
  dias_retraso integer
)
language sql stable security definer set search_path = ''
as $$
  select case
      when ec.nombre = 'Observado' then 'observado'
      when ec.nombre = 'Rechazado' then 'rechazado'
      when d.fecha_aprox_atencion = (now() at time zone 'America/Lima')::date then 'vence_hoy'
      when d.fecha_aprox_atencion < (now() at time zone 'America/Lima')::date then 'retraso'
      else 'sin_fecha' end,
    p.pedido_id, d.detalle_id, p.nro_sc::text, p.grupo_costo::text,
    d.material::text, d.nro_parte::text, ec.nombre::text,
    d.fecha_aprox_atencion,
    case when d.fecha_aprox_atencion < (now() at time zone 'America/Lima')::date then (
      select count(*)::integer from generate_series(d.fecha_aprox_atencion + 1,
        (now() at time zone 'America/Lima')::date, interval '1 day') as calendario(dia)
      where extract(isodow from calendario.dia) <> 7
    ) else 0 end
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
            select 1 from public.detalle_historial_estados h
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
  order by case
    when ec.nombre = 'Observado' then 4
    when ec.nombre = 'Rechazado' then 5
    when d.fecha_aprox_atencion < (now() at time zone 'America/Lima')::date then 1
    when d.fecha_aprox_atencion = (now() at time zone 'America/Lima')::date then 2
    else 3 end,
    p.fecha_emision desc, d.detalle_id;
$$;

revoke all on function public.fn_listar_notificaciones(boolean, integer) from public;
revoke all on function public.fn_contar_notificaciones_no_leidas() from public;
revoke all on function public.fn_marcar_notificacion_leida(uuid) from public;
revoke all on function public.fn_marcar_todas_notificaciones_leidas() from public;
revoke all on function public.fn_registrar_suscripcion_push(jsonb) from public;
revoke all on function public.fn_eliminar_suscripcion_push(text) from public;
revoke all on function public.fn_reclamar_push_notificaciones(integer) from public;
revoke all on function public.fn_confirmar_entrega_push(uuid, uuid, text) from public;
revoke all on function public.fn_alerta_evento_vigente(uuid) from public;
revoke all on function public.fn_revisar_alertas_operativas() from public;
revoke all on function public.fn_alertas_publicas_vigentes(text, text, text, text) from public;

grant execute on function public.fn_listar_notificaciones(boolean, integer) to authenticated;
grant execute on function public.fn_contar_notificaciones_no_leidas() to authenticated;
grant execute on function public.fn_marcar_notificacion_leida(uuid) to authenticated;
grant execute on function public.fn_marcar_todas_notificaciones_leidas() to authenticated;
grant execute on function public.fn_registrar_suscripcion_push(jsonb) to authenticated;
grant execute on function public.fn_eliminar_suscripcion_push(text) to authenticated;
grant execute on function public.fn_reclamar_push_notificaciones(integer) to service_role;
grant execute on function public.fn_confirmar_entrega_push(uuid, uuid, text) to service_role;
grant execute on function public.fn_revisar_alertas_operativas() to service_role;
grant execute on function public.fn_alertas_publicas_vigentes(text, text, text, text) to anon, authenticated;

do $$
begin
  if not exists (select 1 from cron.job where jobname = 'appsc-revisar-alertas-0900-lima') then
    perform cron.schedule(
      'appsc-revisar-alertas-0900-lima',
      '0 14 * * *',
      $job$select public.fn_revisar_alertas_operativas();$job$
    );
  end if;
  if not exists (select 1 from cron.job where jobname = 'appsc-despachar-push') then
    perform cron.schedule(
      'appsc-despachar-push',
      '* * * * *',
      $job$
        select net.http_post(
          url := 'https://qhsizmayuhnlvcjcomlx.supabase.co/functions/v1/despachar-notificaciones',
          headers := jsonb_build_object(
            'Content-Type', 'application/json',
            'apikey', (select decrypted_secret from vault.decrypted_secrets where name = 'appsc_notifications_api_key' limit 1)
          ),
          body := '{}'::jsonb
        )
        where exists (select 1 from vault.decrypted_secrets where name = 'appsc_notifications_api_key')
      $job$
    );
  end if;
end;
$$;

do $$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'notificacion_evento'
  ) then
    alter publication supabase_realtime add table public.notificacion_evento;
  end if;
end;
$$;

notify pgrst, 'reload schema';

select public.fn_revisar_alertas_operativas();
