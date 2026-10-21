-- Prueba de contrato para las dos RPC públicas de Unidad Corona Mantenimiento.
-- Ejecutar con un rol con lectura de catálogo y de las tablas subyacentes.
do $$
declare
  v_pedidos_fn regprocedure := 'public.fn_api_publica_pedidos_ucm()'::regprocedure;
  v_detalle_fn regprocedure := 'public.fn_api_publica_detalle_ucm()'::regprocedure;
  v_actual bigint;
  v_esperado bigint;
begin
  if not has_function_privilege('anon', v_pedidos_fn, 'EXECUTE')
    or not has_function_privilege('anon', v_detalle_fn, 'EXECUTE') then
    raise exception 'Las funciones públicas deben poder ejecutarse con el rol anon';
  end if;

  if exists (
    select 1
    from pg_catalog.pg_proc p
    cross join lateral pg_catalog.aclexplode(coalesce(
      p.proacl,
      pg_catalog.acldefault('f', p.proowner)
    )) permiso
    where p.oid in (v_pedidos_fn, v_detalle_fn)
      and permiso.grantee = 0
      and permiso.privilege_type = 'EXECUTE'
  ) then
    raise exception 'Las funciones no deben conservar EXECUTE para PUBLIC';
  end if;

  select count(*) into v_actual from public.fn_api_publica_pedidos_ucm();
  select count(*) into v_esperado
  from public.pedido p
  where p.active and p.grupo_costo = 'Unidad Corona Mantenimiento';
  if v_actual <> v_esperado then
    raise exception 'Encabezados incompletos o duplicados: recibidos %, esperados %', v_actual, v_esperado;
  end if;

  if exists (
    select 1
    from public.fn_api_publica_pedidos_ucm() pedido
    where pedido.grupo_costo is distinct from 'Unidad Corona Mantenimiento'
  ) then
    raise exception 'La API de encabezados devolvió un grupo de costo distinto';
  end if;

  select count(*) into v_actual from public.fn_api_publica_detalle_ucm();
  select count(*) into v_esperado
  from public.detalle_pedido d
  join public.pedido p on p.pedido_id = d.pedido_id
  where d.active and p.active and p.grupo_costo = 'Unidad Corona Mantenimiento';
  if v_actual <> v_esperado then
    raise exception 'Detalles incompletos o duplicados: recibidos %, esperados %', v_actual, v_esperado;
  end if;

  if exists (
    select 1
    from public.fn_api_publica_detalle_ucm() detalle
    where detalle.grupo_costo is distinct from 'Unidad Corona Mantenimiento'
      or not exists (
        select 1
        from public.pedido p
        where p.pedido_id = detalle.pedido_id
          and p.nro_sc::text = detalle.nro_sc
          and p.active
          and p.grupo_costo = 'Unidad Corona Mantenimiento'
      )
  ) then
    raise exception 'La API de detalles devolvió una fila fuera del grupo o sin encabezado válido';
  end if;
end;
$$;
