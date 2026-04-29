import { useState, useRef, useCallback } from 'react'
import './App.css'

// Inline SVG icons — no external dependency needed
const UploadIcon = () => (
  <svg width="28" height="28" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round">
    <path d="M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4"/>
    <polyline points="17 8 12 3 7 8"/>
    <line x1="12" y1="3" x2="12" y2="15"/>
  </svg>
)

const PdfIcon = () => (
  <svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round">
    <path d="M14 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V8z"/>
    <polyline points="14 2 14 8 20 8"/>
    <line x1="9" y1="13" x2="15" y2="13"/>
    <line x1="9" y1="17" x2="13" y2="17"/>
  </svg>
)

const formatSize = (bytes) => {
  if (bytes < 1024) return `${bytes} B`
  if (bytes < 1024 * 1024) return `${(bytes / 1024).toFixed(1)} KB`
  return `${(bytes / (1024 * 1024)).toFixed(1)} MB`
}

function App() {
  const [file, setFile] = useState(null)
  const [isDragging, setIsDragging] = useState(false)
  const [isSubmitting, setIsSubmitting] = useState(false)
  const [status, setStatus] = useState(null) // 'success' | 'error' | null
  const inputRef = useRef(null)

  const handleDragOver = useCallback((e) => {
    e.preventDefault()
    setIsDragging(true)
  }, [])

  const handleDragLeave = useCallback((e) => {
    e.preventDefault()
    setIsDragging(false)
  }, [])

  const handleDrop = useCallback((e) => {
    e.preventDefault()
    setIsDragging(false)
    const dropped = e.dataTransfer.files[0]
    if (dropped?.type === 'application/pdf') {
      setFile(dropped)
      setStatus(null)
    }
  }, [])

  const handleFileChange = (e) => {
    const selected = e.target.files[0]
    if (selected) {
      setFile(selected)
      setStatus(null)
    }
  }

  const clearFile = (e) => {
    // Stop click from bubbling up to the drop zone and reopening the file picker
    e.stopPropagation()
    setFile(null)
    setStatus(null)
    if (inputRef.current) inputRef.current.value = ''
  }

  const handleSubmit = async () => {
    if (!file || isSubmitting) return
    setIsSubmitting(true)
    setStatus(null)

    try {
      const formData = new FormData()
      formData.append('file', file)
      formData.append('title', file.name.replace(/\.pdf$/i, ''))

      const res = await fetch('/api/books/upload', { method: 'POST', body: formData })
      setStatus(res.ok ? 'success' : 'error')
      if (res.ok) {
        setFile(null)
        if (inputRef.current) inputRef.current.value = ''
      }
    } catch {
      setStatus('error')
    } finally {
      setIsSubmitting(false)
    }
  }

  return (
    <div className="app">
      <div className="bg-glow" />

      <header className="header">
        <div className="eyebrow">Zühlke · Digital Archive</div>
        <h1>Digital Library</h1>
        <p className="subtitle">Submit a PDF to add it to the collection</p>
      </header>

      <main className="main">
        <div className="upload-row">
          {/* Drop zone — click to open picker, or drag & drop */}
          <div
            className={`drop-zone${isDragging ? ' is-dragging' : ''}${file ? ' has-file' : ''}`}
            onDragOver={handleDragOver}
            onDragLeave={handleDragLeave}
            onDrop={handleDrop}
            onClick={() => !file && inputRef.current?.click()}
            role="button"
            tabIndex={0}
            onKeyDown={(e) => e.key === 'Enter' && !file && inputRef.current?.click()}
            aria-label="Upload PDF"
          >
            <input
              ref={inputRef}
              type="file"
              accept="application/pdf,.pdf"
              onChange={handleFileChange}
              style={{ display: 'none' }}
            />

            {file ? (
              <div className="file-selected">
                <span className="file-icon"><PdfIcon /></span>
                <div className="file-meta">
                  <span className="file-name">{file.name}</span>
                  <span className="file-size">{formatSize(file.size)}</span>
                </div>
                <button className="clear-btn" onClick={clearFile} aria-label="Remove file">×</button>
              </div>
            ) : (
              <div className="upload-prompt">
                <span className="upload-icon"><UploadIcon /></span>
                <span className="prompt-text">
                  Drop a PDF here or <em>click to browse</em>
                </span>
              </div>
            )}
          </div>

          <button
            className={`submit-btn${isSubmitting ? ' is-loading' : ''}`}
            onClick={handleSubmit}
            disabled={!file || isSubmitting}
          >
            {isSubmitting ? (
              <span className="spinner" />
            ) : (
              'Submit'
            )}
          </button>
        </div>

        {status === 'success' && (
          <p className="status success">Book submitted successfully — it is being processed.</p>
        )}
        {status === 'error' && (
          <p className="status error">Upload failed. Check the service and try again.</p>
        )}
      </main>

      <footer className="footer">
        <span>PDF files only · Max 50 MB</span>
      </footer>
    </div>
  )
}

export default App
