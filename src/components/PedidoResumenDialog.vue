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
})
const emit = defineEmits(['update:visible'])

const detalleStore = useDetallePedidoStore()
const toast = useToast()

const texto = ref('')
const loading = ref(false)
const vistaActual = ref('vista')
const comentariosIncidencias = ref(new Map())
const atencionesPorItem = ref(new Map())

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
    return aprobada > 0 && Number(item.cantidad_atendida ?? 0) >= aprobada
  }),
)

const incidencias = computed(() => props.items.filter(esIncidencia))

function fechaAprox(item) {
  return item.fecha_aprox_atencion ? formatDate(item.fecha_aprox_atencion) : 'Fecha por confirmar'
}

function comentarioIncidencia(item) {
  return comentariosIncidencias.value.get(item.detalle_id) || 'Sin comentario registrado'
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

function construirResumen(comentarios = new Map()) {
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
        `- ${descripcionItem(item)}: solicitada ${formatQty(item.cantidad_solicitada)}. Aprobada ${formatQty(item.cantidad_aprobada)}. Atendida ${formatQty(item.cantidad_atendida)}. Detalle de atención: ${detalle}.`,
      )
    }
  } else {
    lineas.push('- No se registran repuestos atendidos.')
  }

  lineas.push('', 'Repuestos pendientes de atención:')

  if (pendientes.value.length) {
    for (const item of pendientes.value) {
      lineas.push(
        `- ${descripcionItem(item)}: solicitada ${formatQty(item.cantidad_solicitada)}. Aprobada ${formatQty(item.cantidad_aprobada)}. Atendida ${formatQty(item.cantidad_atendida)}. Pendiente ${formatQty(detalleStore.pendiente(item))}. Fecha aproximada de atención: ${fechaAprox(item)}.`,
      )
    }
  } else {
    lineas.push('- No hay repuestos pendientes de atención.')
  }

  lineas.push('', 'Repuestos observados o rechazados:')
  if (incidencias.value.length) {
    for (const item of incidencias.value) {
      const comentario = comentarios.get(item.detalle_id) || 'Sin comentario registrado'
      lineas.push(
        `- ${descripcionItem(item)}: solicitada ${formatQty(item.cantidad_solicitada)}. Aprobada ${formatQty(item.cantidad_aprobada)}. ${item.estados_catalogo?.nombre}. Motivo: ${comentario}.`,
      )
    }
  } else {
    lineas.push('- No se registran repuestos observados o rechazados.')
  }

  return lineas.join('\n')
}

