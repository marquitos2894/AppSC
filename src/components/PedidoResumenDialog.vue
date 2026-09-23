<script setup>
import { computed, ref, watch } from 'vue'
import { useDetallePedidoStore } from '@/stores/detallePedidoStore'
import { useToast } from 'primevue/usetoast'
import { formatDate, formatQty } from '@/utils/format'

const props = defineProps({
  pedido: { type: Object, default: null },
  items: { type: Array, default: () => [] },
  estadoPedido: { type: String, default: '' },
  visible: { type: Boolean, default: false },
  datosComplementarios: { type: Boolean, default: true },
})
const emit = defineEmits(['update:visible'])

const detalleStore = useDetallePedidoStore()
const toast = useToast()

const texto = ref('')
const loading = ref(false)
const vistaActual = ref('vista')
const comentariosPorItem = ref(new Map())
const atencionesPorItem = ref(new Map())
const secciones = ref({ atendidos: true, pendientes: true, incidencias: true, enProceso: true })

function esIncidencia(item) {
  return ['Observado', 'Rechazado'].includes(item?.estados_catalogo?.nombre)
}

function codigoSc(nroSc) {
  const valor = String(nroSc ?? '').trim()
  if (!valor) return 'SC sin número'
  return /^sc/i.test(valor) ? valor : `SC${valor}`
}

function etiquetaAtencion(estado) {
  const etiquetas = { PENDIENTE: 'Pendiente', PARCIAL: 'Parcial', COMPLETO: 'Completo' }
  return etiquetas[estado] ?? 'No registrado'
}

function descripcionItem(item) {
  return `${item.nro_parte || 'Sin nro. de parte'} — ${item.material || 'Sin descripción'}`
}

const pendientes = computed(() =>
  props.items.filter((item) => !esIncidencia(item) && detalleStore.pendiente(item) > 0),
)

const atendidos = computed(() =>
  props.items.filter((item) => {
    const aprobada = Number(item.cantidad_aprobada ?? 0)
    return !esIncidencia(item) && aprobada > 0 && Number(item.cantidad_atendida ?? 0) >= aprobada
  }),
)

const incidencias = computed(() => props.items.filter(esIncidencia))

const enProceso = computed(() =>
  props.items.filter((item) =>
    !esIncidencia(item) &&
    !atendidos.value.includes(item) &&
    !pendientes.value.includes(item),
  ),
)

function alternarSeccion(seccion) {
  secciones.value[seccion] = !secciones.value[seccion]
}

function fechaAprox(item) {
  return item.fecha_aprox_atencion ? formatDate(item.fecha_aprox_atencion) : 'Fecha por confirmar'
}

function estadoActual(item) {
  return item.estados_catalogo?.nombre || 'No registrado'
}

function comentarioItem(item) {
  return comentariosPorItem.value.get(item.detalle_id) || item.comentario || 'Sin comentario registrado'
}

function atencionesItem(item) {
  return atencionesPorItem.value.get(item.detalle_id) || []
}

function etiquetaAtencionItem(ingreso) {
  const partes = [`${formatQty(ingreso.cantidad)} und.`]
  if (ingreso.fecha) partes.push(formatDate(ingreso.fecha))
  if (ingreso.documento) partes.push(`Doc. ${ingreso.documento}`)
  if (ingreso.comentario?.trim()) partes.push(ingreso.comentario.trim())
  return partes.join(' · ')
}

function escaparHtml(valor) {
  return String(valor ?? '')
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&#039;')
}

function detalleCorreo(item, tipo) {
  if (tipo === 'atendidos') {
    const ingresos = atencionesItem(item)
    return ingresos.length
      ? ingresos.map((ingreso) => etiquetaAtencionItem(ingreso)).join('\n')
      : 'Sin detalle registrado'
  }
  if (tipo === 'pendientes') return `F. aprox.: ${fechaAprox(item)}`
  if (tipo === 'incidencias') return 'Requiere aclaración'
  return 'En seguimiento'
}

