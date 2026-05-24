import { StrictMode } from 'react'
import { createRoot } from 'react-dom/client'
import { Auth0Provider } from '@auth0/auth0-react'
import App from './App.tsx'
import './index.css'

const domain = import.meta.env.VITE_AUTH0_DOMAIN
const clientId = import.meta.env.VITE_AUTH0_CLIENT_ID
const audience = import.meta.env.VITE_AUTH0_AUDIENCE

if (!domain || !clientId) {
  console.warn("⚠️ Faltan credenciales de Auth0. Por favor, llena el archivo .env en la carpeta frontend.")
}

createRoot(document.getElementById('root')!).render(
  <StrictMode>
    <Auth0Provider
      domain={domain || "configura-tu-auth0-en-el-env"}
      clientId={clientId || "vacio"}
      authorizationParams={{
        redirect_uri: window.location.origin,
        audience: audience
      }}
    >
      <App />
    </Auth0Provider>
  </StrictMode>,
)
