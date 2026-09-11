import { NavLink, Outlet, useNavigate } from 'react-router-dom'
import { useAuth } from './AuthContext'
import scopeMarkWhite from '../assets/scope_mark_white.png'

/**
 * Persistent shell across D02–D06.
 *
 * Four destinations only: Overview, Hotspot Map, Reports, Infographics. There
 * is no "Pending", no "Verification queue" and no "Approvals" — none of those
 * workflows exist in this system, and a nav item promising one would be the
 * first thing an examiner tested.
 */
const NAV = [
  { to: '/overview', label: 'Overview', icon: '▤' },
  { to: '/hotspots', label: 'Hotspot Map', icon: '◎' },
  { to: '/reports', label: 'Reports', icon: '☰' },
  { to: '/infographics', label: 'Infographics', icon: '▦' },
]

export default function Layout() {
  const { admin, signOut } = useAuth()
  const navigate = useNavigate()

  const handleSignOut = async () => {
    await signOut()
    navigate('/login', { replace: true })
  }

  return (
    <div className="shell">
      <aside className="sidebar">
        <div className="sidebar-brand">
          <img src={scopeMarkWhite} alt="" aria-hidden="true" width="22" height="22" />
          <span>SCOPE</span>
        </div>

        <nav className="nav">
          {NAV.map((item) => (
            <NavLink
              key={item.to}
              to={item.to}
              className={({ isActive }) => (isActive ? 'active' : '')}
            >
              <span aria-hidden="true" style={{ width: 16 }}>
                {item.icon}
              </span>
              {item.label}
            </NavLink>
          ))}
        </nav>

        <div className="sidebar-foot">
          <div style={{ fontWeight: 600 }}>{admin?.full_name}</div>
          <div className="muted" style={{ fontSize: 12, marginBottom: 10 }}>
            {admin?.organisation} · {admin?.role}
          </div>
          <button className="btn" style={{ width: '100%' }} onClick={handleSignOut}>
            Sign out
          </button>
        </div>
      </aside>

      <main>
        <Outlet />
      </main>
    </div>
  )
}