function tablaCorreo(items, titulo, tipo, color = '#3b6e8f') {
  const filas = items.length
    ? items.map((item) => `
        <tr>
          <td style="padding:8px 9px;border-top:1px solid #e5ebef;vertical-align:top;word-break:break-word"><strong style="color:#1e2a38">${escaparHtml(item.nro_parte || 'Sin nro. de parte')}</strong><br><span style="color:#526575">${escaparHtml(item.material || 'Sin descripción')}</span></td>
          <td style="padding:8px 5px;border-top:1px solid #e5ebef;text-align:center;vertical-align:top">${escaparHtml(formatQty(item.cantidad_solicitada))}</td>
          <td style="padding:8px 5px;border-top:1px solid #e5ebef;text-align:center;vertical-align:top">${escaparHtml(formatQty(item.cantidad_aprobada))}</td>
          <td style="padding:8px 5px;border-top:1px solid #e5ebef;text-align:center;vertical-align:top">${escaparHtml(formatQty(item.cantidad_atendida))}</td>
          <td style="padding:8px 7px;border-top:1px solid #e5ebef;vertical-align:top"><span style="display:inline-block;padding:3px 7px;border-radius:999px;background:${color}18;color:${color};font-weight:700;font-size:11px">${escaparHtml(estadoActual(item))}</span></td>
          <td style="padding:8px 9px;border-top:1px solid #e5ebef;vertical-align:top;word-break:break-word">${escaparHtml(comentarioItem(item))}</td>
          <td style="padding:8px 9px;border-top:1px solid #e5ebef;vertical-align:top;word-break:break-word">${escaparHtml(detalleCorreo(item, tipo)).replaceAll('\n', '<br>')}</td>
        </tr>`).join('')
    : `<tr><td colspan="7" style="padding:12px;text-align:center;color:#718096">Sin ítems en esta sección.</td></tr>`

  return `
    <section style="margin:20px 0">
      <div style="padding:10px 12px;background:${color}12;border-left:3px solid ${color};font-size:13px;font-weight:700;color:#1e2a38">${escaparHtml(titulo)} <span style="color:#64748b;font-weight:600">(${items.length})</span></div>
      <table role="presentation" cellspacing="0" cellpadding="0" width="100%" style="width:100%;border-collapse:collapse;table-layout:fixed;font-family:Arial,sans-serif;font-size:12px;color:#334155">
        <thead><tr style="background:#f7fafc;color:#526575;font-size:10px;text-transform:uppercase;letter-spacing:.04em">
          <th align="left" style="padding:8px 9px;width:25%">Repuesto</th><th style="padding:8px 5px;width:7%">Solic.</th><th style="padding:8px 5px;width:7%">Aprob.</th><th style="padding:8px 5px;width:7%">Atend.</th><th align="left" style="padding:8px 7px;width:13%">Estado</th><th align="left" style="padding:8px 9px;width:20%">Comentario</th><th align="left" style="padding:8px 9px;width:21%">Detalle</th>
        </tr></thead><tbody>${filas}</tbody>
      </table>
    </section>`
}

function construirCorreoHtml() {
  if (!props.pedido) return ''
  return `<div style="max-width:980px;margin:0 auto;padding:24px;background:#f5f8fa;font-family:Arial,sans-serif;color:#334155">
    <div style="padding:20px 22px;background:#1e2a38;color:#fff;border-radius:10px 10px 0 0">
      <div style="font-size:11px;letter-spacing:.08em;text-transform:uppercase;color:#b9d0df">AppSC · Resumen de pedido</div>
      <div style="margin-top:7px;font-size:22px;font-weight:700">${escaparHtml(codigoSc(props.pedido.nro_sc))}</div>
      <div style="margin-top:5px;color:#dce8ef;font-size:13px">${escaparHtml(props.pedido.motivo || 'Sin motivo registrado')}</div>
      <div style="margin-top:14px;font-size:12px"><span style="display:inline-block;margin-right:10px;padding:4px 8px;border-radius:999px;background:#ffffff20">Estado: ${escaparHtml(props.estadoPedido || 'No registrado')}</span><span style="display:inline-block;padding:4px 8px;border-radius:999px;background:#ffffff20">Atención: ${escaparHtml(etiquetaAtencion(props.pedido.estado_atencion))}</span></div>
    </div>
    <div style="padding:4px 22px 22px;background:#fff;border:1px solid #dce6ec;border-top:0;border-radius:0 0 10px 10px">
      ${tablaCorreo(enProceso.value, 'Repuestos en proceso', 'proceso', '#3b6e8f')}
      ${tablaCorreo(atendidos.value, 'Repuestos atendidos', 'atendidos', '#2e8b74')}
      ${tablaCorreo(pendientes.value, 'Pendientes de atención', 'pendientes', '#b07a1f')}
      ${tablaCorreo(incidencias.value, 'Observados y rechazados', 'incidencias', '#d97706')}
    </div>
  </div>`
}

