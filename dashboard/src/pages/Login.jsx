import { useState } from 'react'
import { useNavigate, useSearchParams } from 'react-router-dom'
import { useAuth } from '../components/AuthContext'
import { errorMessage } from '../api/client'
import scopeMark from '../assets/scope_mark.png'

/** D01 — Admin Login (FR08). */
export default function Login() {
  const { signIn } = useAuth()
  const navigate = useNavigate()
  const [params] = useSearchParams()

  const [email, setEmail] = useState('')
  const [password, setPassword] = useState('')
  const [error, setError] = useState(
    // Set by the 401 interceptor so an officer whose session lapsed mid-task
    // understands why they are back here.
    params.get('expired') ? 'Your session timed out. Please sign in again.' : '',
  )
  const [submitting, setSubmitting] = useState(false)

  const handleSubmit = async (event) => {
    event.preventDefault()
    if (submitting) return

    setSubmitting(true)
    setError('')
    try {
      await signIn(email.trim(), password)
      navigate('/overview', { replace: true })
    } catch (err) {
      // The backend returns one message for every failure mode so officer
      // email addresses cannot be enumerated; it is shown verbatim.
      setError(errorMessage(err, 'Invalid username or password.'))
      setSubmitting(false)
    }
  }

  return (
    <div
      style={{
        minHeight: '100vh',
        display: 'grid',
        placeItems: 'center',
        padding: 20,
      }}
    >
      <div className="card" style={{ width: '100%', maxWidth: 400, padding: 30 }}>
        <div
          style={{
            display: 'flex',
            alignItems: 'center',
            gap: 10,
            fontWeight: 700,
            letterSpacing: 2,
            fontSize: 19,
          }}
        >
          <img src={scopeMark} alt="" aria-hidden="true" width="26" height="26" />
          SCOPE
        </div>

        <h2 style={{ fontSize: 17, marginTop: 20 }}>Administrative Dashboard</h2>
        <p className="muted" style={{ fontSize: 13, lineHeight: 1.5, marginTop: 6 }}>
          For authorised enforcement officers and NCSM staff only. Access to
          report data is recorded.
        </p>

        <form
          onSubmit={handleSubmit}
          style={{ display: 'flex', flexDirection: 'column', gap: 14, marginTop: 22 }}
        >
          <div className="field">
            <label htmlFor="email">Official email</label>
            <input
              id="email"
              type="email"
              autoComplete="username"
              required
              value={email}
              onChange={(e) => setEmail(e.target.value)}
              placeholder="officer@ncsm.org.my"
            />
          </div>

          <div className="field">
            <label htmlFor="password">Password</label>
            <input
              id="password"
              type="password"
              autoComplete="current-password"
              required
              value={password}
              onChange={(e) => setPassword(e.target.value)}
            />
          </div>

          {error && (
            <div className="notice notice-error" role="alert">
              <span aria-hidden="true">⚠</span>
              <div>{error}</div>
            </div>
          )}

          <button className="btn btn-primary" type="submit" disabled={submitting}>
            {submitting ? 'Signing in…' : 'Log in'}
          </button>
        </form>

        {/* D01 component 7 — the session disclosure. */}
        <p className="muted" style={{ fontSize: 12, marginTop: 20, lineHeight: 1.5 }}>
          For security, your session ends automatically after 30 minutes of
          inactivity.
        </p>
      </div>
    </div>
  )
}
