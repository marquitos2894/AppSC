# Alertas y notificaciones de AppSC

La migración `20260926090000_alertas_y_notificaciones.sql` crea las tablas, políticas RLS, RPC, triggers y tareas programadas. Ya está aplicada en el proyecto Supabase `qhsizmayuhnlvcjcomlx`.

## Push con AppSC cerrada

La app web y la Edge Function necesitan las mismas claves VAPID:

- Frontend (Vercel y entorno local): `VITE_PUSH_PUBLIC_KEY` con la clave pública.
- Edge Function `despachar-notificaciones`: `VAPID_PUBLIC_KEY`, `VAPID_PRIVATE_KEY` y `VAPID_SUBJECT`.
- Crear una clave secreta nombrada `notifications` en Supabase y guardar su valor en Vault con el nombre `appsc_notifications_api_key`. La tarea `appsc-despachar-push` consulta ese nombre y ejecuta la función cada minuto.

La función se despliega desde Supabase MCP. Las entregas se reclaman y confirman por suscripción, con reintentos individuales. No subir `VAPID_PRIVATE_KEY` ni la clave secreta al repositorio. La clave pública de VAPID debe ser idéntica en el frontend y la Edge Function.

La suscripción se solicita únicamente al pulsar “Activar notificaciones del navegador”. Cada perfil de navegador debe activar su propia suscripción. El centro interno funciona aunque el usuario no habilite push.

## Tareas programadas

- `appsc-revisar-alertas-0900-lima`: revisión diaria a las 09:00 de Lima (14:00 UTC).
- `appsc-despachar-push`: busca y entrega avisos pendientes cada minuto.

Si la clave de Vault aún no existe cuando se instala la migración, el despachador no enviará solicitudes hasta que se guarde. Los permisos del navegador, VAPID y la clave nombrada son requisitos de plataforma; se configuran fuera del código fuente.
