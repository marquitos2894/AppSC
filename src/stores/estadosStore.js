import { defineStore } from 'pinia'
import { supabase } from '@/api/supabaseClient'

export const ESTADO_COLORS = {
  'Registrado': '#8A97A8',
  'Confirmado': '#6E8198',
  'En análisis': '#3B6E8F',
  'Aprobado': '#2E8B74',
  'En cotización': '#5F7590',
  'Autorizado': '#4A627E',
  'En compra': '#35495F',
  'Atendido': '#3F9142',
  'Observado': '#E8A33D',
  'Rechazado': '#D64545',
}

export function estadoColor(nombre) {
  return ESTADO_COLORS[nombre] || '#3B6E8F'
}

export const useEstadosStore = defineStore('estados', {
  state: () => ({
    estados: [],
    loading: false,
    loaded: false,
  }),

  getters: {
    flow: (s) =>
      s.estados
        .filter((e) => !e.es_excepcion)
        .sort((a, b) => (a.orden ?? 99) - (b.orden ?? 99)),
    excepciones: (s) => s.estados.filter((e) => e.es_excepcion),
    byName: (s) => (nombre) => s.estados.find((e) => e.nombre === nombre),
    byId: (s) => (id) => s.estados.find((e) => e.estado_id === id),
    pedidoStates: (s) => s.estados.filter((e) => e.ambito === 'pedido'),
    detalleStates: (s) => s.estados.filter((e) => e.ambito === 'detalle'),
  },

  actions: {
    async load() {
      if (this.loaded || this.loading) return
      this.loading = true
      const { data, error } = await supabase
        .from('estados_catalogo')
        .select('*')
        .eq('active', true)
        .order('orden', { ascending: true, nullsFirst: false })
      this.loading = false
      if (error) throw error
      this.estados = data
      this.loaded = true
    },
  },
})
