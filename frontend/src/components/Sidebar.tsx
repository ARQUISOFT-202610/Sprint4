import { LayoutDashboard, PieChart, ShieldAlert, LogOut } from 'lucide-react'
import { useAuth0 } from '@auth0/auth0-react'

export const Sidebar = () => {
  const { logout, user, isAuthenticated } = useAuth0()

  return (
    <div className="w-64 h-full glass flex flex-col p-4 z-10">
      <div className="flex items-center gap-3 mb-10 mt-2">
        <div className="w-8 h-8 rounded-lg bg-gradient-to-tr from-primary to-accent flex items-center justify-center font-bold text-white">
          A
        </div>
        <h1 className="text-xl font-bold bg-clip-text text-transparent bg-gradient-to-r from-primary to-accent">
          AQSF FinOps
        </h1>
      </div>

      <nav className="flex-1 space-y-2">
        <button className="w-full flex items-center gap-3 px-4 py-3 bg-primary/20 text-primary rounded-xl font-medium transition-all">
          <LayoutDashboard size={20} /> Dashboard
        </button>
        <button className="w-full flex items-center gap-3 px-4 py-3 text-slate-400 hover:bg-slate-800/50 hover:text-slate-200 rounded-xl font-medium transition-all">
          <PieChart size={20} /> FinOps
        </button>
        <button className="w-full flex items-center gap-3 px-4 py-3 text-slate-400 hover:bg-slate-800/50 hover:text-slate-200 rounded-xl font-medium transition-all">
          <ShieldAlert size={20} /> Auditoría
        </button>
      </nav>

      <div className="mt-auto border-t border-slate-700/50 pt-4 flex items-center justify-between">
        <div className="flex items-center gap-3 overflow-hidden">
          {isAuthenticated ? (
            <img src={user?.picture} alt="Avatar" className="w-10 h-10 rounded-full border border-slate-600" />
          ) : (
            <div className="w-10 h-10 rounded-full bg-slate-700" />
          )}
          <div className="flex flex-col overflow-hidden">
            <span className="text-sm font-semibold truncate text-slate-200">{user?.name || "Ingeniero"}</span>
            <span className="text-xs text-slate-400 truncate">{user?.email || "admin@aqsf.com"}</span>
          </div>
        </div>
        <button onClick={() => logout()} className="text-slate-400 hover:text-red-400 transition-colors">
          <LogOut size={20} />
        </button>
      </div>
    </div>
  )
}
