import { useCallback, useEffect, useState } from 'react'
import { Link, useParams } from 'react-router-dom'
import { MapContainer, Marker, TileLayer } from 'react-leaflet'
import * as api from '../api/endpoints'
import { errorMessage, mediaUrl } from '../api/client'
import {
  Confidence,
  ErrorState,
  Loading,
  Notice,
  TopBar,
  formatDateTime,
} from '../components/ui'
import 'leaflet/dist/leaflet.css'
import { pinIcon } from '../components/leafletIcons'

/**
 * D05 — Report Detail, READ-ONLY.
 *
 * There is no approve, reject, override, edit or delete control anywhere on
 * this page, and no endpoint behind one. That absence is the design, not an
 * omission: FR12 (manual review / override) was removed, and the AI decision
 * is final because it is made before submission.
 *
 * The AI panel is provenance — which model version and threshold judged this
 * evidence, and when. It is display only.
 */
export default function ReportDetail() {
  const { reportId } = useParams()
  const [report, setReport] = useState(null)
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState('')
  const [activePhoto, setActivePhoto] = useState(0)

  const load = useCallback(() => {
    setLoading(true)
    setError('')
    api
      .getReport(reportId)
      .then(setReport)
      .catch((err) => setError(errorMessage(err, 'This report could not be loaded.')))
      .finally(() => setLoading(false))
  }, [reportId])

  useEffect(load, [load])

  if (loading) return <Loading label="Loading report…" />
  if (error) return <ErrorState message={error} onRetry={load} />
  if (!report) return null

  const photo = report.photos[activePhoto]
  const position = [Number(report.latitude), Number(report.longitude)]

  return (
    <>
      <TopBar title={report.reference_no}>
        <Link to="/reports" className="btn">
          ← Back to reports
        </Link>
      </TopBar>

      <div className="page">
        {/* Shipped in the first commit, not added later: an officer must never
            be in doubt about whether this screen can change anything. */}
        <Notice title="READ-ONLY">
          Photo evidence is validated by the AI classifier before a report is
          submitted, so this report has already passed validation. You may view
          and export it. There is no approve, reject or override action —
          administrators do not verify reports.
        </Notice>

        <div
          style={{
            display: 'grid',
            gridTemplateColumns: 'minmax(0, 1.55fr) minmax(0, 1fr)',
            gap: 18,
            alignItems: 'start',
          }}
        >
          <section className="card" style={{ padding: 18 }}>
            <h3 style={{ fontSize: 15, marginBottom: 12 }}>Photo evidence</h3>

            {report.photos.length === 0 ? (
              <div className="empty">No photographs stored.</div>
            ) : (
              <>
                <a
                  href={mediaUrl(photo.storage_path)}
                  target="_blank"
                  rel="noreferrer"
                  title="Open full size"
                >
                  <img
                    src={mediaUrl(photo.storage_path)}
                    alt={`Evidence ${photo.sequence_no}`}
                    style={{
                      width: '100%',
                      maxHeight: 460,
                      objectFit: 'contain',
                      background: 'var(--surface-2)',
                      borderRadius: 8,
                      display: 'block',
                    }}
                  />
                </a>

                <div style={{ display: 'flex', gap: 10, marginTop: 12, flexWrap: 'wrap' }}>
                  {report.photos.map((item, index) => (
                    <button
                      key={item.storage_path}
                      onClick={() => setActivePhoto(index)}
                      style={{
                        padding: 0,
                        border:
                          index === activePhoto
                            ? '2px solid var(--brand)'
                            : '2px solid var(--line)',
                        borderRadius: 8,
                        overflow: 'hidden',
                        background: 'none',
                        lineHeight: 0,
                      }}
                    >
                      <img
                        src={mediaUrl(item.storage_path)}
                        alt={`Thumbnail ${item.sequence_no}`}
                        style={{ width: 74, height: 74, objectFit: 'cover' }}
                      />
                    </button>
                  ))}
                </div>

                <div
                  style={{
                    marginTop: 14,
                    display: 'flex',
                    alignItems: 'center',
                    gap: 14,
                    fontSize: 13,
                  }}
                >
                  <span className="muted">
                    Photo {photo.sequence_no} of {report.photos.length}
                  </span>
                  <Confidence value={photo.confidence_score} />
                  <span className="muted">
                    Captured {formatDateTime(photo.captured_at)}
                  </span>
                </div>
              </>
            )}
          </section>

          <div style={{ display: 'flex', flexDirection: 'column', gap: 18 }}>
            <section className="card" style={{ padding: 18 }}>
              <h3 style={{ fontSize: 15, marginBottom: 12 }}>Location</h3>
              <MapContainer
                center={position}
                zoom={16}
                style={{ height: 200, width: '100%' }}
                scrollWheelZoom={false}
              >
                <TileLayer
                  attribution='&copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a>'
                  url="https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png"
                />
                <Marker position={position} icon={pinIcon} />
              </MapContainer>

              <dl style={{ margin: '14px 0 0', fontSize: 13.5 }}>
                <Row label="Premise" value={report.premise_name || 'Not given'} />
                <Row label="Address" value={report.address_text || '—'} />
                <Row
                  label="Coordinates"
                  value={
                    <span className="mono">
                      {Number(report.latitude).toFixed(5)},{' '}
                      {Number(report.longitude).toFixed(5)}
                    </span>
                  }
                />
                {report.location_integrity_metres != null && (
                  <Row
                    label="Capture distance"
                    value={
                      <>
                        {report.location_integrity_metres} m
                        <div className="muted" style={{ fontSize: 12, marginTop: 2 }}>
                          Between where the photo was taken and where the
                          reporter tagged it.
                        </div>
                      </>
                    }
                  />
                )}
              </dl>
            </section>

            <section className="card" style={{ padding: 18 }}>
              <h3 style={{ fontSize: 15, marginBottom: 12 }}>AI classification</h3>
              {report.classification ? (
                <dl style={{ margin: 0, fontSize: 13.5 }}>
                  <Row label="Outcome" value={report.classification.outcome} />
                  <Row
                    label="Highest score"
                    value={<Confidence value={report.classification.highest_confidence} />}
                  />
                  <Row
                    label="Threshold"
                    value={
                      <span className="mono">
                        {Number(report.classification.threshold_used).toFixed(4)}
                      </span>
                    }
                  />
                  <Row
                    label="Model"
                    value={<span className="mono">{report.classification.model_version}</span>}
                  />
                  <Row
                    label="Photos"
                    value={`${report.classification.photos_passed} of ${report.classification.photos_evaluated} passed`}
                  />
                  <Row
                    label="Evaluated"
                    value={formatDateTime(report.classification.evaluated_at)}
                  />
                </dl>
              ) : (
                <div className="muted">No classification record.</div>
              )}
              <p className="muted" style={{ fontSize: 12, marginTop: 12, lineHeight: 1.5 }}>
                Evaluated before submission. Display only — this result cannot
                be changed from the dashboard.
              </p>
            </section>

            <section className="card" style={{ padding: 18 }}>
              <h3 style={{ fontSize: 15, marginBottom: 12 }}>Report details</h3>
              <dl style={{ margin: 0, fontSize: 13.5 }}>
                <Row
                  label="Reference"
                  value={<span className="mono">{report.reference_no}</span>}
                />
                <Row label="Reported" value={formatDateTime(report.reported_at)} />
                <Row label="Submitted" value={formatDateTime(report.submitted_at)} />
                <Row label="Photos" value={report.photos.length} />
                <Row
                  label="Reporter"
                  value={
                    <>
                      {report.reporter}
                      <div className="muted" style={{ fontSize: 12, marginTop: 2 }}>
                        SCOPE holds no identifying information about reporters.
                      </div>
                    </>
                  }
                />
              </dl>
            </section>
          </div>
        </div>
      </div>
    </>
  )
}

function Row({ label, value }) {
  return (
    <div
      style={{
        display: 'grid',
        gridTemplateColumns: '116px 1fr',
        gap: 10,
        padding: '7px 0',
        borderBottom: '1px solid var(--line)',
      }}
    >
      <dt className="muted">{label}</dt>
      <dd style={{ margin: 0 }}>{value}</dd>
    </div>
  )
}
