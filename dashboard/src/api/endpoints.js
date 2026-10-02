import client from './client'

/**
 * Every call in this module is a GET, except the two that authenticate and the
 * one that replaces an infographic slot.
 *
 * There is deliberately no updateReport, approveReport, rejectReport or
 * deleteReport. No such endpoint exists on the backend: administrators view
 * and export, they never verify, approve, reject or amend. If a screen ever
 * appears to need one, the design has drifted.
 */

// --- D01 authentication ----------------------------------------------------

export const login = (email, password) =>
  client.post('/admin/login', { email, password }).then((r) => r.data)

export const logout = () => client.post('/admin/logout')

export const me = () => client.get('/admin/me').then((r) => r.data)

// --- D02 analytics ---------------------------------------------------------

export const overview = ({ days = 30, granularity = 'day' } = {}) =>
  client
    .get('/admin/analytics/overview', { params: { days, granularity } })
    .then((r) => r.data)

// --- D03 hotspot clusters --------------------------------------------------

export const clusters = ({ days = 365, precision = 3 } = {}) =>
  client
    .get('/admin/hotspots/clusters', { params: { days, precision } })
    .then((r) => r.data)

// --- D04 report list -------------------------------------------------------

export const listReports = ({
  search,
  dateFrom,
  dateTo,
  page = 1,
  pageSize = 25,
} = {}) =>
  client
    .get('/admin/reports', {
      params: {
        search: search || undefined,
        date_from: dateFrom || undefined,
        date_to: dateTo || undefined,
        page,
        page_size: pageSize,
      },
    })
    .then((r) => r.data)

/** FR13. The browser downloads the filtered set as a CSV. */
export const exportCsvUrl = ({ search, dateFrom, dateTo } = {}) => {
  const params = new URLSearchParams()
  if (search) params.set('search', search)
  if (dateFrom) params.set('date_from', dateFrom)
  if (dateTo) params.set('date_to', dateTo)
  return `/admin/reports/export.csv?${params.toString()}`
}

export const downloadCsv = async (filters) => {
  const response = await client.get(exportCsvUrl(filters), {
    responseType: 'blob',
  })
  const url = URL.createObjectURL(response.data)
  const link = document.createElement('a')
  link.href = url
  link.download = `scope-reports-${new Date().toISOString().slice(0, 10)}.csv`
  document.body.appendChild(link)
  link.click()
  link.remove()
  URL.revokeObjectURL(url)
}

// --- D05 report detail -----------------------------------------------------

export const getReport = (reportId) =>
  client.get(`/admin/reports/${reportId}`).then((r) => r.data)

// --- D06 infographics ------------------------------------------------------

export const listInfographics = () =>
  client.get('/admin/infographics').then((r) => r.data)

/** Replace a slot's title and, optionally, its image. Publishing into an
 *  empty slot requires an image. */
export const updateInfographic = (slot, { title, image }) => {
  const form = new FormData()
  form.append('title', title)
  if (image) form.append('image', image)
  return client
    .put(`/admin/infographics/${slot}`, form)
    .then((r) => r.data)
}

/** Empty a slot. The slot itself stays and can be published into again. */
export const deleteInfographic = (slot) =>
  client.delete(`/admin/infographics/${slot}`).then((r) => r.data)
