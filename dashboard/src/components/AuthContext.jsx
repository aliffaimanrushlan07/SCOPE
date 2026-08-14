import { createContext, useCallback, useContext, useEffect, useState } from 'react'
import * as api from '../api/endpoints'
import { tokenStore } from '../api/client'

const AuthContext = createContext(null)

export function AuthProvider({ children }) {
  const [admin, setAdmin] = useState(null)
  const [loading, setLoading] = useState(true)

  // A token in storage is not proof of a live session — it may have expired
  // while the tab was closed. It is verified against the server once on boot,
  // so a stale token never renders a dashboard the officer cannot actually use.
  useEffect(() => {
    let cancelled = false
    if (!tokenStore.get()) {
      setLoading(false)
      return
    }
    api
      .me()
      .then((data) => !cancelled && setAdmin(data))
      .catch(() => tokenStore.clear())
      .finally(() => !cancelled && setLoading(false))
    return () => {
      cancelled = true
    }
  }, [])

  const signIn = useCallback(async (email, password) => {
    const session = await api.login(email, password)
    tokenStore.set(session.access_token)
    setAdmin(session.admin)
    return session
  }, [])

  const signOut = useCallback(async () => {
    // Best effort: the LOGOUT activity-log entry matters, but a failed call
    // must not strand the officer in a session they asked to end.
    try {
      await api.logout()
    } catch {
      /* ignore */
    }
    tokenStore.clear()
    setAdmin(null)
  }, [])

  return (
    <AuthContext.Provider value={{ admin, loading, signIn, signOut }}>
      {children}
    </AuthContext.Provider>
  )
}

export function useAuth() {
  const context = useContext(AuthContext)
  if (!context) throw new Error('useAuth must be used inside AuthProvider')
  return context
}
