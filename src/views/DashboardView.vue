<script setup>
import { ref, computed, onMounted, watch } from 'vue'
import { storeToRefs } from 'pinia'
import Chart from 'primevue/chart'
import {
  ArcElement,
  BarElement,
  CategoryScale,
  Chart as ChartJS,
  Legend,
  LinearScale,
  Tooltip,
} from 'chart.js'
import { useDashboardStore } from '@/stores/dashboardStore'
import { useFiltroGlobalStore } from '@/stores/filtroGlobalStore'
import { estadoColor } from '@/stores/estadosStore'
import { formatQty } from '@/utils/format'

ChartJS.register(CategoryScale, LinearScale, BarElement, ArcElement, Tooltip, Legend)

const dashboardStore = useDashboardStore()
const filtroGlobalStore = useFiltroGlobalStore()
const { kpis, porEstado, porCosto, itemsPendientes, loading } = storeToRefs(dashboardStore)

const fechaDesde = ref(null)
const fechaHasta = ref(null)

const atencionPct = computed(() => {
  const aprobada = Number(kpis.value?.total_aprobada ?? 0)
  const atendida = Number(kpis.value?.total_atendida ?? 0)
  return aprobada > 0 ? Math.round((atendida / aprobada) * 100) : 0
})

const pieData = computed(() => ({
  labels: porEstado.value.map((e) => e.estado),
  datasets: [
    {
      data: porEstado.value.map((e) => Number(e.total)),
      backgroundColor: porEstado.value.map((e) => estadoColor(e.estado)),
      borderWidth: 0,
    },
  ],
}))

const barData = computed(() => ({
  labels: porCosto.value.map((e) => e.grupo_costo),
  datasets: [
    {
      label: 'Pedidos',
      data: porCosto.value.map((e) => Number(e.total)),
      backgroundColor: '#3b6e8f',
      borderRadius: 6,
      maxBarThickness: 42,
    },
  ],
}))

const pieOptions = { responsive: true, maintainAspectRatio: false, plugins: { legend: { position: 'bottom' } } }
const barOptions = { responsive: true, maintainAspectRatio: false, plugins: { legend: { display: false } } }

function cargar() {
  dashboardStore.cargar({ desde: fechaDesde.value, hasta: fechaHasta.value }).catch(() => {})
}

function limpiar() {
  fechaDesde.value = null
  fechaHasta.value = null
  dashboardStore.cargar({}).catch(() => {})
}

const kpiCards = computed(() => [
  { label: 'Pedidos totales', value: kpis.value?.total_pedidos ?? 0, tone: 'default' },
  { label: 'Pendientes', value: kpis.value?.pedidos_pendientes ?? 0, tone: 'pendiente' },
  { label: 'Parciales', value: kpis.value?.pedidos_parciales ?? 0, tone: 'parcial' },
  { label: 'Completos', value: kpis.value?.pedidos_completos ?? 0, tone: 'completo' },
  { label: 'Atención', value: `${atencionPct.value}%`, tone: 'atencion' },
  { label: 'Ítems en excepción', value: kpis.value?.items_excepcion ?? 0, tone: 'excepcion' },
])

onMounted(cargar)

watch(
  () => filtroGlobalStore.grupoCosto,
  cargar,
)
</script>