function construirResumen() {
  if (!props.pedido) return ''

  const lineas = [
    codigoSc(props.pedido.nro_sc),
    `Estado actual del pedido: ${props.estadoPedido || 'No registrado'}`,
    `Estado de atención: ${etiquetaAtencion(props.pedido.estado_atencion)}`,
    '',
  ]

  lineas.push('Repuestos atendidos:')
  if (atendidos.value.length) {
    for (const item of atendidos.value) {
      const atenciones = atencionesItem(item)
      const detalle = atenciones.length
        ? atenciones.map((ingreso) => etiquetaAtencionItem(ingreso)).join(' | ')
        : 'Sin detalle de atención registrado'
      lineas.push(
        `- ${descripcionItem(item)}: solicitada ${formatQty(item.cantidad_solicitada)}. Aprobada ${formatQty(item.cantidad_aprobada)}. Atendida ${formatQty(item.cantidad_atendida)}. Estado actual: ${estadoActual(item)}. Comentario: ${comentarioItem(item)}. Detalle de atención: ${detalle}.`,
      )
    }
  } else {
    lineas.push('- No se registran repuestos atendidos.')
  }

  lineas.push('', 'Repuestos pendientes de atención:')

  if (pendientes.value.length) {
    for (const item of pendientes.value) {
      lineas.push(
        `- ${descripcionItem(item)}: solicitada ${formatQty(item.cantidad_solicitada)}. Aprobada ${formatQty(item.cantidad_aprobada)}. Atendida ${formatQty(item.cantidad_atendida)}. Pendiente ${formatQty(detalleStore.pendiente(item))}. Estado actual: ${estadoActual(item)}. Comentario: ${comentarioItem(item)}. Fecha aproximada de atención: ${fechaAprox(item)}.`,
      )
    }
  } else {
    lineas.push('- No hay repuestos pendientes de atención.')
  }

  lineas.push('', 'Repuestos observados o rechazados:')
  if (incidencias.value.length) {
    for (const item of incidencias.value) {
      lineas.push(
        `- ${descripcionItem(item)}: solicitada ${formatQty(item.cantidad_solicitada)}. Aprobada ${formatQty(item.cantidad_aprobada)}. Estado actual: ${estadoActual(item)}. Comentario: ${comentarioItem(item)}.`,
      )
    }
  } else {
    lineas.push('- No se registran repuestos observados o rechazados.')
  }

  lineas.push('', 'Repuestos en proceso:')
  if (enProceso.value.length) {
    for (const item of enProceso.value) {
      lineas.push(
        `- ${descripcionItem(item)}: solicitada ${formatQty(item.cantidad_solicitada)}. Estado actual: ${estadoActual(item)}. Comentario: ${comentarioItem(item)}.`,
      )
    }
  } else {
    lineas.push('- No se registran repuestos en proceso.')
  }

  return lineas.join('\n')
}

async function generarResumen() {
  if (!props.pedido) return
  loading.value = true
  texto.value = ''
  comentariosPorItem.value = new Map()
  atencionesPorItem.value = new Map()
  if (!props.datosComplementarios) {
    texto.value = construirResumen()
    loading.value = false
    return
  }
  try {
    const [historialResult, atencionesResult] = await Promise.allSettled([
      detalleStore.fetchComentariosIncidencias(props.items.map((item) => item.detalle_id)),
      detalleStore.fetchIngresosItems(atendidos.value.map((item) => item.detalle_id)),
    ])
    const historial = historialResult.status === 'fulfilled' ? historialResult.value : []
    const atenciones = atencionesResult.status === 'fulfilled' ? atencionesResult.value : {}
    const comentarios = new Map()

    for (const item of props.items) {
      const movimiento = historial.find(
        (registro) =>
          registro.detalle_id === item.detalle_id && registro.estado_id === item.estado_actual_id,
      )
      if (movimiento?.comentario?.trim()) comentarios.set(item.detalle_id, movimiento.comentario.trim())
    }
    comentariosPorItem.value = comentarios
    atencionesPorItem.value = new Map(Object.entries(atenciones).map(([id, values]) => [Number(id), values]))
    texto.value = construirResumen()
    if (historialResult.status === 'rejected' || atencionesResult.status === 'rejected') {
      toast.add({
        severity: 'warn',
        summary: 'Datos complementarios parciales',
        detail: 'El resumen se generó con la información disponible.',
        life: 6000,
      })
    }
  } catch (error) {
    texto.value = construirResumen()
    toast.add({
      severity: 'warn',
      summary: 'Datos complementarios no disponibles',
      detail: 'El resumen se generó con la información principal del pedido.',
      life: 6000,
    })
  } finally {
    loading.value = false
  }
}

