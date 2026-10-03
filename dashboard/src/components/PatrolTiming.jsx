import { useState } from 'react'

/**
 * D02 — patrol timing: when violations are reported, by day and time of day.
 *
 * All times are Malaysian local time and every row is a calendar day, so a
 * report at 01:00 Saturday sits on the Saturday row. Columns are two-hour
 * blocks starting at midnight; the named categories above them each span
 * whole blocks, which is why the band lines up with the grid.
 *
 * Below MIN_RELIABLE reports the grid is still drawn, but faded and reduced:
 * a handful of points produces a "peak" that is mostly chance, and the panel
 * should not present it with the same weight as a well-supported one.
 */

const DAYS = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday']
const MIN_RELIABLE = 5

// Single-hue sequential teal, light to dark, from the dashboard's own --chart-bar
// family. Magnitude only — the D03 band colours mean density on the map and are
// deliberately not reused here. The darker half takes white ink.
const STEPS = ['#d5f5ef', '#a7e9dd', '#6fd3c3', '#2fb3a2', '#0d8f80', '#0b6b61']
const DARK_FROM = 3

const pad = (hour) => String(hour).padStart(2, '0')
const blockRange = (block) => `${pad(block * 2)}:00–${pad((block * 2 + 2) % 24)}:00`

function categoryFor(categories, block) {
  const hour = block * 2
  return categories.find((c) => hour >= c.start_hour && hour < c.end_hour)?.label
}

function cellStyle(count, max) {
  if (!count) return { background: 'var(--surface)', color: 'transparent' }
  const index = Math.min(STEPS.length - 1, Math.floor((count / max) * STEPS.length - 1e-9))
  return {
    background: STEPS[index],
    color: index >= DARK_FROM ? '#ffffff' : 'var(--ink)',
  }
}

