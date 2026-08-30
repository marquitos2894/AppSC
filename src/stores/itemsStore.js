import { defineStore } from 'pinia'
import { supabase } from '@/api/supabaseClient'
import { SIN_GRUPO_COSTO, useFiltroGlobalStore } from '@/stores/filtroGlobalStore'
import { PENDIENTES_ATENCION } from '@/stores/estadosStore'

export const useItemsStore = defineStore('items', {
  state: () => ({
    items: [],
    total: 0,
    loading: false,
    filtroMaterial: '',
    filtroNroParte: '',
    filtroNroSc: '',
    filtroEstado: null,
  }),

  actions: {
    async fetchItems() {
      this.loading = true
      const filtroGlobal = useFiltroGlobalStore()
      let query = supabase.from('vw_items_detalle').select('*', { count: 'exact' })
      if (this.filtroMaterial) query = query.ilike('material', `%${this.filtroMaterial}%`)
      if (this.filtroNroParte) query = query.ilike('nro_parte', `%${this.filtroNroParte}%`)
      if (this.filtroNroSc) {
        const term = this.filtroNroSc.replace(/^sc/i, '')
        query = query.ilike('nro_sc', `%${term}%`)
      }
      if (this.filtroEstado === PENDIENTES_ATENCION) {
        query = query.in('estado_atencion', ['SIN_ATENDER', 'PARCIAL'])
      } else if (this.filtroEstado) {
        query = query.eq('estado', this.filtroEstado)
      }
      if (filtroGlobal.grupoCosto === SIN_GRUPO_COSTO) {
        query = query.is('grupo_costo', null)
      } else if (filtroGlobal.grupoCosto) {
        query = query.eq('grupo_costo', filtroGlobal.grupoCosto)
      }
      const { data, error, count } = await query
        .order('pedido_id', { ascending: false })
        .order('detalle_id', { ascending: false })
      this.loading = false
      if (error) throw error
      this.items = data
      this.total = count
    },

    async limpiarFiltros() {
      this.filtroMaterial = ''
      this.filtroNroParte = ''
      this.filtroNroSc = ''
      this.filtroEstado = null
      await this.fetchItems()
    },

    async editarItem(detalleId, cambios) {
      const { error } = await supabase
        .from('detalle_pedido')
        .update(cambios)
        .eq('detalle_id', detalleId)
      if (error) throw error
      await this.fetchItems()
    },
  },
})