async function copiarResumen() {
  try {
    if (!navigator.clipboard) throw new Error('Portapapeles no disponible')
    await navigator.clipboard.writeText(texto.value)
    toast.add({ severity: 'success', summary: 'Resumen copiado', life: 3000 })
  } catch (error) {
    toast.add({
      severity: 'warn',
      summary: 'No se pudo copiar',
      detail: 'Puedes seleccionar el texto y copiarlo manualmente.',
      life: 6000,
    })
  }
}

async function copiarCorreoConFormato() {
  try {
    if (!navigator.clipboard?.write || typeof ClipboardItem === 'undefined') {
      throw new Error('Portapapeles HTML no disponible')
    }
    const html = construirCorreoHtml()
    await navigator.clipboard.write([
      new ClipboardItem({
        'text/html': new Blob([html], { type: 'text/html' }),
        'text/plain': new Blob([texto.value], { type: 'text/plain' }),
      }),
    ])
    toast.add({ severity: 'success', summary: 'Correo con formato copiado', detail: 'Pégalo directamente en Exchange.', life: 3500 })
  } catch (error) {
    toast.add({ severity: 'warn', summary: 'No se pudo copiar el formato', detail: 'Usa “Copiar texto” como alternativa.', life: 6000 })
  }
}

watch(
  () => props.visible,
  (visible) => {
    if (visible) {
      vistaActual.value = 'vista'
      secciones.value = { atendidos: true, pendientes: true, incidencias: true, enProceso: true }
      generarResumen()
    }
  },
)
</script>