export default function PatrolTiming({ timing }) {
  const [hover, setHover] = useState(null)

  if (timing.total === 0) {
    return <div className="empty">No reports for this selection in this period.</div>
  }

  const reliable = timing.total >= MIN_RELIABLE
  const max = Math.max(...timing.grid.flat())
  const busiestDay = timing.by_day.indexOf(Math.max(...timing.by_day))
  const busiestCategory = timing.categories.reduce((a, b) => (b.count > a.count ? b : a))
  const peak = timing.peak

  const cellHeight = reliable ? 34 : 22
  const columns = `${reliable ? 44 : 34}px repeat(12, minmax(${reliable ? 36 : 24}px, 1fr))`

  return (
    <div>
      {!reliable && (
        <p className="muted" style={{ fontSize: 12.5, margin: '0 0 10px' }}>
          Only {timing.total} {timing.total === 1 ? 'report' : 'reports'} here — pattern
          not yet reliable.
        </p>
      )}

      <div style={{ opacity: reliable ? 1 : 0.45, maxWidth: reliable ? 'none' : 520 }}>
        <div style={{ fontSize: reliable ? 14 : 12.5, marginBottom: 14, lineHeight: 1.6 }}>
          <div>
            <strong>Peak:</strong> {DAYS[peak.day]} {blockRange(peak.block)} (
            {categoryFor(timing.categories, peak.block)}) · {peak.count}{' '}
            {peak.count === 1 ? 'report' : 'reports'}
          </div>
          <div className="muted">
            Busiest day: {DAYS[busiestDay]} · Busiest time: {busiestCategory.label} (
            {pad(busiestCategory.start_hour)}:00–{pad(busiestCategory.end_hour % 24)}:00)
          </div>
        </div>

        <div style={{ overflowX: 'auto', position: 'relative' }}>
          <div
            role="table"
            aria-label="Reports by day of week and two-hour block, Malaysian time"
            style={{ display: 'grid', gridTemplateColumns: columns, gap: 2, minWidth: reliable ? 520 : 360 }}
          >
            {/* Category band */}
            <div />
            {timing.categories.map((category) => (
              <div
                key={category.label}
                style={{
                  gridColumn: `span ${(category.end_hour - category.start_hour) / 2}`,
                  fontSize: reliable ? 11 : 9.5,
                  fontWeight: 600,
                  color: 'var(--ink-2)',
                  textAlign: 'center',
                  padding: '3px 2px',
                  background: 'var(--surface-2)',
                  borderRadius: 4,
                  whiteSpace: 'nowrap',
                  overflow: 'hidden',
                  textOverflow: 'ellipsis',
                }}
                title={`${category.label}: ${pad(category.start_hour)}:00–${pad(category.end_hour % 24)}:00`}
              >
                {category.label}
              </div>
            ))}

            {/* Hour labels */}
            <div />
            {Array.from({ length: 12 }, (_, block) => (
              <div
                key={block}
                className="muted"
                style={{ fontSize: reliable ? 10.5 : 9, textAlign: 'left', paddingTop: 2 }}
              >
                {pad(block * 2)}
              </div>
            ))}

            {/* Rows */}
            {timing.grid.map((row, day) => [
              <div
                key={`label-${day}`}
                className="muted"
                style={{ fontSize: reliable ? 12 : 10.5, alignSelf: 'center' }}
              >
                {DAYS[day].slice(0, 3)}
              </div>,
              ...row.map((count, block) => {
                const active = hover && hover.day === day && hover.block === block
                return (
                  <div
                    key={`${day}-${block}`}
                    role="cell"
                    aria-label={`${DAYS[day]} ${blockRange(block)}: ${count} reports`}
                    onMouseEnter={() => setHover({ day, block, count })}
                    onMouseLeave={() => setHover(null)}
                    style={{
                      ...cellStyle(count, max),
                      height: cellHeight,
                      borderRadius: 4,
                      display: 'grid',
                      placeItems: 'center',
                      fontSize: reliable ? 12 : 10,
                      fontWeight: 600,
                      outline: active ? '2px solid var(--ink)' : 'none',
                      outlineOffset: -2,
                      cursor: 'default',
                    }}
                  >
                    {count || ''}
                  </div>
                )
              }),
            ])}
          </div>
        </div>

        <div
          className="muted"
          style={{ fontSize: 12, minHeight: 18, marginTop: 8 }}
          aria-live="polite"
        >
          {hover
            ? `${DAYS[hover.day]} · ${blockRange(hover.block)} · ${categoryFor(
                timing.categories,
                hover.block,
              )} · ${hover.count} ${hover.count === 1 ? 'report' : 'reports'}`
            : 'Malaysian time. Hover a cell for details.'}
        </div>

        <div
          style={{
            display: 'grid',
            gridTemplateColumns: 'repeat(auto-fit, minmax(240px, 1fr))',
            gap: 22,
            marginTop: 16,
          }}
        >
          <Totals
            title="Reports by day"
            rows={timing.by_day.map((count, day) => ({ label: DAYS[day], count }))}
            compact={!reliable}
          />
          <Totals
            title="Reports by time of day"
            rows={timing.categories.map((c) => ({
              label: `${c.label} (${pad(c.start_hour)}–${pad(c.end_hour % 24)})`,
              count: c.count,
            }))}
            compact={!reliable}
          />
        </div>
      </div>
    </div>
  )
}

function Totals({ title, rows, compact }) {
  const max = Math.max(1, ...rows.map((r) => r.count))
  return (
    <div>
      <h4 style={{ fontSize: compact ? 12 : 13, margin: '0 0 8px' }}>{title}</h4>
      <div style={{ display: 'flex', flexDirection: 'column', gap: compact ? 4 : 6 }}>
        {rows.map((row) => (
          <div
            key={row.label}
            style={{
              display: 'grid',
              gridTemplateColumns: `${compact ? 120 : 150}px 1fr 28px`,
              alignItems: 'center',
              gap: 8,
              fontSize: compact ? 11 : 12.5,
            }}
          >
            <span style={{ whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }}>
              {row.label}
            </span>
            <div style={{ height: compact ? 5 : 7, background: 'var(--surface-2)', borderRadius: 4 }}>
              <div
                style={{
                  width: `${(row.count / max) * 100}%`,
                  height: '100%',
                  background: 'var(--chart-bar)',
                  borderRadius: 4,
                }}
              />
            </div>
            <strong style={{ textAlign: 'right' }}>{row.count}</strong>
          </div>
        ))}
      </div>
    </div>
  )
}
