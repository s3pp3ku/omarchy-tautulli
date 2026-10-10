// Parsing helpers for Tautulli's get_activity response. Kept out of the
// panel so the HTTP/QML side never has to think about field names.

function parseActivity(raw) {
  var parsed = JSON.parse(raw)
  var response = parsed && parsed.response ? parsed.response : null
  if (!response || response.result !== "success") {
    var message = response && response.message ? String(response.message) : "Unexpected response"
    return { ok: false, error: message, streamCount: 0, sessions: [] }
  }
  var data = response.data || {}
  var rawSessions = data.sessions || []
  var sessions = []
  for (var i = 0; i < rawSessions.length; i++) sessions.push(parseSession(rawSessions[i]))
  return {
    ok: true,
    error: "",
    streamCount: parseInt(data.stream_count, 10) || sessions.length,
    sessions: sessions
  }
}

function parseSession(s) {
  s = s || {}
  var mediaType = String(s.media_type || "")
  var durationMs = parseInt(s.duration, 10) || 0
  var offsetMs = parseInt(s.view_offset, 10) || 0
  return {
    sessionKey: String(s.session_key || ""),
    user: String(s.friendly_name || s.user || "Unknown"),
    title: String(s.full_title || s.title || "Unknown title"),
    episodeTag: episodeTag(mediaType, s.parent_media_index, s.media_index),
    mediaType: mediaType,
    year: String(s.year || ""),
    library: String(s.library_name || ""),
    state: String(s.state || "playing"),
    progressPercent: Math.max(0, Math.min(100, parseInt(s.progress_percent, 10) || 0)),
    remaining: formatRemaining(durationMs, offsetMs),
    player: String(s.player || ""),
    product: String(s.product || ""),
    quality: formatQuality(s),
    bandwidth: formatBandwidth(s.bandwidth),
    ipAddress: String(s.ip_address || ""),
    // Prefer the show's poster over the episode thumb — it's the
    // recognizable artwork; the per-episode thumb is often just a still.
    posterPath: String(s.grandparent_thumb || s.thumb || "")
  }
}

function episodeTag(mediaType, season, episode) {
  if (mediaType !== "episode") return ""
  var s = parseInt(season, 10)
  var e = parseInt(episode, 10)
  if (isNaN(s) || isNaN(e)) return ""
  return "S" + String(s).padStart(2, "0") + "E" + String(e).padStart(2, "0")
}

function formatQuality(s) {
  var decision = String(s.transcode_decision || "").toLowerCase()
  var label = decision === "transcode" ? "Transcode" : decision === "copy" ? "Direct Stream" : decision === "direct play" ? "Direct Play" : ""
  var resolution = String(s.stream_video_resolution || s.video_resolution || "")
  var codec = String(s.stream_video_codec || s.video_codec || "").toUpperCase()
  var parts = [label, resolution ? resolution + "p" : "", codec].filter(function(v) { return v !== "" })
  return parts.join(" • ")
}

function formatBandwidth(kbps) {
  var n = parseInt(kbps, 10)
  if (!n) return ""
  return n >= 1000 ? (n / 1000).toFixed(1) + " Mbps" : n + " Kbps"
}

function formatRemaining(durationMs, offsetMs) {
  var remainingMs = durationMs - offsetMs
  if (!durationMs || remainingMs <= 0) return ""
  var totalMinutes = Math.round(remainingMs / 60000)
  var hours = Math.floor(totalMinutes / 60)
  var minutes = totalMinutes % 60
  if (hours > 0) return hours + "h " + minutes + "m left"
  return minutes + "m left"
}
