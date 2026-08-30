import { defineStore } from 'pinia'
import { supabase } from '@/api/supabaseClient'

export const SIN_GRUPO_COSTO = '__appsc_sin_grupo_costo__'

export const useFiltroGlobalStore = defineStore('filtroGlobal', {
  state: () => ({
    grupoCosto: null,
    gruposCosto: [],
    loading: false,
  }),

  actions: {
    async cargarGruposCosto() {
      this.loading = true
      try {
        const { data, error } = await supabase
          .from('pedido')
          .select('grupo_costo')
          .eq('active', true)

        if (error) throw error

        const valores = new Set((data ?? []).map((pedido) => pedido.grupo_costo))
        const grupos = [...valores]
          .filter((grupo) => grupo !== null)
          .sort((a, b) => a.localeCompare(b, 'es'))
          .map((grupo) => ({ label: grupo, value: grupo }))

        if (valores.has(null)) {
          grupos.unshift({ label: 'Sin grupo de costo', value: SIN_GRUPO_COSTO })
        }

        this.gruposCosto = grupos
      } finally {
        this.loading = false
      }
    },

    limpiar() {
      this.grupoCosto = null
      this.gruposCosto = []
    },
  },
})
