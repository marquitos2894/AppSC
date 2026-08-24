<script setup>
import { ref, computed } from 'vue'
import { storeToRefs } from 'pinia'
import { usePedidosStore } from '@/stores/pedidosStore'
import { useEstadosStore } from '@/stores/estadosStore'
import { useToast } from 'primevue/usetoast'

const props = defineProps({
  visible: { type: Boolean, default: false },
})
const emit = defineEmits(['update:visible', 'creado'])

const pedidosStore = usePedidosStore()
const estadosStore = useEstadosStore()
const toast = useToast()

const { pedidoStates } = storeToRefs(estadosStore)

const saving = ref(false)
const fechaEmision = ref(new Date())
const motivo = ref('')
const grupoCosto = ref('')
const nroSc = ref('')
const estadoId = ref(null)
const items = ref([])

const gruposSugeridos = ['Unidad Corona Mantenimiento', 'Unidad Corona Operaciones']

const estadoOptions = computed(() =>
  pedidoStates.value.map((e) => ({ label: e.nombre, value: e.estado_id })),
)

const estadoInicial = computed({
  get: () => estadoId.value,
  set: (v) => (estadoId.value = v),
})

function abrir() {
  fechaEmision.value = new Date()
  motivo.value = ''
  grupoCosto.value = ''
  nroSc.value = ''
  const emision = estadosStore.byName('Registrado')
  estadoId.value = emision?.estado_id ?? null
  items.value = [nuevoItem()]
}

function nuevoItem() {
  return { nro_parte: '', material: '', equipo: '', cantidad_solicitada: 0 }
}

function agregarItem() {
  items.value.push(nuevoItem())
}

function quitarItem(indice) {
  items.value.splice(indice, 1)
  if (!items.value.length) items.value.push(nuevoItem())
}

function itemsValidos() {
  return items.value.filter((i) => Number(i.cantidad_solicitada) > 0)
}

function puedeGuardar() {
  return Boolean(estadoId.value) && itemsValidos().length > 0
}

async function guardar() {
  if (!puedeGuardar()) {
    toast.add({
      severity: 'warn',
      summary: 'Faltan datos',
      detail: 'Indica un motivo o al menos un ítem con cantidad solicitada.',
      life: 4000,
    })
    return
  }
  saving.value = true
  try {
    const f = fechaEmision.value
    const fechaISO = `${f.getFullYear()}-${String(f.getMonth() + 1).padStart(2, '0')}-${String(f.getDate()).padStart(2, '0')}`
    const pedido = await pedidosStore.crearPedido({
      motivo: motivo.value || null,
      grupo_costo: grupoCosto.value || null,
      nro_sc: nroSc.value || null,
      fecha_emision: fechaISO,
      estadoId: estadoId.value,
      items: itemsValidos(),
    })
    toast.add({
      severity: 'success',
      summary: 'Pedido creado',
      detail: `Pedido #${pedido.pedido_id} registrado con ${itemsValidos().length} ítem(s).`,
      life: 4000,
    })
    emit('update:visible', false)
    emit('creado', pedido.pedido_id)
  } catch (e) {
    toast.add({ severity: 'error', summary: 'Error', detail: e.message, life: 6000 })
  } finally {
    saving.value = false
  }
}
</script>

<template>
  <Dialog
    :visible="visible"
    modal
    header="Nueva solicitud de pedido"
    :style="{ width: '720px' }"
    :closable="!saving"
    @update:visible="emit('update:visible', $event)"
    @show="abrir"
  >
    <div class="flex flex-column gap-4">
      <div class="grid" style="grid-template-columns: 1fr 1fr; gap: 14px">
        <div class="flex flex-column gap-2">
          <label class="field-label">N° SC (ERP)</label>
          <InputText v-model="nroSc" placeholder="Ej. SC-2026-0001" class="mono" fluid />
        </div>
        <div class="flex flex-column gap-2">
          <label class="field-label">Fecha de emisión</label>
          <DatePicker v-model="fechaEmision" date-format="dd/mm/yy" show-icon />
        </div>
      </div>

      <div class="grid" style="grid-template-columns: 1fr 1fr; gap: 14px">
        <div class="flex flex-column gap-2">
          <label class="field-label">Grupo de costo</label>
          <Select
            v-model="grupoCosto"
            :options="gruposSugeridos"
            editable
            placeholder="Ej. Unidad Corona Mantenimiento"
            fluid
          />
        </div>
        <div class="flex flex-column gap-2">
          <label class="field-label">Estado inicial</label>
          <Select
            v-model="estadoInicial"
            :options="estadoOptions"
            option-label="label"
            option-value="value"
            placeholder="Seleccionar estado"
            fluid
          />
        </div>
      </div>

      <div class="flex flex-column gap-2">
        <label class="field-label">Motivo de la solicitud</label>
        <Textarea
          v-model="motivo"
          rows="2"
          auto-resize
          placeholder="Ej. PU1861 daño a driver de la perforadora JU-11"
        />
      </div>

      <div class="flex flex-column gap-2">
        <div class="flex align-items-center justify-content-between">
          <label class="field-label" style="margin: 0">Ítems del pedido</label>
          <Button label="Agregar ítem" icon="pi pi-plus" size="small" text @click="agregarItem" />
        </div>

        <div class="items-editor">
          <div class="items-editor-head">
            <span>Nro parte</span>
            <span>Material / componente</span>
            <span>Equipo</span>
            <span style="width: 110px">Cantidad</span>
            <span style="width: 34px"></span>
          </div>
          <div v-for="(item, i) in items" :key="i" class="items-editor-row">
            <InputText v-model="item.nro_parte" placeholder="REP06019" class="mono" />
            <InputText v-model="item.material" placeholder="Descripción del repuesto" />
            <InputText v-model="item.equipo" placeholder="Ej. JU-11" />
            <InputNumber
              v-model="item.cantidad_solicitada"
              mode="decimal"
              :min="0"
              :max-fraction-digits="2"
              style="width: 110px"
            />
            <Button
              icon="pi pi-trash"
              size="small"
              text
              severity="danger"
              aria-label="Quitar ítem"
              @click="quitarItem(i)"
            />
          </div>
        </div>
      </div>
    </div>

    <template #footer>
      <Button label="Cancelar" text severity="secondary" :disabled="saving" @click="emit('update:visible', false)" />
      <Button label="Crear pedido" icon="pi pi-check" :loading="saving" :disabled="!puedeGuardar()" @click="guardar" />
    </template>
  </Dialog>
</template>

<style scoped>
.field-label {
  font-size: 11px;
  font-weight: 700;
  text-transform: uppercase;
  letter-spacing: 0.08em;
  color: var(--text-muted);
}

.items-editor {
  border: 1px solid var(--line);
  border-radius: 10px;
  overflow: hidden;
}

.items-editor-head,
.items-editor-row {
  display: grid;
  grid-template-columns: 130px 1fr 120px 110px 34px;
  gap: 8px;
  align-items: center;
  padding: 8px 10px;
}

.items-editor-head {
  background: #fbfcfd;
  font-size: 10.5px;
  font-weight: 700;
  text-transform: uppercase;
  letter-spacing: 0.07em;
  color: #5b6b7d;
  border-bottom: 1px solid var(--line);
}

.items-editor-row {
  border-bottom: 1px solid #edf1f5;
}

.items-editor-row:last-child {
  border-bottom: 0;
}
</style>
