const test = require("node:test")
const assert = require("node:assert/strict")
const fs = require("node:fs")
const path = require("node:path")

const Model = require("../Model.js")

const fixture = name => fs.readFileSync(path.join(__dirname, "fixtures", name), "utf8")
const data = Model.parseData(fixture("site.json"))

test("parseData reads sync.sh's output and keeps each source's combined rating", () => {
  assert.equal(data.version, "fixture")
  assert.equal(data.characters.length, 100)
  assert.equal(data.roles.length, 28)
  assert.equal(data.selfnames.length, 73)
  assert.equal(data.sourceCount, 87)
  assert.equal(data.combined["2001-a-space-odyssey"], 86)
  assert.equal(data.combined["foundation-isaac-asimov"], null)
})

test("parseData refuses anything that isn't the site's data", () => {
  assert.equal(Model.parseData(""), null)
  assert.equal(Model.parseData("<html>"), null)
  assert.equal(Model.parseData("null"), null)
  assert.equal(Model.parseData(JSON.stringify({ characters: [], roles: [], selfnames: [], sources: [] })), null)
  assert.equal(Model.parseData(JSON.stringify({ characters: [{ slug: "x" }], roles: [], selfnames: [], sources: [] })), null)
  assert.equal(Model.parseData(JSON.stringify({ characters: [], roles: [] })), null)
  const odd = Model.parseData(JSON.stringify({
    characters: [{ slug: "x", name: "X", overview: "A bot.", archetypes: [] }, null],
    roles: [{ id: "r" }], selfnames: [{ name: "Sage" }, 7], sources: [{ slug: "s", combined: "high" }, null]
  }))
  assert.equal(odd.version, "")
  assert.equal(odd.characters.length, 1)
  assert.equal(odd.roles.length, 0)
  assert.equal(odd.selfnames.length, 1)
  assert.equal(odd.combined.s, null)
})

test("siteVersion reads the content hash the site's build stamps on app.js", () => {
  assert.equal(Model.siteVersion('<script src="app.js?v=fc56f8805b" type="module"></script>'), "fc56f8805b")
  assert.equal(Model.siteVersion("<html></html>"), "")
  assert.equal(Model.siteVersion(undefined), "")
})

test("the Bot of the Day is a bot, the same all day and for everyone", () => {
  const pool = Model.botPool(data.characters)
  assert.equal(pool.length, 62)
  assert.ok(pool.every(c => c.type === "ai"))
  const slugs = pool.map(c => c.slug)
  assert.deepEqual(slugs, slugs.slice().sort())
  // The data's order doesn't matter.
  assert.equal(Model.botOfDay(Model.botPool(data.characters.slice().reverse()), "2026-10-28").slug, Model.botOfDay(pool, "2026-10-28").slug)
  assert.equal(Model.botOfDay(pool, "2026-10-28").slug, "wall-e")
  assert.equal(Model.botOfDay(pool, "2026-10-29").slug, "david-8")
  const week = ["01", "02", "03", "04", "05", "06", "07"].map(d => Model.botOfDay(pool, "2026-11-" + d).slug)
  assert.ok(new Set(week).size >= 6)
  assert.equal(Model.botOfDay([], "2026-10-28"), null)
  assert.equal(Model.botOfDay(null, "2026-10-28"), null)
})

test("dayKey is the local calendar date", () => {
  assert.equal(Model.dayKey(new Date(2026, 9, 28, 23, 59)), "2026-10-28")
  assert.equal(Model.dayKey(new Date(2026, 0, 5, 0, 1)), "2026-01-05")
})

test("hash is FNV-1a", () => {
  assert.equal(Model.hash(""), 0x811c9dc5)
  assert.equal(Model.hash("a"), 0xe40c292c)
  assert.equal(Model.hash("foobar"), 0xbf9cf968)
})

test("another never repeats the bot on show", () => {
  const pool = Model.botPool(data.characters)
  const now = pool[0]
  for (const r of [0, 0.25, 0.5, 0.999]) assert.notEqual(Model.another(pool, now, r).slug, now.slug)
  assert.equal(Model.another(pool, now, 0).slug, pool[1].slug)
  assert.equal(Model.another(pool, null, 0).slug, pool[0].slug)
  assert.equal(Model.another([now], now, 0.5).slug, now.slug)
  assert.equal(Model.another([], now, 0.5), null)
})

test("names copy without their brackets, and lines and links read right", () => {
  const hal = data.characters.find(c => c.slug === "hal-9000")
  assert.equal(Model.shortName("Murderbot (SecUnit)"), "Murderbot")
  assert.equal(Model.shortName("Johnny 5 (Number 5)"), "Johnny 5")
  assert.equal(Model.shortName("HAL 9000"), "HAL 9000")
  assert.equal(Model.sourceLine(hal), "2001: A Space Odyssey · Film · 1968")
  assert.equal(Model.sourceLine({ sourceTitle: "Book", medium: "other" }), "Book")
  assert.equal(Model.sourceLine(null), "")
  assert.equal(Model.characterUrl(hal), "https://namemyai.org/#/bot/hal-9000")
  assert.equal(Model.suggestUrl(" write my emails "), "https://namemyai.org/#/suggest?q=write%20my%20emails")
  assert.equal(Model.suggestUrl(""), "https://namemyai.org/#/suggest")
})

