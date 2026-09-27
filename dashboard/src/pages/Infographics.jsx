import { useCallback, useEffect, useRef, useState } from 'react'
import * as api from '../api/endpoints'
import { errorMessage, mediaUrl } from '../api/client'
import { ErrorState, Loading, Notice, TopBar, formatDateTime } from '../components/ui'

/**
 * D06 — Infographic Management.
 *
 * THREE FIXED SLOTS, replace-in-place only. There is no "add slot" and no
 * delete, because the mobile Home carousel (S02) renders exactly three
 * pagination dots and the Awareness Hub (S04) exactly three buttons — neither
 * has an empty or overflow state, so a fourth slot or a deletion would break
 * both screens.
 *
 * The constraint is stated in the banner rather than left implicit, so an
 * administrator is not left hunting for a delete button that was never built.
 * It is also enforced by the database: the primary key is a CHECK-constrained
 * slot number and a trigger blocks DELETE.
 */
export default function Infographics() {
  const [slots, setSlots] = useState([])
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState('')

  const load = useCallback(() => {
    setLoading(true)
    setError('')
    api
      .listInfographics()
      .then(setSlots)
      .catch((err) => setError(errorMessage(err, 'Infographics could not be loaded.')))
      .finally(() => setLoading(false))
  }, [])

  useEffect(load, [load])

  return (
    <>
      <TopBar title="Infographics" />

      <div className="page">
        <Notice title="Three fixed slots">
          These three infographics appear in the mobile app's Awareness Hub.
          You can replace the image and edit the title of each slot, but slots
          cannot be added or deleted — that screen is built around exactly
          three.
        </Notice>

        {loading ? (
          <Loading label="Loading slots…" />
        ) : error ? (
          <ErrorState message={error} onRetry={load} />
        ) : (
          <div
            style={{
              display: 'grid',
              gridTemplateColumns: 'repeat(auto-fit, minmax(290px, 1fr))',
              gap: 18,
            }}
          >
            {slots.map((slot) => (
              <SlotCard key={slot.infographic_id} slot={slot} onSaved={load} />
            ))}
          </div>
        )}
      </div>
    </>
  )
}

function SlotCard({ slot, onSaved }) {
  const [title, setTitle] = useState(slot.title)
  const [file, setFile] = useState(null)
  const [preview, setPreview] = useState(null)
  const [saving, setSaving] = useState(false)
  const [error, setError] = useState('')
  const [saved, setSaved] = useState(false)
  const inputRef = useRef(null)

  const dirty = title !== slot.title || file != null

  const handleFile = (event) => {
    const chosen = event.target.files?.[0]
    if (!chosen) return
    setFile(chosen)
    setPreview(URL.createObjectURL(chosen))
    setSaved(false)
  }

  const handleSave = async () => {
    setSaving(true)
    setError('')
    try {
      await api.updateInfographic(slot.infographic_id, { title: title.trim(), image: file })
      setFile(null)
      setPreview(null)
      setSaved(true)
      onSaved()
    } catch (err) {
      setError(errorMessage(err, 'The slot could not be updated.'))
    } finally {
      setSaving(false)
    }
  }

  const handleReset = () => {
    setTitle(slot.title)
    setFile(null)
    setPreview(null)
    setError('')
    if (inputRef.current) inputRef.current.value = ''
  }

  return (
    <div className="card" style={{ padding: 16 }}>
      <div
        style={{
          display: 'flex',
          justifyContent: 'space-between',
          alignItems: 'center',
          marginBottom: 12,
        }}
      >
        <strong style={{ fontSize: 14 }}>Slot {slot.infographic_id}</strong>
        {saved && !dirty && (
          <span className="muted" style={{ fontSize: 12 }}>
            Saved
          </span>
        )}
      </div>

      <div
        style={{
          background: 'var(--surface-2)',
          borderRadius: 8,
          height: 210,
          display: 'grid',
          placeItems: 'center',
          overflow: 'hidden',
          marginBottom: 12,
        }}
      >
        {preview || slot.image_path ? (
          <img
            src={preview ?? mediaUrl(slot.image_path)}
            alt={slot.title}
            style={{ width: '100%', height: '100%', objectFit: 'contain' }}
            onError={(e) => {
              e.currentTarget.style.display = 'none'
            }}
          />
        ) : (
          <span className="muted" style={{ fontSize: 13 }}>
            No image
          </span>
        )}
      </div>

      <div className="field" style={{ marginBottom: 10 }}>
        <label htmlFor={`title-${slot.infographic_id}`}>Title</label>
        <input
          id={`title-${slot.infographic_id}`}
          value={title}
          maxLength={120}
          onChange={(e) => {
            setTitle(e.target.value)
            setSaved(false)
          }}
        />
      </div>

      <div className="muted" style={{ fontSize: 12, marginBottom: 10, lineHeight: 1.5 }}>
        {slot.updated_at
          ? `Last updated ${formatDateTime(slot.updated_at)}`
          : 'Never updated'}
        <br />
        Portrait 3:4, minimum 1080 × 1440 recommended.
      </div>

      {error && (
        <div className="notice notice-error" style={{ marginBottom: 10, fontSize: 13 }}>
          <span aria-hidden="true">⚠</span>
          <div>{error}</div>
        </div>
      )}

      <input
        ref={inputRef}
        type="file"
        accept="image/jpeg,image/png,image/webp"
        onChange={handleFile}
        style={{ display: 'none' }}
        id={`file-${slot.infographic_id}`}
      />

      <div style={{ display: 'flex', gap: 8, flexWrap: 'wrap' }}>
        <button className="btn" onClick={() => inputRef.current?.click()}>
          Replace image
        </button>
        <button
          className="btn btn-primary"
          onClick={handleSave}
          disabled={!dirty || saving || !title.trim()}
        >
          {saving ? 'Saving…' : 'Publish'}
        </button>
        {dirty && (
          <button className="btn" onClick={handleReset} disabled={saving}>
            Cancel
          </button>
        )}
      </div>
    </div>
  )
}
