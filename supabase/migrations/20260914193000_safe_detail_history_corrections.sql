-- Correcciones trazables para el historial de estados de los ítems.
-- Un movimiento no se elimina: se desactiva y se conserva el motivo.

alter table public.detalle_historial_estados
  add column if not exists anulado_en timestamptz,
  add column if not exists anulado_por uuid,
  add column if not exists motivo_anulacion text,
  add column if not exists historial_origen_id bigint,
  add column if not exists comentario_editado_en timestamptz,
  add column if not exists comentario_editado_por uuid;

do $$
begin
  if not exists (
    select 1 from pg_constraint where conname = 'detalle_historial_origen_fk'
  ) then
    alter table public.detalle_historial_estados
      add constraint detalle_historial_origen_fk
      foreign key (historial_origen_id)
      references public.detalle_historial_estados(historial_id);
  end if;
end $$;

create table if not exists public.detalle_historial_auditoria (
  auditoria_id bigserial primary key,
  historial_id bigint not null references public.detalle_historial_estados(historial_id),
  accion varchar(40) not null check (accion in ('COMENTARIO_EDITADO', 'MOVIMIENTO_ANULADO', 'CORRECCION_REGISTRADA')),
  comentario_anterior text,
  comentario_nuevo text,
  motivo text,
  usuario_id uuid,
  timestamp timestamptz not null default now()
);

alter table public.detalle_historial_auditoria enable row level security;
drop policy if exists authenticated_select on public.detalle_historial_auditoria;
create policy authenticated_select on public.detalle_historial_auditoria
  for select to authenticated using (true);
grant select on public.detalle_historial_auditoria to authenticated;

create or replace function public.fn_editar_comentario_movimiento_detalle(
  p_historial_id bigint,
  p_comentario text default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_anterior text;
begin
  if auth.uid() is null or coalesce(auth.jwt() -> 'app_metadata' ->> 'role', '') = 'viewer' then
    raise exception 'No tienes permiso para editar movimientos';
  end if;

  select comentario into v_anterior
  from detalle_historial_estados
  where historial_id = p_historial_id and active
  for update;

  if not found then
    raise exception 'El movimiento no existe o ya fue anulado';
  end if;

  update detalle_historial_estados
  set comentario = nullif(btrim(p_comentario), ''),
      comentario_editado_en = now(),
      comentario_editado_por = auth.uid()
  where historial_id = p_historial_id;

  insert into detalle_historial_auditoria (
    historial_id, accion, comentario_anterior, comentario_nuevo, usuario_id
  ) values (
    p_historial_id, 'COMENTARIO_EDITADO', v_anterior, nullif(btrim(p_comentario), ''), auth.uid()
  );
end;
$$;

create or replace function public.fn_corregir_ultimo_movimiento_detalle(
  p_detalle_id bigint,
  p_historial_id bigint,
  p_estado_id int,
  p_motivo text
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_estado_actual int;
  v_estado_anterior int;
  v_ultimo_historial_id bigint;
  v_nombre_estado_anterior text;
  v_nuevo_historial_id bigint;
  v_comentario text;
begin
  if auth.uid() is null or coalesce(auth.jwt() -> 'app_metadata' ->> 'role', '') = 'viewer' then
    raise exception 'No tienes permiso para corregir movimientos';
  end if;

  if nullif(btrim(p_motivo), '') is null then
    raise exception 'Debes indicar el motivo de la corrección';
  end if;

  select h.estado_id, d.estado_actual_id, ec.nombre
    into v_estado_anterior, v_estado_actual, v_nombre_estado_anterior
  from detalle_historial_estados h
  join detalle_pedido d on d.detalle_id = h.detalle_id
  join estados_catalogo ec on ec.estado_id = h.estado_id
  where h.historial_id = p_historial_id
    and h.detalle_id = p_detalle_id
    and h.active
    and d.active
  for update of h, d;

  if not found then
    raise exception 'El movimiento no existe o ya fue anulado';
  end if;

  select historial_id into v_ultimo_historial_id
  from detalle_historial_estados
  where detalle_id = p_detalle_id and active
  order by historial_id desc
  limit 1;

  if v_ultimo_historial_id is distinct from p_historial_id
     or v_estado_actual is distinct from v_estado_anterior then
    raise exception 'Solo se puede corregir el último movimiento que coincide con el estado actual del ítem';
  end if;

  if v_nombre_estado_anterior = 'Atendido' then
    raise exception 'El estado Atendido se calcula por entregas y no puede corregirse manualmente';
  end if;

  if p_estado_id = v_estado_anterior then
    raise exception 'El estado seleccionado es el mismo. Usa la edición de comentario si solo deseas aclarar el movimiento';
  end if;

  if not exists (
    select 1 from estados_catalogo
    where estado_id = p_estado_id and active and ambito = 'detalle'
  ) then
    raise exception 'El estado seleccionado no es válido para un ítem';
  end if;

  update detalle_historial_estados
  set active = false,
      anulado_en = now(),
      anulado_por = auth.uid(),
      motivo_anulacion = btrim(p_motivo)
  where historial_id = p_historial_id;

  insert into detalle_historial_auditoria (historial_id, accion, motivo, usuario_id)
  values (p_historial_id, 'MOVIMIENTO_ANULADO', btrim(p_motivo), auth.uid());

  -- El trigger del detalle valida el nuevo estado y genera el movimiento de reemplazo.
  update detalle_pedido
  set estado_actual_id = p_estado_id
  where detalle_id = p_detalle_id;

  select historial_id into v_nuevo_historial_id
  from detalle_historial_estados
  where detalle_id = p_detalle_id and active
  order by historial_id desc
  limit 1;

  if v_nuevo_historial_id is null or v_nuevo_historial_id = p_historial_id then
    raise exception 'No se pudo registrar el movimiento de reemplazo';
  end if;

  v_comentario := format('Corrección del movimiento #%s: %s', p_historial_id, btrim(p_motivo));
  update detalle_historial_estados
  set comentario = v_comentario,
      historial_origen_id = p_historial_id
  where historial_id = v_nuevo_historial_id;

  insert into detalle_historial_auditoria (
    historial_id, accion, comentario_nuevo, motivo, usuario_id
  ) values (
    v_nuevo_historial_id, 'CORRECCION_REGISTRADA', v_comentario, btrim(p_motivo), auth.uid()
  );
end;
$$;

revoke all on function public.fn_editar_comentario_movimiento_detalle(bigint, text) from public;
revoke all on function public.fn_corregir_ultimo_movimiento_detalle(bigint, bigint, int, text) from public;
grant execute on function public.fn_editar_comentario_movimiento_detalle(bigint, text) to authenticated;
grant execute on function public.fn_corregir_ultimo_movimiento_detalle(bigint, bigint, int, text) to authenticated;
