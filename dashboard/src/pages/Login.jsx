import { useState } from 'react'
import { useNavigate, useSearchParams } from 'react-router-dom'
import { useAuth } from '../components/AuthContext'
import { errorMessage } from '../api/client'
import scopeMark from '../assets/scope_mark.png'
import BorderGlow from '../components/BorderGlow'
import GradientWaves from '../components/GradientWaves'
import SpecularButton from '../components/SpecularButton'

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
        position: 'relative',
        minHeight: '100vh',
        display: 'grid',
        placeItems: 'center',
        padding: 20,
      }}
    >
      {/* Decorative backdrop. The chrome teal behind it shows through where
          the waves fade out, and is all that renders without WebGL 2. Grain
          and pointer parallax are off: GPU cost for no gain on a sign-in. */}
      <div
        aria-hidden="true"
        style={{ position: 'fixed', inset: 0, zIndex: 0, background: 'var(--chrome)' }}
      >
        <GradientWaves
          horizonColor="#115E59"
          waveColor="#99F6E4"
          crestColor="#CCFBF1"
          speed={0.25}
          detail="low"
          mouseInteraction={false}
          grain={false}
        />
      </div>

      {/* The edge nearest the pointer lights in the brand teals. Intensity
          and edge fill are kept low because the Log in button's highlight
          also reacts near the bottom edge, and the fill must not tint the
          text it sits behind. */}
      <BorderGlow
        className="login-card"
        backgroundColor="#ffffff"
        borderRadius={10}
        colors={['#115e59', '#2dd4bf', '#99f6e4']}
        glowColor="168 84 78"
        glowIntensity={0.7}
        glowRadius={32}
        coneSpread={20}
        fillOpacity={0.15}
      >
        <div style={{ padding: 30 }}>
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
            <img src={scopeMark} alt="" aria-hidden="true" width="34" height="34" />
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

            {/* Colours must be literal hex because the shader reads them, not
                CSS: the edge stroke is --chrome, the highlight is the wave
                colour of the backdrop. Fill, hover and focus are .login-submit. */}
            <SpecularButton
              type="submit"
              disabled={submitting}
              className="login-submit"
              size="sm"
              radius={8}
              textColor="#ffffff"
              baseColor="#0b2f2c"
              lineColor="#99f6e4"
              proximity={200}
            >
              {submitting ? 'Signing in…' : 'Log in'}
            </SpecularButton>
          </form>

          {/* D01 component 7 — the session disclosure. */}
          <p className="muted" style={{ fontSize: 12, marginTop: 20, lineHeight: 1.5 }}>
            For security, your session ends automatically after 30 minutes of
            inactivity.
          </p>
        </div>
      </BorderGlow>
    </div>
  )
}
