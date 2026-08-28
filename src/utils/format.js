const qtyFormat = new Intl.NumberFormat('es-PE', {
  minimumFractionDigits: 0,
  maximumFractionDigits: 2,
})

export function formatQty(value) {
  return qtyFormat.format(Number(value ?? 0))
}

const DATE_ONLY = /^(\d{4})-(\d{2})-(\d{2})$/

export function formatDate(value, withTime = false) {
  if (!value) return '—'
  let date
  if (typeof value === 'string' && DATE_ONLY.test(value)) {
    // Fecha pura: se construye con Date.UTC para que el despliegue en UTC
    // nunca cambie de día, sin depender del parseo del motor.
    const [, y, m, d] = value.match(DATE_ONLY)
    date = new Date(Date.UTC(+y, +m - 1, +d))
  } else {
    date = new Date(value)
  }
  return date.toLocaleDateString('es-PE', {
    timeZone: 'UTC',
    day: '2-digit',
    month: 'short',
    year: 'numeric',
    ...(withTime ? { hour: '2-digit', minute: '2-digit' } : {}),
  })
}

// Convierte 'YYYY-MM-DD' (o Date/ISO) a un Date LOCAL a medianoche local.
// Se usa para ligar DatePickers: evita el desfase de un día que causa
// `new Date('YYYY-MM-DD')` (que se interpreta como medianoche UTC).
export function toLocalDate(value) {
  if (!value) return null
  if (typeof value === 'string') {
    const m = value.match(/^(\d{4})-(\d{2})-(\d{2})/)
    if (m) {
      const d = new Date(+m[1], +m[2] - 1, +m[3])
      return isNaN(d) ? null : d
    }
  }
  const d = new Date(value)
  return isNaN(d) ? null : d
}

export function toISODate(value) {
  if (!value) return null
  if (typeof value === 'string') return value.slice(0, 10)
  return `${value.getFullYear()}-${String(value.getMonth() + 1).padStart(2, '0')}-${String(value.getDate()).padStart(2, '0')}`
}
