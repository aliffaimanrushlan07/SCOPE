import { useCallback, useEffect, useState } from 'react'
import { useNavigate } from 'react-router-dom'
import * as api from '../api/endpoints'
import { errorMessage } from '../api/client'
import {
  Confidence,
  ErrorState,
  Loading,
  Notice,
  TopBar,
  formatDateTime,
} from '../components/ui'

/**
 * D04 — Reports: list and filter (FR10, FR13).
 *
 * Five columns: Reference, Date & time, Location, Premise name, AI confidence.
 *
 * The filters are search and date range. There is deliberately NO status
 * filter — no status exists to filter on — and no violation type or premise
 * type filter, because neither field exists in the data model. An earlier
 * wireframe showing an "All violation types" chip is stale.
 */
export default function Reports() {
  const navigate = useNavigate()

  const [filters, setFilters] = useState({ search: '', dateFrom: '', dateTo: '' })
  const [applied, setApplied] = useState({ search: '', dateFrom: '', dateTo: '' })
  const [page, setPage] = useState(1)

  const [data, setData] = useState(null)
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState('')
  const [exporting, setExporting] = useState(false)

  const load = useCallback(() => {
    setLoading(true)
    setError('')
    api
      .listReports({ ...applied, page })
      .then(setData)
      .catch((err) => setError(errorMessage(err, 'Reports could not be loaded.')))
      .finally(() => setLoading(false))
  }, [applied, page])

  useEffect(load, [load])

  const applyFilters = (event) => {
    event.preventDefault()
    setPage(1)
    setApplied(filters)
  }

  const clearFilters = () => {
    const empty = { search: '', dateFrom: '', dateTo: '' }
    setFilters(empty)
    setApplied(empty)
    setPage(1)
  }

  const handleExport = async () => {
    setExporting(true)
    try {
      await api.downloadCsv(applied)
    } catch (err) {
      setError(errorMessage(err, 'The export could not be produced.'))
    } finally {
      setExporting(false)
    }
  }

  const hasFilters = applied.search || applied.dateFrom || applied.dateTo

  return (
    <>
      <TopBar title="Reports">
        <button className="btn" onClick={handleExport} disabled={exporting}>
          {exporting ? 'Preparing…' : '↓ Export CSV'}
        </button>
      </TopBar>

      <div className="page">
        <Notice>
          Reports are read-only. Evidence is validated by the AI classifier
          before submission, so every report listed here has already passed
          validation. Administrators view and export report data; they do not
          verify, approve or reject it.
        </Notice>

        <form className="card" onSubmit={applyFilters} style={{ padding: 16 }}>
          <div
            style={{
              display: 'grid',
              gridTemplateColumns: 'minmax(200px, 2fr) 1fr 1fr auto auto',
              gap: 12,
              alignItems: 'end',
            }}
          >
            <div className="field">
              <label htmlFor="search">Search</label>
              <input
                id="search"
                placeholder="Reference number or location"
                value={filters.search}
                onChange={(e) => setFilters({ ...filters, search: e.target.value })}
              />
            </div>

            <div className="field">
              <label htmlFor="from">From</label>
              <input
                id="from"
                type="date"
                value={filters.dateFrom}
                onChange={(e) => setFilters({ ...filters, dateFrom: e.target.value })}
              />
            </div>

            <div className="field">
              <label htmlFor="to">To</label>
              <input
                id="to"
                type="date"
                value={filters.dateTo}
                onChange={(e) => setFilters({ ...filters, dateTo: e.target.value })}
              />
            </div>

            <button className="btn btn-primary" type="submit">
              Apply
            </button>
            <button
              className="btn"
              type="button"
              onClick={clearFilters}
              disabled={!hasFilters}
            >
              Clear
            </button>
          </div>
        </form>

        <div className="card">
          {loading ? (
            <Loading label="Loading reports…" />
          ) : error ? (
            <ErrorState message={error} onRetry={load} />
          ) : data?.items?.length ? (
            <>
              <div className="table-wrap">
                <table>
                  <thead>
                    <tr>
                      <th>Reference</th>
                      <th>Date &amp; time</th>
                      <th>Location</th>
                      <th>Premise name</th>
                      <th>AI confidence</th>
                    </tr>
                  </thead>
                  <tbody>
                    {data.items.map((row) => (
                      <tr
                        key={row.report_id}
                        className="clickable"
                        onClick={() => navigate(`/reports/${row.report_id}`)}
                      >
                        <td className="mono">{row.reference_no}</td>
                        <td>{formatDateTime(row.submitted_at)}</td>
                        <td>{row.address_text || '—'}</td>
                        <td>{row.premise_name || <span className="muted">Not given</span>}</td>
                        <td>
                          <Confidence value={row.ai_confidence} />
                        </td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              </div>

              <div
                style={{
                  display: 'flex',
                  alignItems: 'center',
                  gap: 12,
                  padding: '12px 16px',
                  borderTop: '1px solid var(--line)',
                  fontSize: 13,
                }}
              >
                <span className="muted">
                  {data.total} report{data.total === 1 ? '' : 's'}
                  {hasFilters ? ' matching your filters' : ''}
                </span>
                <span style={{ flex: 1 }} />
                <button
                  className="btn"
                  disabled={page <= 1}
                  onClick={() => setPage((p) => p - 1)}
                >
                  Previous
                </button>
                <span className="muted">
                  Page {data.page} of {data.total_pages || 1}
                </span>
                <button
                  className="btn"
                  disabled={page >= (data.total_pages || 1)}
                  onClick={() => setPage((p) => p + 1)}
                >
                  Next
                </button>
              </div>
            </>
          ) : (
            <div className="empty">
              {hasFilters
                ? 'No reports match these filters.'
                : 'No reports have been submitted yet.'}
            </div>
          )}
        </div>
      </div>
    </>
  )
}
