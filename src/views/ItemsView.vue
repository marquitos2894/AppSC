<template>
  <div v-if="!configurado" class="setup-warning">
    <Message severity="warn" :closable="false">
      <div class="flex flex-column gap-1">
        <strong>Supabase no está configurado.</strong>
        <span>
          Crea un archivo <span class="mono">.env</span> en la raíz con
          <span class="mono">VITE_SUPABASE_URL</span> y
          <span class="mono">VITE_SUPABASE_ANON_KEY</span>, ejecuta
          <span class="mono">supabase/schema.sql</span> en el SQL Editor y reinicia
          <span class="mono">npm run dev</span>.
        </span>
      </div>
    </Message>
  </div>

  <div class="page-header">
    <h1 class="page-title">
      Ítems
      <span v-if="total !== null && !itemsStore.loading" class="mono-count mono">
        {{ total }}
      </span>
    </h1>

    <span class="p-input-icon-left items-filtro">
      <i class="pi pi-search"></i>
      <InputText
        v-model="filtroMaterial"
        placeholder="Material"
        fluid
        @keydown.enter="aplicar"
        @keydown.esc="limpiarCampo('material')"
      />
    </span>

    <span class="p-input-icon-left items-filtro">
      <i class="pi pi-search"></i>
      <InputText
        v-model="filtroNroParte"
        placeholder="Nro parte"
        class="mono"
        fluid
        @keydown.enter="aplicar"
        @keydown.esc="limpiarCampo('nroParte')"
      />
    </span>

    <span class="p-input-icon-left items-filtro">
      <i class="pi pi-search"></i>
      <InputText
        v-model="filtroNroSc"
        placeholder="N° SC"
        class="mono"
        fluid
        @keydown.enter="aplicar"
        @keydown.esc="limpiarCampo('nroSc')"
      />
    </span>

    <Select
      v-model="filtroEstado"
      :options="estados"
      option-label="nombre"
      option-value="nombre"
      placeholder="Estado"
      show-clear
      :loading="cargandoEstados"
      style="min-width: 170px"
      @change="aplicar"
    />

    <Button
      label="Limpiar"
      icon="pi pi-filter-slash"
      text
      severity="secondary"
      :disabled="sinFiltros"
      @click="limpiar"
    />
  </div>

  <div class="page-content">
    <div class="pedidos-card">
      <DataTable
        :value="items"
        :loading="itemsStore.loading"
        data-key="detalle_id"
        :rows="15"
        paginator
        :rows-per-page-options="[15, 30, 60]"
        :always-show-paginator="false"
        :total-records="total"
        table-style="min-width: 900px"
        @sort="() => {}"
      >
        <Column header="N° SC" field="nro_sc" style="width: 100px" sortable>
          <template #body="{ data }">
            <span class="cell-id">SC{{ data.nro_sc }}</span>
          </template>
        </Column>
        <Column header="Nro parte" field="nro_parte" style="width: 150px" sortable>
          <template #body="{ data }">
            <span class="mono cell-num" style="font-size: 12.5px">{{ data.nro_parte || '—' }}</span>
          </template>
        </Column>
        <Column header="Material" field="material" style="min-width: 220px" sortable>
          <template #body="{ data }">
            <span style="font-size: 12.5px">{{ data.material || '—' }}</span>
          </template>
        </Column>
        <Column header="Equipo" field="equipo" style="min-width: 120px" sortable>
          <template #body="{ data }">
            <span style="font-size: 12.5px">{{ data.equipo || '—' }}</span>
          </template>
        </Column>
        <Column header="Solic." field="cantidad_solicitada" style="width: 80px" sortable>
          <template #body="{ data }">
            <span class="cell-num">{{ formatQty(data.cantidad_solicitada) }}</span>
          </template>
        </Column>
        <Column header="Aprob." field="cantidad_aprobada" style="width: 80px" sortable>
          <template #body="{ data }">
            <span class="cell-num">{{ formatQty(data.cantidad_aprobada) }}</span>
          </template>
        </Column>
        <Column header="Atend." field="cantidad_atendida" style="width: 80px" sortable>
          <template #body="{ data }">
            <span class="cell-num">{{ formatQty(data.cantidad_atendida) }}</span>
          </template>
        </Column>
        <Column header="Estado" field="estado" style="width: 150px" sortable>
          <template #body="{ data }">
            <EstadoTag :nombre="data.estado" size="sm" />
          </template>
        </Column>
        <Column header="Pend." field="Acciones" style="width: 80px" sortable>
          <template #body="{ data }">
            <Button
                    icon="pi pi-history"
                    text
                    rounded
                    size="small"
                    aria-label="Movimientos"
                    v-tooltip.top="'Movimientos'"
                    @click="abrirMovimientos(data)"/>
              </template>
        </Column>

      </DataTable>
    </div>
  </div>
  <ItemMovimientosDialog v-model:visible="dialogMovimientos" :item="itemSeleccionado" />
</template>

<script setup>
import { ref, computed, onMounted } from 'vue'
import { storeToRefs } from 'pinia'
import { isConfigured } from '@/api/supabaseClient'
import { useItemsStore } from '@/stores/itemsStore'
import { useEstadosStore } from '@/stores/estadosStore'
import { useToast } from 'primevue/usetoast'
import { formatQty } from '@/utils/format'

const itemsStore = useItemsStore()
const estadosStore = useEstadosStore()
const toast = useToast()

const { items, total, loading } = storeToRefs(itemsStore)
const { estados, loading: cargandoEstados } = storeToRefs(estadosStore)
const configurado = isConfigured

const filtroMaterial = ref('')
const filtroNroParte = ref('')
const filtroNroSc = ref('')
const filtroEstado = ref(null)
const dialogMovimientos = ref(false)
const itemSeleccionado = ref(null)

const sinFiltros = computed(() =>
  !filtroMaterial.value && !filtroNroParte.value && !filtroNroSc.value && !filtroEstado.value,
)

onMounted(async () => {
  if (!configurado) return
  try {
    await estadosStore.load()
    await itemsStore.fetchItems()
  } catch (e) {
    notificarError(e)
  }
})

async function aplicar() {
  itemsStore.filtroMaterial = filtroMaterial.value
  itemsStore.filtroNroParte = filtroNroParte.value
  itemsStore.filtroNroSc = filtroNroSc.value
  itemsStore.filtroEstado = filtroEstado.value
  try {
    await itemsStore.fetchItems()
  } catch (e) {
    notificarError(e)
  }
}

function limpiarCampo(campo) {
  if (campo === 'material') filtroMaterial.value = ''
  if (campo === 'nroParte') filtroNroParte.value = ''
  if (campo === 'nroSc') filtroNroSc.value = ''
  aplicar()
}

function abrirMovimientos(item) {
  itemSeleccionado.value = item
  dialogMovimientos.value = true
}

async function limpiar() {
  filtroMaterial.value = ''
  filtroNroParte.value = ''
  filtroNroSc.value = ''
  filtroEstado.value = null
  try {
    await itemsStore.limpiarFiltros()
  } catch (e) {
    notificarError(e)
  }
}

function notificarError(e) {
  toast.add({
    severity: 'error',
    summary: 'Error de conexión',
    detail: e?.message || 'No se pudo conectar con Supabase.',
    life: 6000,
  })
}
</script>

<style scoped>
.items-filtro {
  width: 170px;
}
</style>
