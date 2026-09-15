<script setup>
import { computed, ref, watch } from 'vue'
import { useDetallePedidoStore } from '@/stores/detallePedidoStore'
import { useToast } from 'primevue/usetoast'
import { formatQty, toISODate } from '@/utils/format'

const props = defineProps({ visible: Boolean, pedido: { type: Object, default: null }, items: { type: Array, default: () => [] } })
const emit = defineEmits(['update:visible', 'registrado'])
const detalleStore = useDetallePedidoStore()
const toast = useToast()
const fecha = ref(new Date())
const documento = ref('')
const comentario = ref('')
const cantidades = ref({})
const saving = ref(false)
const estadosPermitidos = ['Aprobado', 'En cotización', 'En compra', 'Atendido']
const pendiente = (item) => Math.max(Number(item.cantidad_aprobada ?? 0) - Number(item.cantidad_atendida ?? 0), 0)
const elegibles = computed(() => props.items.filter((item) => estadosPermitidos.includes(item.estados_catalogo?.nombre) && pendiente(item) > 0))
const noElegibles = computed(() => props.items.filter((item) => !elegibles.value.includes(item)))
const ingresos = computed(() => elegibles.value.map((item) => ({ detalle_id: item.detalle_id, cantidad: Number(cantidades.value[item.detalle_id] ?? 0) })).filter((item) => item.cantidad > 0))

watch(() => props.visible, (abierto) => {
  if (abierto) {
    fecha.value = new Date(); documento.value = ''; comentario.value = ''
    cantidades.value = Object.fromEntries(elegibles.value.map((item) => [item.detalle_id, pendiente(item)]))
  }
})

async function guardar() {
  if (!props.pedido || !ingresos.value.length) return
  const excedido = elegibles.value.find((item) => Number(cantidades.value[item.detalle_id] ?? 0) > pendiente(item))
  if (excedido) {
    toast.add({ severity: 'warn', summary: 'Cantidad no válida', detail: `La entrega de ${excedido.nro_parte || excedido.material} supera su saldo pendiente.`, life: 5000 })
    return
  }
  saving.value = true
  try {
    await detalleStore.registrarIngresosItems({ pedidoId: props.pedido.pedido_id, ingresos: ingresos.value, fecha: toISODate(fecha.value), documento: documento.value, comentario: comentario.value })
    toast.add({ severity: 'success', summary: 'Entregas registradas', detail: `${ingresos.value.length} entregas registradas correctamente.`, life: 3500 })
    emit('update:visible', false); emit('registrado')
  } catch (error) {
    toast.add({ severity: 'error', summary: 'No se registró ninguna entrega', detail: error.message, life: 6000 })
  } finally { saving.value = false }
}
</script>

<template>
  <Dialog :visible="visible" modal header="Registrar entregas seleccionadas" :style="{ width: 'min(780px, 96vw)' }" :closable="!saving" @update:visible="emit('update:visible', $event)">
    <div class="flex flex-column gap-4">
      <Message severity="info" :closable="false">Se creará una entrega independiente por cada fila con cantidad mayor que cero. Si una validación falla, no se guardará ninguna.</Message>
      <Message v-if="noElegibles.length" severity="warn" :closable="false">{{ noElegibles.length }} ítem{{ noElegibles.length === 1 ? '' : 's' }} no puede{{ noElegibles.length === 1 ? '' : 'n' }} recibir entrega porque no está aprobado o ya no tiene saldo.</Message>
      <div class="cabecera-grid">
        <div class="flex flex-column gap-2"><label class="field-label">Fecha de entrega</label><DatePicker v-model="fecha" date-format="dd/mm/yy" show-icon fluid /></div>
        <div class="flex flex-column gap-2"><label class="field-label">Documento</label><InputText v-model="documento" maxlength="25" class="mono" placeholder="Guía / factura" fluid /></div>
      </div>
      <div class="flex flex-column gap-2"><label class="field-label">Comentario común</label><Textarea v-model="comentario" rows="2" auto-resize placeholder="Observación opcional para todas las entregas" /></div>
      <div class="items-table">
        <div class="fila encabezado"><span>Ítem</span><span>Aprob.</span><span>Pend.</span><span>Entregar</span></div>
        <div v-for="item in elegibles" :key="item.detalle_id" class="fila">
          <span><strong class="mono">{{ item.nro_parte || '—' }}</strong><small>{{ item.material || 'Sin descripción' }}</small></span>
          <span>{{ formatQty(item.cantidad_aprobada) }}</span><span>{{ formatQty(pendiente(item)) }}</span>
          <InputNumber v-model="cantidades[item.detalle_id]" :min="0" :max="pendiente(item)" :max-fraction-digits="2" size="small" fluid />
        </div>
      </div>
    </div>
    <template #footer><Button label="Cancelar" text severity="secondary" :disabled="saving" @click="emit('update:visible', false)" /><Button label="Registrar entregas" icon="pi pi-plus" :loading="saving" :disabled="!ingresos.length" @click="guardar" /></template>
  </Dialog>
</template>

<style scoped>
.cabecera-grid { display:grid; grid-template-columns:1fr 1fr; gap:16px; }.field-label { font-size:11px; font-weight:700; text-transform:uppercase; letter-spacing:.08em; color:var(--text-muted); }.items-table { border:1px solid var(--line); border-radius:8px; overflow:auto; }.fila { display:grid; grid-template-columns:minmax(190px,1fr) 70px 70px 130px; align-items:center; gap:10px; padding:8px 10px; border-bottom:1px solid var(--line); font-size:12px; }.fila:last-child { border-bottom:0; }.fila > span:first-child { display:flex; flex-direction:column; gap:2px; }.fila small { color:var(--text-muted); }.encabezado { background:#f7f9fb; font-size:10px; font-weight:700; text-transform:uppercase; letter-spacing:.07em; color:var(--text-muted); }@media(max-width:580px){.cabecera-grid{grid-template-columns:1fr}.fila{grid-template-columns:1fr 70px 70px 100px;gap:6px;padding:8px}.encabezado{display:none}}
</style>
