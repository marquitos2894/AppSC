-- Los privilegios predeterminados del proyecto exponen nuevas funciones a anon y authenticated.
-- Las RPC de alertas necesitan permisos explícitos por rol.

revoke all on function public.trg_notificacion_estado() from public, anon, authenticated, service_role;
revoke all on function public.trg_resolver_alertas_operativas() from public, anon, authenticated, service_role;
revoke all on function public.fn_alerta_evento_vigente(uuid) from public, anon, authenticated, service_role;

revoke all on function public.fn_listar_notificaciones(boolean, integer) from public, anon, authenticated, service_role;
revoke all on function public.fn_contar_notificaciones_no_leidas() from public, anon, authenticated, service_role;
revoke all on function public.fn_marcar_notificacion_leida(uuid) from public, anon, authenticated, service_role;
revoke all on function public.fn_marcar_todas_notificaciones_leidas() from public, anon, authenticated, service_role;
revoke all on function public.fn_registrar_suscripcion_push(jsonb) from public, anon, authenticated, service_role;
revoke all on function public.fn_eliminar_suscripcion_push(text) from public, anon, authenticated, service_role;

revoke all on function public.fn_reclamar_push_notificaciones(integer) from public, anon, authenticated, service_role;
revoke all on function public.fn_confirmar_entrega_push(uuid, uuid, text) from public, anon, authenticated, service_role;
revoke all on function public.fn_revisar_alertas_operativas() from public, anon, authenticated, service_role;
revoke all on function public.fn_alertas_publicas_vigentes(text, text, text, text) from public, anon, authenticated, service_role;

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
