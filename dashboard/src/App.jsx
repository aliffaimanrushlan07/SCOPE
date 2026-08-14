import { BrowserRouter, Navigate, Route, Routes } from 'react-router-dom'
import { AuthProvider, useAuth } from './components/AuthContext'
import Layout from './components/Layout'
import { Loading } from './components/ui'

import Login from './pages/Login'
import Overview from './pages/Overview'
import HotspotMap from './pages/HotspotMap'
import Reports from './pages/Reports'
import ReportDetail from './pages/ReportDetail'
import Infographics from './pages/Infographics'

function RequireAuth({ children }) {
  const { admin, loading } = useAuth()
  if (loading) return <Loading label="Checking your session…" />
  if (!admin) return <Navigate to="/login" replace />
  return children
}

function RedirectIfSignedIn({ children }) {
  const { admin, loading } = useAuth()
  if (loading) return <Loading />
  if (admin) return <Navigate to="/overview" replace />
  return children
}

export default function App() {
  return (
    <BrowserRouter>
      <AuthProvider>
        <Routes>
          <Route
            path="/login"
            element={
              <RedirectIfSignedIn>
                <Login />
              </RedirectIfSignedIn>
            }
          />

          <Route
            element={
              <RequireAuth>
                <Layout />
              </RequireAuth>
            }
          >
            <Route path="/overview" element={<Overview />} />
            <Route path="/hotspots" element={<HotspotMap />} />
            <Route path="/reports" element={<Reports />} />
            <Route path="/reports/:reportId" element={<ReportDetail />} />
            <Route path="/infographics" element={<Infographics />} />
          </Route>

          <Route path="*" element={<Navigate to="/overview" replace />} />
        </Routes>
      </AuthProvider>
    </BrowserRouter>
  )
}
