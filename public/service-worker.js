self.addEventListener('push', (event) => {
  let payload = {}
  try {
    payload = event.data ? event.data.json() : {}
  } catch {
    payload = { body: event.data?.text() || 'Tienes una nueva notificación de AppSC.' }
  }

  event.waitUntil(self.registration.showNotification(payload.title || 'AppSC', {
    body: payload.body || 'Tienes una nueva notificación.',
    data: { url: payload.url || '/' },
    tag: payload.tag || 'appsc-notificacion',
    renotify: false,
  }))
})

self.addEventListener('notificationclick', (event) => {
  event.notification.close()
  const target = new URL(event.notification.data?.url || '/', self.location.origin).href
  event.waitUntil((async () => {
    const windows = await self.clients.matchAll({ type: 'window', includeUncontrolled: true })
    const existing = windows.find((client) => new URL(client.url).origin === self.location.origin)
    if (existing) {
      await existing.navigate(target)
      return existing.focus()
    }
    return self.clients.openWindow(target)
  })())
})
