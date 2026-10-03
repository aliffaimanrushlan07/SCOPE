import { useCallback, useEffect, useRef, useState } from 'react'
import * as api from '../api/endpoints'
import { errorMessage, mediaUrl } from '../api/client'
import { ErrorState, Loading, Notice, TopBar, formatDateTime } from '../components/ui'

/**
 * D06 — Infographic Management.
 *
 * TWO FIXED SLOTS. Each can be replaced in place or deleted. Deleting empties
 * the slot rather than removing it, so the card stays and the administrator
 * can publish a new infographic into it. The mobile Awareness Hub (S04) lists
 * published slots only.
 *
 * The slot count is enforced by the database: the primary key is a
 * CHECK-constrained slot number and a trigger blocks row deletion.
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
        <Notice title="Two slots">
          Published infographics appear in the mobile app's Awareness Hub. You
          can replace the image, edit the title or delete each one. A deleted
          slot stays here, empty, so you can publish a new infographic into it.
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
  const savedTitle = slot.title ?? ''
  const empty = slot.image_path == null
  const [title, setTitle] = useState(savedTitle)
  const [file, setFile] = useState(null)
  const [preview, setPreview] = useState(null)
  const [saving, setSaving] = useState(false)
  const [deleting, setDeleting] = useState(false)
  const [error, setError] = useState('')
  const [saved, setSaved] = useState(false)
  const inputRef = useRef(null)

  // Follow the server after a reload, e.g. the title clearing on delete.
  useEffect(() => setTitle(savedTitle), [savedTitle])

  const dirty = title !== savedTitle || file != null
  const busy = saving || deleting

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

  const handleDelete = async () => {
    const ok = window.confirm(
      `Delete "${slot.title}" from slot ${slot.infographic_id}? ` +
        'It will disappear from the mobile app straight away.',
    )
    if (!ok) return
    setDeleting(true)
    setError('')
    try {
      await api.deleteInfographic(slot.infographic_id)
      handleReset()
      setSaved(false)
      onSaved()
    } catch (err) {
      setError(errorMessage(err, 'The slot could not be deleted.'))
    } finally {
      setDeleting(false)
    }
  }

  const handleReset = () => {
    setTitle(savedTitle)
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
        {empty ? (
          <span className="muted" style={{ fontSize: 12 }}>
            Empty
          </span>
        ) : (
          saved &&
          !dirty && (
            <span className="muted" style={{ fontSize: 12 }}>
              Saved
            </span>
          )
        )}
      </div>

      <div
        style={{
          position: 'relative',
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
          // Absolutely positioned so the box, not the image, sets the size:
          // as a grid item, height: 100% did not resolve and a portrait
          // infographic overflowed and was cropped. Keyed by its source so a
          // new image gets a fresh element — onError hides the element, and
          // that must not carry over to the next image.
          <img
            key={preview ?? slot.image_path}
            src={preview ?? mediaUrl(slot.image_path)}
            alt={title}
            style={{
              position: 'absolute',
              inset: 0,
              width: '100%',
              height: '100%',
              objectFit: 'contain',
            }}
            onError={(e) => {
              e.currentTarget.style.display = 'none'
            }}
          />
        ) : (
          <span className="muted" style={{ fontSize: 13 }}>
            {empty ? 'Empty slot — choose an image to publish' : 'No image'}
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
          ? `${empty ? 'Deleted' : 'Last updated'} ${formatDateTime(slot.updated_at)}`
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
        <button className="btn" onClick={() => inputRef.current?.click()} disabled={busy}>
          {empty ? 'Choose image' : 'Replace image'}
        </button>
        <button
          className="btn btn-primary"
          onClick={handleSave}
          disabled={!dirty || busy || !title.trim() || (empty && !file)}
        >
          {saving ? 'Saving…' : 'Publish'}
        </button>
        {dirty && (
          <button className="btn" onClick={handleReset} disabled={busy}>
            Cancel
          </button>
        )}
        {!empty && (
          <button
            className="btn btn-danger"
            onClick={handleDelete}
            disabled={busy}
            style={{ marginLeft: 'auto' }}
          >
            {deleting ? 'Deleting…' : 'Delete'}
          </button>
        )}
      </div>
    </div>
  )
}
