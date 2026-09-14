-- Evita solicitudes duplicadas por Nro. SC en pedidos activos.
-- Normaliza valores como "SC001307", "001307" y "1307" al mismo identificador.
create unique index if not exists idx_pedido_active_nro_sc_unique
on pedido (
  (coalesce(nullif(ltrim(regexp_replace(nro_sc, '\D', '', 'g'), '0'), ''), '0'))
)
where active and nro_sc is not null and btrim(nro_sc) <> '';