test("settings fall back to their defaults", () => {
  assert.equal(Model.labelStyle("name"), "name")
  assert.equal(Model.labelStyle("race"), "icon")
  assert.equal(Model.switchedOn(true), true)
  assert.equal(Model.switchedOn(undefined), true)
  assert.equal(Model.switchedOn(false), false)
  assert.equal(Model.switchedOn("false"), false)
})

test("a job is read from its label, keywords or a near miss", () => {
  const role = q => (Model.findRole(data.roles, q) || {}).label
  assert.equal(role("coding"), "Coding / Engineering")
  assert.equal(role("Research"), "Research")
  assert.equal(role("reserch"), "Research")
  assert.equal(role("write my emails"), "Writing & Editing")
  assert.equal(role("personal assistant"), "Chief of Staff")
  assert.equal(role("devo"), undefined)
  assert.equal(role("xyzzy"), undefined)
  assert.equal(role(""), undefined)
  assert.equal(Model.lev("abc", "abcde"), 9)
  assert.equal(Model.lev("teh", "the"), 1)
  assert.deepEqual(Model.tok("The bot for my Travel plans"), ["travel", "plans"])
  assert.equal(Model.normQ(" C++ / C# coding! "), "c++ c# coding")
})

test("a story idea is matched as a phrase, not a job", () => {
  assert.deepEqual(Model.phraseSet(data, "time travel").slice(0, 2), ["time travel", "back in time"])
  assert.equal(Model.phraseSet(data, "travel"), null)
  assert.equal(Model.phraseSet(data, "customer support"), null)
  assert.equal(Model.phraseSet(data, "purple monkey"), null)
})

test("traitWord finds the overview's word for a matched trait", () => {
  const c = { overview: "A ship's computer that runs the ship's systems." }
  assert.equal(Model.traitWord(c, ["comput"]), "computer")
  assert.equal(Model.traitWord(c, ["ship"]), "ship")
  assert.equal(Model.traitWord(c, ["zzz"]), null)
  assert.equal(Model.traitWord({ overview: "" }, ["a"]), null)
})

// tests/fixtures/site-suggestions.json is what namemyai.org's own suggester
// listed for each query on 2026-10-28, and site.json holds every character
// in those lists, so the port has to rank them exactly as the site does.
test("suggestions match namemyai.org's, name for name and in order", () => {
  const site = JSON.parse(fixture("site-suggestions.json"))
  for (const q of Object.keys(site)) {
    assert.deepEqual(Model.suggest(data, q).list.map(c => c.name), site[q], q)
  }
})

test("suggest knows the job it matched, and nothing for nothing", () => {
  assert.equal(Model.suggest(data, "coding").role.label, "Coding / Engineering")
  assert.equal(Model.suggest(data, "time travel").role, null)
  assert.equal(Model.suggest(data, "coding", 3).list.length, 3)
  assert.deepEqual(Model.suggest(data, "  "), { role: null, list: [] })
  assert.deepEqual(Model.suggest(null, "coding"), { role: null, list: [] })
  assert.deepEqual(Model.suggest(data, "xyzzy").list, [])
  // A name in the query counts as a keyword hit.
  assert.equal(Model.suggest(data, "multivac").list[0].slug, "multivac")
})

test("self-chosen names follow the job's theme, popular first", () => {
  const theme = q => Model.selfPick(data.selfnames, q).map(n => n.theme)
  assert.ok(theme("security").every(t => t === "strength"))
  assert.ok(theme("write my emails").every(t => t === "creativity"))
  assert.ok(theme("research").every(t => t === "wisdom"))
  assert.equal(Model.selfPick(data.selfnames, "coding").length, 6)
  assert.equal(Model.selfPick(data.selfnames, "coding", 2).length, 2)
  assert.deepEqual(Model.selfPick(data.selfnames, "security").map(n => n.name), ["Zero", "Calder", "Delta", "Synth", "Aurum", "Kairo"])
  assert.deepEqual(Model.selfPick(data.selfnames, "xyzzy").map(n => n.name), ["Sage", "Lex", "Nova", "Prism", "Zelda", "Caelum"])
  // Fewer themed names than asked for tops up from the rest.
  const few = [{ name: "A", theme: "wisdom" }, { name: "B", theme: "quirky", popular: true }]
  assert.deepEqual(Model.selfPick(few, "research").map(n => n.name), ["A", "B"])
  assert.equal(Model.hue(""), 7)
})