<template>
  <Dialog
    :visible="visible"
    modal
    header="Resumen para correo"
    :style="{ width: 'min(1100px, calc(100vw - 3rem))' }"
    @update:visible="emit('update:visible', $event)"
  >
    <div class="resumen-dialogo">
      <div v-if="loading" class="resumen-cargando">
        <ProgressSpinner stroke-width="4" style="width: 28px; height: 28px" />
        <span>Generando resumen…</span>
      </div>

      <template v-else>
        <header class="resumen-cabecera">
          <div class="resumen-cabecera-principal">
            <div class="resumen-cabecera-icono" aria-hidden="true"><i class="pi pi-envelope"></i></div>
            <div>
              <h2>{{ codigoSc(pedido?.nro_sc) }}</h2>
              <p>{{ pedido?.motivo }}</p>
            </div>
          </div>
          <div class="resumen-estados" aria-label="Estado del pedido">
            <EstadoTag :nombre="estadoPedido || 'No registrado'" />
            <span class="resumen-atencion">
              <i class="pi pi-box" aria-hidden="true"></i>
              Atención {{ etiquetaAtencion(pedido?.estado_atencion) }}
            </span>
          </div>
        </header>

        <div class="resumen-vista-switch" role="tablist" aria-label="Modo de resumen">
          <Button
            label="Vista previa"
            icon="pi pi-table"
            size="small"
            :text="vistaActual !== 'vista'"
            :class="{ 'resumen-vista-activa': vistaActual === 'vista' }"
            role="tab"
            :aria-selected="vistaActual === 'vista'"
            @click="vistaActual = 'vista'"
          />
          <Button
            label="Editar texto"
            icon="pi pi-pencil"
            size="small"
            :text="vistaActual !== 'texto'"
            :class="{ 'resumen-vista-activa': vistaActual === 'texto' }"
            role="tab"
            :aria-selected="vistaActual === 'texto'"
            @click="vistaActual = 'texto'"
          />
        </div>

        <div v-if="vistaActual === 'vista'" class="resumen-vista" role="tabpanel">
          <section class="resumen-seccion" aria-labelledby="en-proceso-titulo">
            <div class="resumen-seccion-cabecera">
              <div>
                <h3 id="en-proceso-titulo"><i class="pi pi-list" aria-hidden="true"></i> Repuestos en proceso</h3>
                <p>Ítems que aún no fueron aprobados, observados, rechazados ni atendidos.</p>
              </div>
              <div class="resumen-seccion-acciones">
                <span class="resumen-contador">{{ enProceso.length }}</span>
                <Button
                  :icon="secciones.enProceso ? 'pi pi-chevron-up' : 'pi pi-chevron-down'"
                  text rounded size="small"
                  :aria-label="secciones.enProceso ? 'Contraer repuestos en proceso' : 'Expandir repuestos en proceso'"
                  @click="alternarSeccion('enProceso')"
                />
              </div>
            </div>

            <DataTable
              v-if="secciones.enProceso && enProceso.length"
              :value="enProceso"
              class="resumen-tabla"
              table-style="width: 100%; table-layout: fixed"
            >
              <Column header="Repuesto" style="width: 42%">
                <template #body="{ data }">
                  <div class="repuesto-cell">
                    <i class="pi pi-box" aria-hidden="true"></i>
                    <div>
                      <span class="mono">{{ data.nro_parte || 'Sin nro. de parte' }}</span>
                      <span>{{ data.material || 'Sin descripción' }}</span>
                    </div>
                  </div>
                </template>
              </Column>
              <Column header="Solicitado" header-class="columna-numerica" body-class="columna-numerica" style="width: 18%">
                <template #body="{ data }"><span class="resumen-cantidad">{{ formatQty(data.cantidad_solicitada) }}</span></template>
              </Column>
              <Column header="Estado" style="width: 40%">
                <template #body="{ data }">
                  <span v-tooltip.top="`Comentario: ${comentarioItem(data)}`"><EstadoTag :nombre="estadoActual(data)" size="sm" /></span>
                </template>
              </Column>
            </DataTable>
            <div v-else-if="secciones.enProceso" class="resumen-vacio">
              <i class="pi pi-check-circle" aria-hidden="true"></i>
              <span>No se registran repuestos en proceso.</span>
            </div>
          </section>
          <section class="resumen-seccion" aria-labelledby="atendidos-titulo">
            <div class="resumen-seccion-cabecera">
              <div>
                <h3 id="atendidos-titulo"><i class="pi pi-check-circle resumen-icono-atendido" aria-hidden="true"></i> Repuestos atendidos</h3>
                <p>Ítems cuya cantidad aprobada ya fue cubierta por completo.</p>
              </div>
              <div class="resumen-seccion-acciones">
                <span class="resumen-contador resumen-contador--atendido">{{ atendidos.length }}</span>
                <Button
                  :icon="secciones.atendidos ? 'pi pi-chevron-up' : 'pi pi-chevron-down'"
                  text rounded size="small"
                  :aria-label="secciones.atendidos ? 'Contraer repuestos atendidos' : 'Expandir repuestos atendidos'"
                  @click="alternarSeccion('atendidos')"
                />
              </div>
            </div>

            <DataTable
              v-if="secciones.atendidos && atendidos.length"
              :value="atendidos"
              class="resumen-tabla"
              table-style="width: 100%; table-layout: fixed"
            >
              <Column header="Repuesto" style="width: 31%">
                <template #body="{ data }">
                  <div class="repuesto-cell">
                    <i class="pi pi-box" aria-hidden="true"></i>
                    <div>
                      <span class="mono">{{ data.nro_parte || 'Sin nro. de parte' }}</span>
                      <span>{{ data.material || 'Sin descripción' }}</span>
                    </div>
                  </div>
                </template>
              </Column>
              <Column header="Solic." header-class="columna-numerica" body-class="columna-numerica" style="width: 8%">
                <template #body="{ data }"><span class="resumen-cantidad">{{ formatQty(data.cantidad_solicitada) }}</span></template>
              </Column>
              <Column header="Aprob." header-class="columna-aprobada columna-numerica" body-class="columna-numerica" style="width: 8%">
                <template #body="{ data }"><span class="resumen-cantidad resumen-cantidad--aprobada">{{ formatQty(data.cantidad_aprobada) }}</span></template>
              </Column>
              <Column header="Atend." header-class="columna-atendida columna-numerica" body-class="columna-numerica" style="width: 8%">
                <template #body="{ data }"><span class="resumen-cantidad resumen-cantidad--atendida">{{ formatQty(data.cantidad_atendida) }}</span></template>
              </Column>
              <Column header="Estado" style="width: 16%">
                <template #body="{ data }">
                  <span v-tooltip.top="`Comentario: ${comentarioItem(data)}`"><EstadoTag :nombre="estadoActual(data)" size="sm" /></span>
                </template>
              </Column>
              <Column header="Detalle de atención" style="width: 29%">
                <template #body="{ data }">
                  <div class="atencion-detalle-cell">
                    <span v-for="ingreso in atencionesItem(data)" :key="ingreso.ingreso_id">
                      <i class="pi pi-calendar-check" aria-hidden="true"></i>
                      {{ etiquetaAtencionItem(ingreso) }}
                    </span>
                    <span v-if="!atencionesItem(data).length" class="atencion-detalle-vacio">Sin detalle registrado</span>
                  </div>
                </template>
              </Column>
            </DataTable>
            <div v-else-if="secciones.atendidos" class="resumen-vacio">
              <i class="pi pi-check-circle" aria-hidden="true"></i>
              <span>No se registran repuestos atendidos.</span>
            </div>
          </section>

          <section class="resumen-seccion" aria-labelledby="pendientes-titulo">
            <div class="resumen-seccion-cabecera">
              <div>
                <h3 id="pendientes-titulo"><i class="pi pi-clock" aria-hidden="true"></i> Pendientes de atención</h3>
                <p>Ítems aprobados que todavía requieren entrega.</p>
              </div>
              <div class="resumen-seccion-acciones">
                <span class="resumen-contador">{{ pendientes.length }}</span>
                <Button
                  :icon="secciones.pendientes ? 'pi pi-chevron-up' : 'pi pi-chevron-down'"
                  text rounded size="small"
                  :aria-label="secciones.pendientes ? 'Contraer pendientes de atención' : 'Expandir pendientes de atención'"
                  @click="alternarSeccion('pendientes')"
                />
              </div>
            </div>

            <DataTable
              v-if="secciones.pendientes && pendientes.length"
              :value="pendientes"
              class="resumen-tabla"
              table-style="width: 100%; table-layout: fixed"
            >
              <Column header="Repuesto" style="width: 30%">
                <template #body="{ data }">
                  <div class="repuesto-cell">
                    <i class="pi pi-box" aria-hidden="true"></i>
                    <div>
                      <span class="mono">{{ data.nro_parte || 'Sin nro. de parte' }}</span>
                      <span>{{ data.material || 'Sin descripción' }}</span>
                    </div>
                  </div>
                </template>
              </Column>
              <Column header="Solic." header-class="columna-numerica" body-class="columna-numerica" style="width: 8%">
                <template #body="{ data }">
                  <span class="resumen-cantidad">{{ formatQty(data.cantidad_solicitada) }}</span>
                </template>
              </Column>
              <Column header="Aprob." header-class="columna-aprobada columna-numerica" body-class="columna-numerica" style="width: 8%">
                <template #body="{ data }"><span class="resumen-cantidad resumen-cantidad--aprobada">{{ formatQty(data.cantidad_aprobada) }}</span></template>
              </Column>
              <Column header="Atend." header-class="columna-atendida columna-numerica" body-class="columna-numerica" style="width: 8%">
                <template #body="{ data }"><span class="resumen-cantidad resumen-cantidad--atendida">{{ formatQty(data.cantidad_atendida) }}</span></template>
              </Column>
              <Column header="Estado" style="width: 16%">
                <template #body="{ data }">
                  <span v-tooltip.top="`Comentario: ${comentarioItem(data)}`"><EstadoTag :nombre="estadoActual(data)" size="sm" /></span>
                </template>
              </Column>
              <Column header="Fecha aprox" style="width: 30%">
                <template #body="{ data }">
                  <span class="resumen-fecha" :class="{ pendiente: !data.fecha_aprox_atencion }">
                    <i class="pi pi-calendar" aria-hidden="true"></i>{{ fechaAprox(data) }}
                  </span>
                </template>
              </Column>
            </DataTable>
            <div v-else-if="secciones.pendientes" class="resumen-vacio">
              <i class="pi pi-check-circle" aria-hidden="true"></i>
              <span>No hay repuestos pendientes de atención.</span>
            </div>
          </section>

          <section class="resumen-seccion" aria-labelledby="incidencias-titulo">
            <div class="resumen-seccion-cabecera">
              <div>
                <h3 id="incidencias-titulo"><i class="pi pi-exclamation-triangle" aria-hidden="true"></i> Observados y rechazados</h3>
                <p>Ítems que requieren una aclaración en la respuesta.</p>
              </div>
              <div class="resumen-seccion-acciones">
                <span class="resumen-contador resumen-contador--incidencia">{{ incidencias.length }}</span>
                <Button
                  :icon="secciones.incidencias ? 'pi pi-chevron-up' : 'pi pi-chevron-down'"
                  text rounded size="small"
                  :aria-label="secciones.incidencias ? 'Contraer observados y rechazados' : 'Expandir observados y rechazados'"
                  @click="alternarSeccion('incidencias')"
                />
              </div>
            </div>

            <DataTable
              v-if="secciones.incidencias && incidencias.length"
              :value="incidencias"
              class="resumen-tabla"
              table-style="width: 100%; table-layout: fixed"
            >
              <Column header="Repuesto" style="width: 48%">
                <template #body="{ data }">
                  <div class="repuesto-cell">
                    <i class="pi pi-box" aria-hidden="true"></i>
                    <div>
                      <span class="mono">{{ data.nro_parte || 'Sin nro. de parte' }}</span>
                      <span>{{ data.material || 'Sin descripción' }}</span>
                      <span class="resumen-motivo"><strong>Motivo:</strong> {{ comentarioItem(data) }}</span>
                    </div>
                  </div>
                </template>
              </Column>
              <Column header="Solic." header-class="columna-numerica" body-class="columna-numerica" style="width: 12%">
                <template #body="{ data }"><span class="resumen-cantidad">{{ formatQty(data.cantidad_solicitada) }}</span></template>
              </Column>
              <Column header="Aprob." header-class="columna-aprobada columna-numerica" body-class="columna-numerica" style="width: 12%">
                <template #body="{ data }"><span class="resumen-cantidad resumen-cantidad--aprobada">{{ formatQty(data.cantidad_aprobada) }}</span></template>
              </Column>
              <Column header="Estado" style="width: 28%">
                <template #body="{ data }">
                  <span v-tooltip.top="`Comentario: ${comentarioItem(data)}`"><EstadoTag :nombre="estadoActual(data)" size="sm" /></span>
                </template>
              </Column>
            </DataTable>
            <div v-else-if="secciones.incidencias" class="resumen-vacio">
              <i class="pi pi-check-circle" aria-hidden="true"></i>
              <span>No se registran repuestos observados o rechazados.</span>
            </div>
          </section>


        </div>

        <div v-else class="resumen-editor" role="tabpanel">
          <div class="resumen-editor-cabecera">
            <div>
              <h3>Texto para correo</h3>
              <p>Edita el contenido antes de copiarlo.</p>
            </div>
            <i class="pi pi-pencil" aria-hidden="true"></i>
          </div>
          <Textarea v-model="texto" rows="16" auto-resize fluid aria-label="Texto del resumen para correo" />
        </div>
      </template>
    </div>

    <template #footer>
      <Button label="Cerrar" text severity="secondary" @click="emit('update:visible', false)" />
      <Button label="Copiar texto" icon="pi pi-copy" text :disabled="loading || !texto" @click="copiarResumen" />
      <Button label="Copiar correo con formato" icon="pi pi-envelope" :disabled="loading || !texto" @click="copiarCorreoConFormato" />
    </template>
  </Dialog>
