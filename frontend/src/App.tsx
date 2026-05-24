import { useState } from 'react'
import { useAuth0 } from '@auth0/auth0-react'
import { Sidebar } from './components/Sidebar'
import { FinOpsDashboard } from './components/FinOpsDashboard'

function App() {
  const { isAuthenticated, loginWithRedirect, isLoading } = useAuth0()
  const [devMode, setDevMode] = useState(false)

  if (isLoading && !devMode) {
    return (
      <div className="flex h-screen w-screen items-center justify-center bg-background">
        <div className="w-12 h-12 border-4 border-primary border-t-transparent rounded-full animate-spin"></div>
      </div>
    )
  }

  if (!isAuthenticated && !devMode) {
    return (
      <div className="flex h-screen w-screen items-center justify-center bg-background bg-[radial-gradient(ellipse_at_top_right,_var(--tw-gradient-stops))] from-slate-800 via-background to-background">
        <div className="glass p-10 rounded-3xl max-w-md w-full text-center">
          <div className="w-16 h-16 rounded-2xl bg-gradient-to-tr from-primary to-accent flex items-center justify-center font-bold text-white text-3xl mx-auto mb-6">
            A
          </div>
          <h1 className="text-3xl font-bold text-white mb-2">AQSF FinOps</h1>
          <p className="text-slate-400 mb-8">Plataforma corporativa de análisis y optimización de costos cloud.</p>
          <button 
            onClick={() => loginWithRedirect()}
            className="w-full py-3 px-4 mb-3 bg-primary hover:bg-blue-600 text-white rounded-xl font-bold transition-colors shadow-lg shadow-primary/30"
          >
            Iniciar Sesión con Auth0
          </button>
          <button 
            onClick={() => setDevMode(true)}
            className="w-full py-3 px-4 bg-slate-700/50 hover:bg-slate-600 text-slate-300 rounded-xl font-bold transition-colors border border-slate-600"
          >
            Entrar sin Login (Ver Dashboard)
          </button>
        </div>
      </div>
    )
  }

  return (
    <div className="flex h-screen w-screen bg-background bg-[radial-gradient(ellipse_at_top_right,_var(--tw-gradient-stops))] from-slate-800/50 via-background to-background overflow-hidden">
      <Sidebar />
      <FinOpsDashboard />
    </div>
  )
}

export default App
