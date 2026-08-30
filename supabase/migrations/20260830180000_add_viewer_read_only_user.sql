-- user1@corimayo.com is a read-only application user.
update auth.users
set raw_app_meta_data = coalesce(raw_app_meta_data, '{}'::jsonb) || jsonb_build_object('role', 'viewer')
where id = '0cd337e1-fde2-4568-bcbf-6b6eee1c9d56'::uuid;

do $$
declare
  tabla text;
begin
  foreach tabla in array array[
    'pedido', 'detalle_pedido', 'detalle_ingreso',
    'solicitud_historial_estados', 'detalle_historial_estados', 'estados_catalogo'
  ] loop
    execute format('drop policy if exists authenticated_all on public.%I', tabla);
    execute format('create policy authenticated_select on public.%I for select to authenticated using (true)', tabla);
    execute format('create policy authenticated_insert on public.%I for insert to authenticated with check ((select coalesce(auth.jwt() -> ''app_metadata'' ->> ''role'', '''')) <> ''viewer'')', tabla);
    execute format('create policy authenticated_update on public.%I for update to authenticated using ((select coalesce(auth.jwt() -> ''app_metadata'' ->> ''role'', '''')) <> ''viewer'') with check ((select coalesce(auth.jwt() -> ''app_metadata'' ->> ''role'', '''')) <> ''viewer'')', tabla);
    execute format('create policy authenticated_delete on public.%I for delete to authenticated using ((select coalesce(auth.jwt() -> ''app_metadata'' ->> ''role'', '''')) <> ''viewer'')', tabla);
  end loop;
end $$;

drop policy if exists documentos_insert on storage.objects;
create policy documentos_insert on storage.objects
for insert to authenticated
with check (
  bucket_id = 'Documentos'
  and (select coalesce(auth.jwt() -> 'app_metadata' ->> 'role', '')) <> 'viewer'
);