</template>

<style scoped>
.resumen-dialogo { min-height: 320px; }

.resumen-cabecera {
  display: flex;
  justify-content: space-between;
  align-items: flex-start;
  gap: 18px;
  padding-bottom: 18px;
  border-bottom: 1px solid var(--line);
}

.resumen-cabecera-principal,
.resumen-estados,
.resumen-atencion,
.repuesto-cell,
.resumen-fecha,
.resumen-seccion-cabecera h3,
.resumen-vacio,
.resumen-editor-cabecera { display: flex; align-items: center; }

.resumen-cabecera-principal { gap: 11px; min-width: 0; }

.resumen-cabecera-icono {
  width: 36px;
  height: 36px;
  display: grid;
  place-items: center;
  flex: 0 0 auto;
  border-radius: 10px;
  color: var(--accent-500);
  background: rgba(59, 110, 143, 0.12);
}

.resumen-cabecera h2,
.resumen-seccion-cabecera h3,
.resumen-editor-cabecera h3 { margin: 0; color: var(--text-strong); }

.resumen-cabecera h2 { font-family: var(--font-mono); font-size: 17px; letter-spacing: 0.01em; }

.resumen-cabecera p,
.resumen-seccion-cabecera p,
.resumen-editor-cabecera p { margin: 3px 0 0; color: var(--text-muted); font-size: 12.5px; }

