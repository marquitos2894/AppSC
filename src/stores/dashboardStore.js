import { defineStore } from 'pinia'
import { supabase } from '@/api/supabaseClient'
import { SIN_GRUPO_COSTO, useFiltroGlobalStore } from '@/stores/filtroGlobalStore'
import { toISODate } from '@/utils/format'

export const useDashboardStore = defineStore('dashboard', {
  state: () => ({
    loading: false,
    kpis: null,
    porEstado: [],
    porCosto: [],
    itemsPendientes: [],
    desde: null,
    hasta: null,
  }),

  actions: {
    async cargar({ desde, hasta } = {}) {
      this.loading = true
      this.desde = desde ?? null
      this.hasta = hasta ?? null
      const desdeISO = toISODate(desde)
      const hastaISO = toISODate(hasta)
      const filtroGlobal = useFiltroGlobalStore()
      const grupoCosto = filtroGlobal.grupoCosto

      try {
        const [k, e, c, it] = await Promise.all([
          supabase.rpc('dashboard_kpis', {
            p_desde: desdeISO,
            p_hasta: hastaISO,
            p_grupo_costo: grupoCosto,
          }),
          supabase.rpc('dashboard_pedidos_por_estado', {
            p_desde: desdeISO,
            p_hasta: hastaISO,
            p_grupo_costo: grupoCosto,
          }),
          supabase.rpc('dashboard_pedidos_por_costo', {
            p_desde: desdeISO,
            p_hasta: hastaISO,
            p_grupo_costo: grupoCosto,
          }),
          this.cargarItemsPendientes(grupoCosto),
        ])

        if (k.error) throw k.error
        if (e.error) throw e.error
        if (c.error) throw c.error
        if (it.error) throw it.error

        this.kpis = k.data?.[0] ?? null
        this.porEstado = e.data ?? []
        this.porCosto = c.data ?? []
        this.itemsPendientes = it.data ?? []
      } finally {
        this.loading = false
      }
    },

    async cargarItemsPendientes(grupoCosto) {
      let query = supabase.from('vw_items_pendientes').select('*').limit(10)
      if (grupoCosto === SIN_GRUPO_COSTO) {
        query = query.is('grupo_costo', null)
      } else if (grupoCosto) {
        query = query.eq('grupo_costo', grupoCosto)
      }
      return query
    },
  },
})
