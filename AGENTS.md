# AGENTS.md

AppSC es una SPA Vue 3 de gestión de pedidos con backend Supabase. Repositorio: `marquitos2894/AppSC`, rama principal `main`.

## Reglas siempre activas

- JavaScript puro con `<script setup>` y Composition API. La única excepción TypeScript es `supabase/functions/leer-pdf/index.ts`.
- PrimeVue permanece en v4.3.9: usar `Select`, `DatePicker` y `Drawer`; no migrar a v5.
- Los componentes PrimeVue y directivas se auto-importan. Excepciones: `Chart`, `useToast` y `useConfirm` según la configuración existente.
- La lógica de negocio vive en Supabase (triggers/RPC); el frontend solo lee y escribe.
- Resolver estados por nombre mediante `estadosStore`; nunca asumir que `estado_id` equivale a `orden`.
- Mantener el tema claro forzado y los tokens/colores existentes.
- Comandos: `npm run dev`, `npm run build` (única verificación), `npm run preview`.
- Supabase se opera por MCP; no usar una CLI local inexistente.

## Contexto bajo demanda

No leer por defecto `node_modules/`, `dist/`, `package-lock.json`, `supabase/config.toml`, `supabase/schema.sql`, `src/styles/main.css` ni `prompt-app-pedidos.md`. Consultarlos solo si la tarea afecta dependencias, configuración, base de datos, estilos globales o el prompt histórico.

Para reglas detalladas de estados, RLS, Storage, Edge Functions, Auth y gotchas del frontend, consultar [docs/context-reference.md](docs/context-reference.md).

## Mapa rápido

- `src/stores/`: estado y acceso a Supabase.
- `src/components/`: UI y diálogos PrimeVue.
- `src/views/`: páginas de pedidos, ítems y dashboard.
- `supabase/schema.sql`: esquema declarativo de referencia.
- `supabase/functions/leer-pdf/`: función Edge para leer PDFs.
