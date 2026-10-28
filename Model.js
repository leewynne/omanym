// namemyai.org's data shaped for the bar and the popup: the Bot of the Day,
// and the site's own name suggester, ported so a job scores the same here as
// on the site. Pure functions only: the QML owns fetching, the cache and
// timers, so everything here runs under node for the tests.

var site = "https://namemyai.org"

var glyphs = {
  copy: String.fromCodePoint(0xF018F),    // nf-md-content_copy
  shuffle: String.fromCodePoint(0xF049D), // nf-md-shuffle_variant
  today: String.fromCodePoint(0xF00F6),   // nf-md-calendar_today
  open: String.fromCodePoint(0xF03CC),    // nf-md-open_in_new
  search: String.fromCodePoint(0xF0349),  // nf-md-magnify
  refresh: String.fromCodePoint(0xF0450), // nf-md-refresh
  check: String.fromCodePoint(0xF012C)    // nf-md-check
}

var labelStyles = ["icon", "name"]

var mediumLabels = { film: "Film", tv: "TV", books: "Books", games: "Games", comics: "Comics, Manga & Anime" }

// How many suggestions the popup lists, and self-chosen names under them.
var suggestionLimit = 8
var selfLimit = 6

function labelStyle(value) {
  return value === "name" ? "name" : "icon"
}

// On/off settings arrive as booleans, or as "false" from `omarchy bar set`
// without --json.
function switchedOn(value) {
  return value !== false && value !== "false"
}

// The site's build stamps a content hash on its scripts (app.js?v=…), so
// the home page says whether anything has changed since the last download.
function siteVersion(html) {
  var m = /app\.js\?v=([0-9a-f]+)/.exec(String(html || ""))
  return m ? m[1] : ""
}

// The dataset sync.sh prints: the site's characters, roles and self-chosen
// names, and each source's combined rating. Null unless it all looks right.
function parseData(text) {
  var raw
  try {
    raw = JSON.parse(String(text || ""))
  } catch (e) {
    return null
  }
  if (!raw || !Array.isArray(raw.characters) || !Array.isArray(raw.roles) || !Array.isArray(raw.selfnames) || !Array.isArray(raw.sources)) return null
  var chars = raw.characters.filter(function(c) {
    return c && typeof c.slug === "string" && typeof c.name === "string" && typeof c.overview === "string" && Array.isArray(c.archetypes)
  })
  if (chars.length === 0) return null
  var combined = {}
  raw.sources.forEach(function(s) {
    if (s && typeof s.slug === "string") combined[s.slug] = typeof s.combined === "number" ? s.combined : null
  })
  return {
    version: typeof raw.version === "string" ? raw.version : "",
    characters: chars,
    combined: combined,
    sourceCount: raw.sources.length,
    roles: raw.roles.filter(function(r) { return r && Array.isArray(r.keywords) && Array.isArray(r.picks) }),
    selfnames: raw.selfnames.filter(function(n) { return n && typeof n.name === "string" })
  }
}

// ---- Bot of the Day ----

function pad(n) {
  return (n < 10 ? "0" : "") + n
}

// The calendar day where the user is, so the bot changes at their midnight
// and everyone gets the same one on the same date.
function dayKey(date) {
  return date.getFullYear() + "-" + pad(date.getMonth() + 1) + "-" + pad(date.getDate())
}

// FNV-1a, 32 bit.
function hash(s) {
  var h = 0x811c9dc5
  for (var i = 0; i < s.length; i++) {
    h ^= s.charCodeAt(i)
    h = Math.imul(h, 0x01000193) >>> 0
  }
  return h >>> 0
}

// The bots: characters typed `ai`, in slug order so the site reordering
// its data doesn't change the pick.
function botPool(chars) {
  return (chars || []).filter(function(c) { return c.type === "ai" }).sort(function(a, b) {
    return a.slug < b.slug ? -1 : (a.slug > b.slug ? 1 : 0)
  })
}

function botOfDay(pool, key) {
  if (!pool || pool.length === 0) return null
  return pool[hash("omanym:" + key) % pool.length]
}

// Another bot, never the one on show. r is a random number in [0, 1).
function another(pool, current, r) {
  if (!pool || pool.length === 0) return null
  if (pool.length === 1) return pool[0]
  var others = pool.filter(function(c) { return !current || c.slug !== current.slug })
  return others[Math.min(others.length - 1, Math.floor(r * others.length))]
}

// ---- Names and links ----

// The name to copy: "Data (Star Trek)" is just Data.
function shortName(name) {
  return String(name || "").replace(/\s*\(.*?\)/g, "").trim()
}