.resumen-estados { justify-content: flex-end; flex-wrap: wrap; gap: 7px; }

.resumen-atencion {
  gap: 6px;
  padding: 4px 9px;
  border-radius: 999px;
  background: #f1f5f8;
  color: var(--text);
  font-size: 11.5px;
  font-weight: 600;
  white-space: nowrap;
}

.resumen-atencion i,
.resumen-seccion-cabecera h3 i,
.resumen-editor-cabecera > i { color: var(--accent-500); font-size: 12px; }

.resumen-vista-switch { display: flex; gap: 4px; margin-top: 14px; }
.resumen-vista-switch :deep(.p-button) { color: var(--text-muted); }
.resumen-vista-switch :deep(.resumen-vista-activa) { color: var(--accent-500); background: rgba(59, 110, 143, 0.1); }

.resumen-vista { display: flex; flex-direction: column; gap: 26px; padding-top: 20px; }

.resumen-seccion-cabecera {
  display: flex;
  align-items: flex-start;
  justify-content: space-between;
  gap: 16px;
  margin-bottom: 10px;
}

.resumen-seccion-acciones { display: flex; align-items: center; gap: 4px; }

.resumen-seccion-cabecera h3,
.resumen-editor-cabecera h3 { gap: 8px; font-size: 13px; }

