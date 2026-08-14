import axios from 'axios'

/**
 * Axios instance for the SCOPE admin API.
 *
 * The base URL is supplied at build time so the same source runs against a
 * local backend and a deployed one. Vite exposes only VITE_-prefixed
 * variables to the browser, which is deliberate — it is why no secret is ever
 * read here.
 */
export const API_ORIGIN =
  import.meta.env.VITE_API_ORIGIN ?? 'http://127.0.0.1:8000'

const client = axios.create({
  baseURL: `${API_ORIGIN}/api/v1`,
  timeout: 20000,
})

const TOKEN_KEY = 'scope_admin_token'

export const tokenStore = {
  get: () => localStorage.getItem(TOKEN_KEY),
  set: (token) => localStorage.setItem(TOKEN_KEY, token),
  clear: () => localStorage.removeItem(TOKEN_KEY),
}

client.interceptors.request.use((config) => {
  const token = tokenStore.get()
  if (token) config.headers.Authorization = `Bearer ${token}`
  return config
})

/**
 * A 401 means the 30-minute inactivity session disclosed on D01 has lapsed,
 * or the token is invalid. Either way the officer must sign in again, so the
 * token is dropped and the app is sent to the login screen.
 *
 * Handled centrally rather than per-screen: a session can expire during any
 * request, and every screen behaving the same way is what makes the timeout
 * predictable.
 */
client.interceptors.response.use(
  (response) => response,
  (error) => {
    if (error.response?.status === 401 && tokenStore.get()) {
      tokenStore.clear()
      if (!window.location.pathname.startsWith('/login')) {
        window.location.assign('/login?expired=1')
      }
    }
    return Promise.reject(error)
  },
)

/** Turns an axios failure into a message worth showing an officer. */
export function errorMessage(error, fallback = 'Something went wrong.') {
  const detail = error?.response?.data?.detail
  if (typeof detail === 'string') return detail
  if (Array.isArray(detail) && detail[0]?.msg) return detail[0].msg
  if (error?.code === 'ECONNABORTED') return 'The server took too long to respond.'
  if (!error?.response) return 'Cannot reach the SCOPE service. Is the backend running?'
  return fallback
}

/** Resolves a stored media path to a full URL. */
export const mediaUrl = (path) => `${API_ORIGIN}/media/${path}`

export default client
