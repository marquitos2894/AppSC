import { createApp } from 'vue'
import { createPinia } from 'pinia'
import PrimeVue from 'primevue/config'
import Aura from '@primeuix/themes/aura'
import { definePreset } from '@primeuix/themes'
import ToastService from 'primevue/toastservice'
import ConfirmationService from 'primevue/confirmationservice'
import 'primeicons/primeicons.css'
import App from './App.vue'
import router from './router'
import { useAuthStore } from './stores/authStore'
import './styles/main.css'

const AppPreset = definePreset(Aura, {
  semantic: {
    primary: {
      50: '#F0F5F8',
      100: '#DCE8EF',
      200: '#BBD2E0',
      300: '#92B6CB',
      400: '#6696B3',
      500: '#3B6E8F',
      600: '#2F5A77',
      700: '#274B64',
      800: '#223E53',
      900: '#1E2A38',
      950: '#131C26',
    },
    warn: { 500: '#E8A33D' },
    danger: { 500: '#D64545' },
    success: { 500: '#3F9142' },
  },
})

const app = createApp(App)

app.use(createPinia())
app.use(PrimeVue, {
  theme: { preset: AppPreset },
  ripple: true,
})
app.use(ToastService)
app.use(ConfirmationService)

const auth = useAuthStore()
await auth.init()

app.use(router)
app.mount('#app')