async function generarResumen() {
  if (!props.pedido) return
  loading.value = true
  texto.value = ''
  comentariosIncidencias.value = new Map()
  atencionesPorItem.value = new Map()
  try {
    const [historialResult, atencionesResult] = await Promise.allSettled([
      detalleStore.fetchComentariosIncidencias(incidencias.value.map((item) => item.detalle_id)),
      detalleStore.fetchIngresosItems(atendidos.value.map((item) => item.detalle_id)),
    ])
    const historial = historialResult.status === 'fulfilled' ? historialResult.value : []
    const atenciones = atencionesResult.status === 'fulfilled' ? atencionesResult.value : {}
    const comentarios = new Map()

    for (const item of incidencias.value) {
      const movimiento = historial.find(
        (registro) =>
          registro.detalle_id === item.detalle_id && registro.estado_id === item.estado_actual_id,
      )
      if (movimiento?.comentario?.trim()) comentarios.set(item.detalle_id, movimiento.comentario.trim())
    }
    comentariosIncidencias.value = comentarios
    atencionesPorItem.value = new Map(Object.entries(atenciones).map(([id, values]) => [Number(id), values]))
    texto.value = construirResumen(comentarios)
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

watch(
  () => props.visible,
  (visible) => {
    if (visible) {
      vistaActual.value = 'vista'
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
    :style="{ width: 'min(850px, calc(100vw - 2rem))' }"
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
          <section class="resumen-seccion" aria-labelledby="atendidos-titulo">
            <div class="resumen-seccion-cabecera">
              <div>
                <h3 id="atendidos-titulo"><i class="pi pi-check-circle resumen-icono-atendido" aria-hidden="true"></i> Repuestos atendidos</h3>
                <p>Ítems cuya cantidad aprobada ya fue cubierta por completo.</p>
              </div>
              <span class="resumen-contador resumen-contador--atendido">{{ atendidos.length }}</span>
            </div>

            <DataTable
              v-if="atendidos.length"
              :value="atendidos"
              class="resumen-tabla"
              table-style="min-width: 930px"
            >
              <Column header="Repuesto">
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
              <Column header="Solic." style="width: 88px">
                <template #body="{ data }"><span class="resumen-cantidad">{{ formatQty(data.cantidad_solicitada) }}</span></template>
              </Column>
              <Column header="Aprob." header-class="columna-aprobada" style="width: 88px">
                <template #body="{ data }"><span class="resumen-cantidad resumen-cantidad--aprobada">{{ formatQty(data.cantidad_aprobada) }}</span></template>
              </Column>
              <Column header="Atend." header-class="columna-atendida" style="width: 88px">
                <template #body="{ data }"><span class="resumen-cantidad resumen-cantidad--atendida">{{ formatQty(data.cantidad_atendida) }}</span></template>
              </Column>
              <Column header="Detalle de atención" style="min-width: 250px">
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
            <div v-else class="resumen-vacio">
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
              <span class="resumen-contador">{{ pendientes.length }}</span>
            </div>

            <DataTable
              v-if="pendientes.length"
              :value="pendientes"
              class="resumen-tabla"
              table-style="min-width: 750px"
            >
              <Column header="Repuesto">
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
              <Column header="Solic." style="width: 88px">
                <template #body="{ data }">
                  <span class="resumen-cantidad">{{ formatQty(data.cantidad_solicitada) }}</span>
                </template>
              </Column>
              <Column header="Aprob." header-class="columna-aprobada" style="width: 88px">
                <template #body="{ data }"><span class="resumen-cantidad resumen-cantidad--aprobada">{{ formatQty(data.cantidad_aprobada) }}</span></template>
              </Column>
              <Column header="Atend." header-class="columna-atendida" style="width: 88px">
                <template #body="{ data }"><span class="resumen-cantidad resumen-cantidad--atendida">{{ formatQty(data.cantidad_atendida) }}</span></template>
              </Column>
              <Column header="Fecha aprox" style="width: 190px">
                <template #body="{ data }">
                  <span class="resumen-fecha" :class="{ pendiente: !data.fecha_aprox_atencion }">
                    <i class="pi pi-calendar" aria-hidden="true"></i>{{ fechaAprox(data) }}
                  </span>
                </template>
              </Column>
            </DataTable>
            <div v-else class="resumen-vacio">
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
              <span class="resumen-contador resumen-contador--incidencia">{{ incidencias.length }}</span>
            </div>

            <DataTable
              v-if="incidencias.length"
              :value="incidencias"
              class="resumen-tabla"
              table-style="min-width: 780px"
            >
              <Column header="Repuesto" style="width: 235px">
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
              <Column header="Solic." style="width: 88px">
                <template #body="{ data }"><span class="resumen-cantidad">{{ formatQty(data.cantidad_solicitada) }}</span></template>
              </Column>
              <Column header="Aprob." header-class="columna-aprobada" style="width: 88px">
                <template #body="{ data }"><span class="resumen-cantidad resumen-cantidad--aprobada">{{ formatQty(data.cantidad_aprobada) }}</span></template>
              </Column>
              <Column header="Estado" style="width: 125px">
                <template #body="{ data }"><EstadoTag :nombre="data.estados_catalogo?.nombre" size="sm" /></template>
              </Column>
              <Column header="Motivo">
                <template #body="{ data }"><span class="resumen-motivo">{{ comentarioIncidencia(data) }}</span></template>
              </Column>
            </DataTable>
            <div v-else class="resumen-vacio">
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
      <Button label="Copiar resumen" icon="pi pi-copy" :disabled="loading || !texto" @click="copiarResumen" />
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

.resumen-fecha { gap: 6px; color: var(--text); font-size: 12.5px; white-space: nowrap; }
.resumen-fecha i { color: var(--accent-500); font-size: 12px; }
.resumen-fecha.pendiente { color: var(--text-muted); font-style: italic; }

.resumen-motivo { display: block; max-width: 290px; color: var(--text); font-size: 12.5px; line-height: 1.4; white-space: normal; }

.atencion-detalle-cell { display: flex; flex-direction: column; gap: 4px; color: var(--text); font-size: 12px; line-height: 1.35; }
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
