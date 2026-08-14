import { format, parseISO } from 'date-fns'

export function TopBar({ title, children }) {
  return (
    <header className="topbar">
      <h1 style={{ fontSize: 19, flex: 1 }}>{title}</h1>
      {children}
    </header>
  )
}

export function Notice({ children, tone = 'default', title }) {
  return (
    <div className={`notice ${tone === 'error' ? 'notice-error' : ''}`}>
      <span aria-hidden="true">{tone === 'error' ? '⚠' : 'ⓘ'}</span>
      <div>
        {title && <strong style={{ display: 'block' }}>{title}</strong>}
        {children}
      </div>
    </div>
  )
}

export function Loading({ label = 'Loading…' }) {
  return <div className="empty">{label}</div>
}

export function ErrorState({ message, onRetry }) {
  return (
    <div className="empty">
      <div style={{ marginBottom: 12 }}>{message}</div>
      {onRetry && (
        <button className="btn" onClick={onRetry}>
          Retry
        </button>
      )}
    </div>
  )
}

/** Timestamps arrive as UTC and are displayed in the officer's local time. */
export function formatDateTime(iso) {
  if (!iso) return '—'
  try {
    return format(parseISO(iso), 'd MMM yyyy, HH:mm')
  } catch {
    return iso
  }
}

export function formatDate(iso) {
  if (!iso) return '—'
  try {
    return format(parseISO(iso), 'd MMM yyyy')
  } catch {
    return iso
  }
}

/**
 * The AI confidence score, shown as provenance rather than as a control.
 *
 * Rendered in greyscale on purpose. A green/red treatment would read as a
 * verdict the officer is being asked to act on, when in fact the decision was
 * already made before submission and cannot be changed here.
 */
export function Confidence({ value }) {
  const pct = Math.round(Number(value) * 100)
  return (
    <span style={{ display: 'inline-flex', alignItems: 'center', gap: 8 }}>
      <span
        style={{
          width: 46,
          height: 5,
          background: 'var(--surface-2)',
          borderRadius: 3,
          overflow: 'hidden',
        }}
      >
        <span
          style={{
            display: 'block',
            width: `${pct}%`,
            height: '100%',
            background: 'var(--ink-2)',
          }}
        />
      </span>
      <span className="mono">{pct}%</span>
    </span>
  )
}
