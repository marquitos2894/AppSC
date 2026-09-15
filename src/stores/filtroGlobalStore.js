import { defineStore } from 'pinia'
import { supabase } from '@/api/supabaseClient'

export const SIN_GRUPO_COSTO = '__appsc_sin_grupo_costo__'
const GRUPO_COSTO_STORAGE_KEY = 'appsc.grupo-costo-global'

function leerGrupoCostoGuardado() {
  if (typeof window === 'undefined') return null
  try {
    return window.localStorage.getItem(GRUPO_COSTO_STORAGE_KEY) || null
  } catch {
    return null
  }
}

function guardarGrupoCosto(valor) {
  if (typeof window === 'undefined') return
  try {
    if (valor) window.localStorage.setItem(GRUPO_COSTO_STORAGE_KEY, valor)
    else window.localStorage.removeItem(GRUPO_COSTO_STORAGE_KEY)
  } catch {
    /* El filtro sigue funcionando aunque el navegador bloquee el almacenamiento. */
  }
}

export const useFiltroGlobalStore = defineStore('filtroGlobal', {
  state: () => ({
    grupoCosto: leerGrupoCostoGuardado(),
    gruposCosto: [],
    loading: false,
  }),

  actions: {
    establecerGrupoCosto(grupoCosto) {
      this.grupoCosto = grupoCosto || null
      guardarGrupoCosto(this.grupoCosto)
    },

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
      this.establecerGrupoCosto(null)
      this.gruposCosto = []
    },
  },
})
