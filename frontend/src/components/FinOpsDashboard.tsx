import { useState } from 'react'
import { Play, CheckCircle, Activity, Server, DollarSign, AlertCircle, ShieldAlert, FileText, Search } from 'lucide-react'
import { AreaChart, Area, XAxis, YAxis, CartesianGrid, Tooltip, ResponsiveContainer } from 'recharts'
import axios from 'axios'
import { useAuth0 } from '@auth0/auth0-react'

const data = [
  { name: 'Lun', cost: 400 },
  { name: 'Mar', cost: 300 },
  { name: 'Mie', cost: 500 },
  { name: 'Jue', cost: 200 },
  { name: 'Vie', cost: 600 },
  { name: 'Sab', cost: 450 },
  { name: 'Dom', cost: 400 },
]

export const FinOpsDashboard = () => {
  const [analyzing, setAnalyzing] = useState(false)
  const [analysisDone, setAnalysisDone] = useState(false)
  const [notification, setNotification] = useState<{type: 'success' | 'error' | 'warning', msg: string} | null>(null)
  
  // States for experiments
  const [analisisId, setAnalisisId] = useState('')
  const [reportData, setReportData] = useState<any>(null)
  const [actionLoading, setActionLoading] = useState(false)

  const { getAccessTokenSilently } = useAuth0()

  const getHeaders = async () => {
    try {
      const token = await getAccessTokenSilently();
      return { Authorization: `Bearer ${token}` };
    } catch (e) {
      return {};
    }
  }

  const apiUrl = import.meta.env.VITE_API_URL || 'http://localhost:8000/api'

  const handleAnalysis = async () => {
    setAnalyzing(true)
    setNotification(null)
    
    try {
      const headers = await getHeaders();
      const response = await axios.post(`${apiUrl}/analisis/`, {
        empresa_id: "empresa-123",
        tipo_analisis: "optimizacion-costos"
      }, { headers });

      if (response.status === 202) {
        setAnalysisDone(true)
        setAnalisisId(response.data.analisis_id)
        setNotification({ 
          type: 'success', 
          msg: `¡Análisis encolado en SQS! ID: ${response.data.analisis_id}` 
        })
      }
    } catch (error: any) {
      setNotification({ 
        type: 'error', 
        msg: `Error (ASR-9/ASR-10): ${error.response?.data?.error || error.message}` 
      })
    } finally {
      setAnalyzing(false)
      setTimeout(() => setNotification(null), 8000)
    }
  }

  const handleGetReport = async () => {
    if (!analisisId) return;
    setActionLoading(true);
    try {
      const headers = await getHeaders();
      const response = await axios.get(`${apiUrl}/reportes/${analisisId}/`, { headers });
      setReportData(response.data);
      setNotification({ type: 'success', msg: 'Reporte obtenido exitosamente.' });
    } catch (error: any) {
      setNotification({ type: 'error', msg: `Error obteniendo reporte: ${error.response?.data?.error || error.message}` });
    } finally {
      setActionLoading(false);
      setTimeout(() => setNotification(null), 5000);
    }
  }

  const handleVerifyIntegrity = async () => {
    if (!analisisId) return;
    setActionLoading(true);
    try {
      const headers = await getHeaders();
      const response = await axios.get(`${apiUrl}/reportes/${analisisId}/verify/`, { headers });
      if (response.data.integro) {
        setNotification({ type: 'success', msg: `Integridad verificada (ASR-11). Hash: ${response.data.hash_calculado}` });
      } else {
        setNotification({ type: 'error', msg: `¡ALERTA! El reporte fue alterado. ASR-11 detectó la falla.` });
      }
    } catch (error: any) {
      setNotification({ type: 'error', msg: `Alerta (ASR-11): ${error.response?.data?.error || error.message}` });
    } finally {
      setActionLoading(false);
      setTimeout(() => setNotification(null), 6000);
    }
  }

  const handleSimulateBreach = async () => {
    if (!analisisId) return;
    setActionLoading(true);
    try {
      const headers = await getHeaders();
      await axios.post(`${apiUrl}/test/integrity-breach/${analisisId}/`, {}, { headers });
      setNotification({ type: 'warning', msg: 'Brecha de integridad simulada (hash corrompido).' });
    } catch (error: any) {
      setNotification({ type: 'error', msg: `Error simulando brecha: ${error.message}` });
    } finally {
      setActionLoading(false);
      setTimeout(() => setNotification(null), 5000);
    }
  }

  return (
    <div className="flex-1 p-8 overflow-y-auto relative">
      {notification && (
        <div className={`absolute top-4 right-8 p-4 rounded-xl border flex items-center gap-3 shadow-2xl z-50 animate-bounce ${
          notification.type === 'success' ? 'bg-emerald-500/20 border-emerald-500/50 text-emerald-400' : 
          notification.type === 'warning' ? 'bg-amber-500/20 border-amber-500/50 text-amber-400' :
          'bg-red-500/20 border-red-500/50 text-red-400'
        }`}>
          {notification.type === 'success' ? <CheckCircle size={24} /> : notification.type === 'warning' ? <ShieldAlert size={24} /> : <AlertCircle size={24} />}
          <p className="font-medium text-lg">{notification.msg}</p>
        </div>
      )}
      
      <header className="flex justify-between items-center mb-10">
        <div>
          <h2 className="text-3xl font-bold text-slate-100">Visión General</h2>
          <p className="text-slate-400 mt-1">Monitorea tus costos cloud y optimiza recursos.</p>
        </div>
        <button 
          onClick={handleAnalysis}
          disabled={analyzing}
          className={`flex items-center gap-2 px-6 py-3 rounded-xl font-semibold transition-all ${
            analyzing ? 'bg-slate-700 text-slate-400 cursor-not-allowed' : 
            analysisDone ? 'bg-emerald-500/20 text-emerald-400 border border-emerald-500/50' : 
            'bg-gradient-to-r from-primary to-accent hover:opacity-90 shadow-lg shadow-primary/20 text-white'
          }`}
        >
          {analyzing ? <><Activity className="animate-spin" size={20} /> Ejecutando en background...</> : 
           analysisDone ? <><CheckCircle size={20} /> Análisis Completado</> : 
           <><Play size={20} fill="currentColor" /> Iniciar Análisis Cloud (ASR-9)</>}
        </button>
      </header>

      {/* Experimentos Section */}
      <div className="glass border border-slate-700 rounded-2xl p-6 mb-8">
        <h3 className="text-xl font-bold mb-4 text-slate-200 flex items-center gap-2">
          <Activity size={24} className="text-primary" /> Panel de Pruebas de Arquitectura (ASRs)
        </h3>
        
        <div className="flex gap-4 items-end mb-4">
          <div className="flex-1">
            <label className="block text-sm text-slate-400 mb-2">ID del Análisis (UUID)</label>
            <input 
              type="text" 
              value={analisisId} 
              onChange={(e) => setAnalisisId(e.target.value)}
              placeholder="Ej: 123e4567-e89b-12d3-a456-426614174000"
              className="w-full bg-slate-800/50 border border-slate-600 rounded-lg p-3 text-slate-200 outline-none focus:border-primary"
            />
          </div>
          <button onClick={handleGetReport} disabled={!analisisId || actionLoading} className="bg-slate-700 hover:bg-slate-600 text-white p-3 rounded-lg flex items-center gap-2 disabled:opacity-50">
            <Search size={18} /> Obtener Reporte
          </button>
          <button onClick={handleVerifyIntegrity} disabled={!analisisId || actionLoading} className="bg-emerald-600/80 hover:bg-emerald-500 text-white p-3 rounded-lg flex items-center gap-2 disabled:opacity-50">
            <CheckCircle size={18} /> ASR-11: Verificar Integridad
          </button>
          <button onClick={handleSimulateBreach} disabled={!analisisId || actionLoading} className="bg-red-600/80 hover:bg-red-500 text-white p-3 rounded-lg flex items-center gap-2 disabled:opacity-50">
            <ShieldAlert size={18} /> ASR-11: Simular Brecha
          </button>
        </div>

        {reportData && (
          <div className="bg-slate-900/50 p-4 rounded-lg border border-slate-700 font-mono text-sm text-slate-300">
            <p><strong className="text-primary">ID:</strong> {reportData.id}</p>
            <p><strong className="text-primary">Estado:</strong> {reportData.estado}</p>
            <p><strong className="text-emerald-400">Hash SHA-256:</strong> {reportData.hash_integridad}</p>
            <p><strong className="text-primary">Detalle:</strong> {JSON.stringify(reportData.detalle_resultados)}</p>
          </div>
        )}
      </div>

      <div className="grid grid-cols-3 gap-6 mb-8">
        <div className="glass rounded-2xl p-6">
          <div className="flex justify-between items-start">
            <div>
              <p className="text-slate-400 font-medium">Gasto Mensual</p>
              <h3 className="text-3xl font-bold mt-2 text-slate-100">$2,450</h3>
            </div>
            <div className="p-3 bg-emerald-500/20 rounded-lg text-emerald-400"><DollarSign size={24} /></div>
          </div>
          <p className="text-sm text-emerald-400 mt-4">↓ 12% vs mes anterior</p>
        </div>
        <div className="glass rounded-2xl p-6">
          <div className="flex justify-between items-start">
            <div>
              <p className="text-slate-400 font-medium">Recursos Activos</p>
              <h3 className="text-3xl font-bold mt-2 text-slate-100">142</h3>
            </div>
            <div className="p-3 bg-primary/20 rounded-lg text-primary"><Server size={24} /></div>
          </div>
          <p className="text-sm text-slate-400 mt-4">En 3 regiones (AWS)</p>
        </div>
        <div className="glass rounded-2xl p-6">
          <div className="flex justify-between items-start">
            <div>
              <p className="text-slate-400 font-medium">Desperdicio Detectado</p>
              <h3 className="text-3xl font-bold mt-2 text-red-400">$320</h3>
            </div>
            <div className="p-3 bg-red-500/20 rounded-lg text-red-400"><FileText size={24} /></div>
          </div>
          <p className="text-sm text-slate-400 mt-4">Requiere atención (Integridad ASR-11 OK)</p>
        </div>
      </div>

      <div className="glass rounded-2xl p-6 h-[400px]">
        <h3 className="text-xl font-bold mb-6 text-slate-200">Tendencia de Costos</h3>
        <ResponsiveContainer width="100%" height="100%">
          <AreaChart data={data}>
            <defs>
              <linearGradient id="colorCost" x1="0" y1="0" x2="0" y2="1">
                <stop offset="5%" stopColor="#3b82f6" stopOpacity={0.3}/>
                <stop offset="95%" stopColor="#3b82f6" stopOpacity={0}/>
              </linearGradient>
            </defs>
            <CartesianGrid strokeDasharray="3 3" stroke="#334155" vertical={false} />
            <XAxis dataKey="name" stroke="#94a3b8" tick={{fill: '#94a3b8'}} axisLine={false} />
            <YAxis stroke="#94a3b8" tick={{fill: '#94a3b8'}} axisLine={false} tickFormatter={(value) => '$' + value} />
            <Tooltip contentStyle={{ backgroundColor: '#1e293b', border: '1px solid #334155', borderRadius: '8px' }} itemStyle={{ color: '#e2e8f0' }} />
            <Area type="monotone" dataKey="cost" stroke="#3b82f6" strokeWidth={3} fillOpacity={1} fill="url(#colorCost)" />
          </AreaChart>
        </ResponsiveContainer>
      </div>
    </div>
  )
}