// "2001: A Space Odyssey · Film · 1968"
function sourceLine(c) {
  if (!c) return ""
  var parts = []
  if (c.sourceTitle) parts.push(c.sourceTitle)
  if (mediumLabels[c.medium]) parts.push(mediumLabels[c.medium])
  if (c.year) parts.push(String(c.year))
  return parts.join(" · ")
}

function characterUrl(c) {
  return site + "/#/bot/" + encodeURIComponent(c.slug)
}

function suggestUrl(q) {
  var t = String(q || "").trim()
  return t ? site + "/#/suggest?q=" + encodeURIComponent(t) : site + "/#/suggest"
}

// ---- The suggester (src/app.js on namemyai.org) ----

function normQ(s) {
  return String(s || "").toLowerCase().replace(/[^a-z0-9+#]+/g, " ").trim()
}

var stopWords = ["the", "and", "for", "bot", "with", "that", "my"]

function tok(s) {
  return String(s || "").toLowerCase().split(/[^a-z0-9]+/).filter(function(w) {
    return w.length > 2 && stopWords.indexOf(w) < 0
  })
}

// Edit distance with transpositions, giving up past one edit.
function lev(a, b) {
  if (Math.abs(a.length - b.length) > 1) return 9
  var d = []
  for (var i = 0; i <= a.length; i++) d[i] = [i]
  for (var j = 1; j <= b.length; j++) d[0][j] = j
  for (i = 1; i <= a.length; i++) {
    for (j = 1; j <= b.length; j++) {
      d[i][j] = Math.min(d[i - 1][j] + 1, d[i][j - 1] + 1, d[i - 1][j - 1] + (a[i - 1] === b[j - 1] ? 0 : 1))
      if (i > 1 && j > 1 && a[i - 1] === b[j - 2] && a[i - 2] === b[j - 1]) d[i][j] = Math.min(d[i][j], d[i - 2][j - 2] + 1)
    }
  }
  return d[a.length][b.length]
}

// How well a query names a job: 100 exact, 70+ a keyword inside it, down to
// 35 for a near miss.
function intentScore(r, q) {
  var qt = q.split(" ")
  var best = 0
  var names = [r.label, r.id.replace(/-/g, " "), r.function].concat(r.keywords)
  for (var n = 0; n < names.length; n++) {
    var k = normQ(names[n])
    if (!k) continue
    if (k === q) best = Math.max(best, 100)
    else if ((" " + q + " ").indexOf(" " + k + " ") >= 0) best = Math.max(best, 70 + k.length)
    else if (q.length >= 3 && k.indexOf(q) === 0 && q.length / k.length >= 0.7) best = Math.max(best, 60)
    else {
      var kts = k.split(" ")
      for (var i = 0; i < qt.length; i++) {
        var t = qt[i]
        for (var j = 0; j < kts.length; j++) {
          var kt = kts[j]
          if (t.length >= 4 && kt.length >= 4 && lev(t, kt) <= 1) best = Math.max(best, 45)
          else if (t.length >= 4 && kt.length >= 4 && (kt.indexOf(t) === 0 || t.indexOf(kt) === 0)
            && Math.min(t.length, kt.length) / Math.max(t.length, kt.length) >= 0.7) best = Math.max(best, 35)
        }
      }
    }
  }
  return best
}

function findRole(roles, q) {
  q = normQ(q)
  if (!q) return null
  var best = null
  var bestScore = 0
  for (var i = 0; i < roles.length; i++) {
    var s = intentScore(roles[i], q)
    if (s > bestScore) {
      bestScore = s
      best = roles[i]
    }
  }
  return bestScore >= 35 ? best : null
}

var phrases = {
  "time travel": ["time travel", "back in time", "from the future", "time lord", "time machine", "travels time", "sent back to 19"],
  "space travel": ["spaceship", "starship", "space station", "travels time and space"]
}

function flat(t) {
  return t.toLowerCase().replace(/-/g, " ")
}

// A multi-word query that reads as a story idea rather than a job, like
// "time travel", matched as a phrase against the overviews.
function phraseSet(data, q) {
  var p = normQ(q)
  if (p.split(" ").length < 2) return null
  var alts = phrases[p] || [p]
  var n = data.characters.filter(function(c) {
    return alts.some(function(a) { return flat(c.overview).indexOf(a) >= 0 })
  }).length
  var exact = data.roles.some(function(r) {
    return r.keywords.some(function(k) { return normQ(k) === p })
  })
  return n >= 2 && !exact ? alts : null
}

function traitWord(c, stems) {
  var ws = c.overview.toLowerCase().match(/[a-z][a-z'-]+/g) || []
  for (var i = 0; i < stems.length; i++) {
    for (var j = 0; j < ws.length; j++) {
      if (ws[j].indexOf(stems[i]) === 0) return ws[j].replace(/'s?$/, "")
    }
  }
  return null
}

function isVillain(c) {
  return c.archetypes.some(function(a) { return /Villain|Overlord|Destroyer/.test(a) })
}

// Ranks every character for what the bot will do, as the site does: the
// job's hand picks, shared archetypes and traits, then plain keyword hits,
// with villains nudged down and well-rated sources nudged up.
function suggest(data, q, limit) {
  var query = String(q || "").trim()
  if (!data || !query) return { role: null, list: [] }
  var ph = phraseSet(data, query)
  var role = ph ? null : findRole(data.roles, query)
  var words = ph ? [] : tok(query).filter(function(w) {
    return !role || !role.keywords.some(function(k) { return normQ(k).split(" ").indexOf(w) >= 0 })
  })
  var out = []
  data.characters.forEach(function(c) {
    var s = 0
    var am = []
    var tw = null
    var text = (c.overview + " " + c.archetypes.join(" ")).toLowerCase()
    var pick = role ? role.picks.indexOf(c.slug) : -1
    if (role) {
      if (pick >= 0) s += 20 - pick
      am = c.archetypes.filter(function(a) { return role.archetypes.indexOf(a) >= 0 })
      s += 6 * am.length
      var hits = (role.traits || []).filter(function(t) { return text.indexOf(t) >= 0 })
      s += 3 * Math.min(3, hits.length)
      tw = hits.length ? traitWord(c, hits) : null
    }
    // A hand pick with nothing else in common loses most of its boost.
    if (pick >= 0 && !am.length && !tw) s -= Math.round((20 - pick) * 0.6)
    if (ph) {
      var hit = ph.filter(function(a) { return flat(c.overview).indexOf(a) >= 0 })[0]
      if (hit) {
        s += 12
        tw = hit
      }
    }
    var wm = words.filter(function(w) {
      var st = w.length > 6 ? w.slice(0, Math.max(6, Math.floor(w.length * 0.7))) : w
      return new RegExp("\\b" + st + (w.length > 6 ? "" : "(s|es)?\\b"), "i").test(text) || c.name.toLowerCase().indexOf(w) >= 0
    })
    if (wm.length) s += 4 * wm.length
    if (s <= 0) return
    if (isVillain(c)) s -= 3
    var combined = data.combined[c.source]
    if (combined) s += combined / 100
    out.push({ character: c, score: s })
  })
  out.sort(function(a, b) {
    return b.score - a.score || a.character.name.localeCompare(b.character.name)
  })
  return { role: role, list: out.slice(0, limit || suggestionLimit).map(function(x) { return x.character }) }
}

// Seeded hue, as the site's: the same query always shuffles the same way.
function hue(s) {
  return Array.from(s).reduce(function(a, ch) { return (a * 31 + ch.charCodeAt(0)) % 360 }, 7)
}

// Names AIs chose for themselves, themed by the job: creative work gets
// creative names, ops and security strong ones, research wise ones.
function selfPick(selfnames, q, limit) {
  var s = String(q || "").toLowerCase()
  var th = /creat|writ|design|art|music|content|social/.test(s) ? "creativity"
    : /secur|guard|ops|devops|code|engineer|data|finance/.test(s) ? "strength"
    : /research|tutor|learn|teach|advis|legal|health|support/.test(s) ? "wisdom" : ""
  var themed = selfnames.filter(function(n) { return !th || n.theme === th })
  var seed = hue(s + th)
  function rank(list) {
    return list.map(function(n, i) {
      return { n: n, i: i, k: (i * 37 + seed) % 97 - (n.popular ? 50 : 0) }
    }).sort(function(a, b) { return a.k - b.k || a.i - b.i }).map(function(x) { return x.n })
  }
  var rest = selfnames.filter(function(n) { return themed.indexOf(n) < 0 })
  return rank(themed).concat(rank(rest)).slice(0, limit || selfLimit)
}

if (typeof module !== "undefined") {
  module.exports = {
    site: site,
    glyphs: glyphs,
    labelStyles: labelStyles,
    mediumLabels: mediumLabels,
    suggestionLimit: suggestionLimit,
    selfLimit: selfLimit,
    labelStyle: labelStyle,
    switchedOn: switchedOn,
    siteVersion: siteVersion,
    parseData: parseData,
    dayKey: dayKey,
    hash: hash,
    botPool: botPool,
    botOfDay: botOfDay,
    another: another,
    shortName: shortName,
    sourceLine: sourceLine,
    characterUrl: characterUrl,
    suggestUrl: suggestUrl,
    normQ: normQ,
    tok: tok,
    lev: lev,
    intentScore: intentScore,
    findRole: findRole,
    phraseSet: phraseSet,
    traitWord: traitWord,
    suggest: suggest,
    hue: hue,
    selfPick: selfPick
  }
}
