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
  return {
    sessionKey: String(s.session_key || ""),
    user: String(s.friendly_name || s.user || "Unknown"),
    title: String(s.full_title || s.title || "Unknown title"),
    state: String(s.state || "playing"),
    progressPercent: Math.max(0, Math.min(100, parseInt(s.progress_percent, 10) || 0)),
    player: String(s.player || ""),
    platform: String(s.platform || ""),
    quality: formatQuality(s),
    location: String(s.location || "").toUpperCase(),
    ipAddress: String(s.ip_address || "")
  }
}

function formatQuality(s) {
  var decision = String(s.transcode_decision || "").toLowerCase()
  var label = decision === "transcode" ? "Transcode" : decision === "copy" ? "Direct Stream" : decision === "direct play" ? "Direct Play" : ""
  var resolution = String(s.stream_video_resolution || s.video_resolution || "")
  if (label && resolution) return label + " • " + resolution
  return label || resolution || ""
}