<template>
  <div class="page-header">
    <h1 class="page-title">Dashboard</h1>

    <div class="flex align-items-center gap-2">
      <DatePicker v-model="fechaDesde" date-format="dd/mm/yy" show-icon placeholder="Desde" style="width: 140px" />
      <DatePicker v-model="fechaHasta" date-format="dd/mm/yy" show-icon placeholder="Hasta" style="width: 140px" />
      <Button label="Aplicar" icon="pi pi-filter" size="small" @click="cargar" />
      <Button label="Limpiar" icon="pi pi-filter-slash" text size="small" severity="secondary" @click="limpiar" />
    </div>
  </div>

  <div class="page-content">
    <div v-if="loading && !kpis" class="flex flex-column gap-3">
      <div class="kpi-grid">
        <Skeleton v-for="n in 6" :key="n" height="84px" />
      </div>
      <Skeleton height="300px" />
    </div>

    <template v-else>
      <div class="kpi-grid">
        <div v-for="card in kpiCards" :key="card.label" class="kpi-card" :class="`kpi-${card.tone}`">
          <span class="kpi-value">{{ card.value }}</span>
          <span class="kpi-label">{{ card.label }}</span>
        </div>
      </div>

      <div class="charts-grid">
        <div class="chart-card">
          <h3 class="chart-title">Pedidos por estado</h3>
          <div class="chart-wrap">
            <Chart type="pie" :data="pieData" :options="pieOptions" />
          </div>
        </div>
        <div class="chart-card">
          <h3 class="chart-title">Pedidos por grupo de costo</h3>
          <div class="chart-wrap">
            <Chart type="bar" :data="barData" :options="barOptions" />
          </div>
        </div>
      </div>

      <div class="chart-card">
        <h3 class="chart-title">Ítems con mayor cantidad pendiente</h3>
        <DataTable :value="itemsPendientes" data-key="detalle_id" table-style="min-width: 720px">
          <Column header="SC" style="width: 90px">
            <template #body="{ data }">
              <span class="cell-id">SC{{ data.nro_sc }}</span>
            </template>
          </Column>
          <Column header="Nro parte" style="width: 140px">
            <template #body="{ data }">
              <span class="mono cell-num" style="font-size: 12.5px">{{ data.nro_parte || '—' }}</span>
            </template>
          </Column>
          <Column header="Material" style="min-width: 200px">
            <template #body="{ data }">
              <span style="font-size: 12.5px">{{ data.material || '—' }}</span>
            </template>
          </Column>
          <Column header="Equipo" style="width: 120px">
            <template #body="{ data }">
              <span style="font-size: 12.5px">{{ data.equipo || '—' }}</span>
            </template>
          </Column>
          <Column header="Aprobada" style="width: 90px">
            <template #body="{ data }">
              <span class="cell-num">{{ formatQty(data.cantidad_aprobada) }}</span>
            </template>
          </Column>
          <Column header="Atendida" style="width: 90px">
            <template #body="{ data }">
              <span class="cell-num">{{ formatQty(data.cantidad_atendida) }}</span>
            </template>
          </Column>
          <Column header="Pendiente" style="width: 100px">
            <template #body="{ data }">
              <span class="cell-num" style="color: var(--accent-500); font-weight: 600">{{ formatQty(data.cantidad_pendiente) }}</span>
            </template>
          </Column>
        </DataTable>
      </div>
    </template>
  </div>
</template>

<style scoped>
.kpi-grid {
  display: grid;
  grid-template-columns: repeat(auto-fit, minmax(170px, 1fr));
  gap: 14px;
  margin-bottom: 18px;
}

.kpi-card {
  background: var(--surface);
  border: 1px solid var(--line);
  border-radius: 12px;
  padding: 16px;
  display: flex;
  flex-direction: column;
  gap: 4px;
  box-shadow: var(--shadow-card);
}

.kpi-value {
  font-size: 24px;
  font-weight: 700;
  color: var(--text-strong);
  font-variant-numeric: tabular-nums;
}

.kpi-label {
  font-size: 11px;
  font-weight: 600;
  text-transform: uppercase;
  letter-spacing: 0.06em;
  color: var(--text-muted);
}

.kpi-pendiente .kpi-value { color: #8b9cad; }
.kpi-parcial .kpi-value { color: #b07a1f; }
.kpi-completo .kpi-value { color: var(--atendido); }
.kpi-atencion .kpi-value { color: var(--accent-500); }
.kpi-excepcion .kpi-value { color: var(--rej); }

.charts-grid {
  display: grid;
  grid-template-columns: 1fr 1fr;
  gap: 14px;
  margin-bottom: 18px;
}

.chart-card {
  background: var(--surface);
  border: 1px solid var(--line);
  border-radius: 12px;
  padding: 16px;
  box-shadow: var(--shadow-card);
}

.chart-title {
  margin: 0 0 12px;
  font-size: 11px;
  font-weight: 700;
  text-transform: uppercase;
  letter-spacing: 0.08em;
  color: var(--text-muted);
}

.chart-wrap {
  position: relative;
  height: 280px;
}

@media (max-width: 900px) {
  .charts-grid {
    grid-template-columns: 1fr;
  }
}
</style>