.resumen-contador {
  min-width: 26px;
  height: 24px;
  display: grid;
  place-items: center;
  border-radius: 999px;
  background: rgba(59, 110, 143, 0.12);
  color: var(--accent-500);
  font-family: var(--font-mono);
  font-size: 12px;
  font-weight: 600;
}

.resumen-contador--incidencia { background: rgba(232, 163, 61, 0.14); color: #b07a1f; }
.resumen-contador--atendido { background: rgba(46, 139, 116, 0.12); color: var(--atendido); }
.resumen-icono-atendido { color: var(--atendido) !important; }

.repuesto-cell { align-items: flex-start; gap: 8px; min-width: 0; }
.repuesto-cell > i { margin-top: 3px; color: #9aabba; font-size: 12px; }
.repuesto-cell > div { display: flex; flex-direction: column; gap: 2px; min-width: 0; }
.repuesto-cell .mono { color: var(--text-strong); font-weight: 600; }
.repuesto-cell span:last-child { color: var(--text); font-size: 12.5px; line-height: 1.35; }

.resumen-cantidad {
  color: var(--accent-500);
  font-family: var(--font-mono);
  font-size: 13px;
  font-weight: 600;
  font-variant-numeric: tabular-nums;
}

.resumen-cantidad--atendida { color: var(--atendido); }
.resumen-cantidad--aprobada { color: #2f6f9f; }

.resumen-tabla :deep(.columna-aprobada) { color: #2f6f9f !important; }
.resumen-tabla :deep(.columna-atendida) { color: #2f8b74 !important; }
.resumen-tabla :deep(.columna-numerica) { text-align: center !important; }
.resumen-tabla :deep(.p-datatable-wrapper) { overflow-x: hidden; }
.resumen-tabla :deep(.p-datatable-table) { width: 100% !important; table-layout: fixed; }
.resumen-tabla :deep(.p-datatable-thead > tr > th),
.resumen-tabla :deep(.p-datatable-tbody > tr > td) {
  padding: 8px 7px;
  overflow-wrap: anywhere;
  vertical-align: top;
}

.resumen-fecha { gap: 6px; color: var(--text); font-size: 12.5px; white-space: nowrap; }
.resumen-fecha i { color: var(--accent-500); font-size: 12px; }
.resumen-fecha.pendiente { color: var(--text-muted); font-style: italic; }

.resumen-motivo { display: block; max-width: 290px; color: var(--text); font-size: 12.5px; line-height: 1.4; white-space: normal; }

.atencion-detalle-cell { display: flex; flex-direction: column; gap: 4px; color: var(--text); font-size: 12px; line-height: 1.35; overflow-wrap: anywhere; }
.atencion-detalle-cell span { display: flex; align-items: flex-start; gap: 6px; }
.atencion-detalle-cell i { margin-top: 2px; color: var(--atendido); font-size: 11px; }
.atencion-detalle-vacio { color: var(--text-muted); font-style: italic; }

.resumen-vacio {
  gap: 8px;
  min-height: 72px;
  justify-content: center;
  border: 1px dashed #cbd7e0;
  border-radius: 8px;
  color: var(--text-muted);
  font-size: 12.5px;
}

.resumen-vacio i { color: var(--atendido); font-size: 15px; }
.resumen-editor { padding-top: 20px; }
.resumen-editor-cabecera { justify-content: space-between; gap: 12px; margin-bottom: 12px; }

.resumen-cargando {
  min-height: 280px;
  display: flex;
  flex-direction: column;
  align-items: center;
  justify-content: center;
  gap: 10px;
  color: var(--text-muted);
  font-size: 13px;
}

@media (max-width: 600px) {
  .resumen-cabecera { flex-direction: column; }
  .resumen-estados { justify-content: flex-start; }
  .resumen-seccion-cabecera { gap: 10px; }
}
</style>
