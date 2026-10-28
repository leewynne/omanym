const test = require("node:test")
const assert = require("node:assert/strict")
const fs = require("node:fs")
const http = require("node:http")
const os = require("node:os")
const path = require("node:path")
const { execFile } = require("node:child_process")

const script = path.join(__dirname, "..", "sync.sh")
const fixture = JSON.parse(fs.readFileSync(path.join(__dirname, "fixtures", "site.json"), "utf8"))

// A stand-in for namemyai.org: a home page carrying the version, and the
// four data files. Records each request's path.
function fakeSite() {
  const site = {
    version: "aaa111",
    files: {
      "/data/characters.json": JSON.stringify(fixture.characters),
      "/data/sources.json": JSON.stringify(fixture.sources.map(s => ({ slug: s.slug, title: "x", combined: s.combined, ratings: {} }))),
      "/data/roles.json": JSON.stringify(fixture.roles),
      "/selfnames.json": JSON.stringify(fixture.selfnames)
    },
    requests: []
  }
  site.server = http.createServer((req, res) => {
    const url = new URL(req.url, "http://x")
    site.requests.push(url.pathname)
    if (url.pathname === "/") {
      res.end('<script src="app.js?v=' + site.version + '" type="module"></script>')
    } else if (site.files[url.pathname] !== undefined && url.searchParams.get("v") === site.version) {
      res.end(site.files[url.pathname])
    } else {
      res.statusCode = 404
      res.end("not found")
    }
  })
  return new Promise(resolve => site.server.listen(0, "127.0.0.1", () => {
    site.url = "http://127.0.0.1:" + site.server.address().port
    resolve(site)
  }))
}

function sync(site, dir, args) {
  return new Promise(resolve => {
    execFile("bash", [script, dir].concat(args || []), { env: Object.assign({}, process.env, { OMANYM_SITE: site.url }) }, (err, stdout, stderr) => {
      resolve({ code: err ? err.code : 0, stdout, stderr })
    })
  })
}

function tempDir() {
  return fs.mkdtempSync(path.join(os.tmpdir(), "omanym-test-"))
}

test("downloads the data once, then only checks the version", async t => {
  const site = await fakeSite()
  t.after(() => site.server.close())
  const dir = path.join(tempDir(), "cache")

  const first = await sync(site, dir)
  assert.equal(first.code, 0)
  assert.equal(first.stderr, "")
  const data = JSON.parse(first.stdout)
  assert.equal(data.version, "aaa111")
  assert.equal(data.characters.length, fixture.characters.length)
  assert.deepEqual(Object.keys(data.sources[0]).sort(), ["combined", "slug"])
  assert.equal(fs.readFileSync(path.join(dir, "version"), "utf8"), "aaa111\n")
  assert.deepEqual(site.requests.sort(), ["/", "/data/characters.json", "/data/roles.json", "/data/sources.json", "/selfnames.json"])

  site.requests = []
  const second = await sync(site, dir)
  assert.equal(second.code, 0)
  assert.equal(JSON.parse(second.stdout).version, "aaa111")
  assert.deepEqual(site.requests, ["/"])

  site.version = "bbb222"
  site.requests = []
  const third = await sync(site, dir)
  assert.equal(JSON.parse(third.stdout).version, "bbb222")
  assert.equal(site.requests.length, 5)
  assert.deepEqual(fs.readdirSync(dir).filter(f => f.startsWith(".")), [])
})

test("--cached prints the copy without going online", async t => {
  const site = await fakeSite()
  t.after(() => site.server.close())
  const dir = tempDir()
  await sync(site, dir)
  site.requests = []
  const cached = await sync(site, dir, ["--cached"])
  assert.equal(cached.code, 0)
  assert.equal(JSON.parse(cached.stdout).version, "aaa111")
  assert.deepEqual(site.requests, [])
})

test("a broken download never replaces a good copy", async t => {
  const site = await fakeSite()
  t.after(() => site.server.close())
  const dir = tempDir()
  await sync(site, dir)

  site.version = "ccc333"
  site.files["/data/roles.json"] = "<html>Oops</html>"
  const broken = await sync(site, dir)
  assert.equal(broken.code, 0)
  assert.match(broken.stderr, /couldn't update/)
  assert.equal(JSON.parse(broken.stdout).version, "aaa111")
  assert.deepEqual(fs.readdirSync(dir).filter(f => f.startsWith(".")), [])

  site.files["/data/roles.json"] = "[]"
  const empty = await sync(site, dir)
  assert.match(empty.stderr, /couldn't update/)
  assert.equal(JSON.parse(empty.stdout).roles.length, fixture.roles.length)
})

test("offline: the cached copy, or nothing and exit 1", async t => {
  const site = await fakeSite()
  const dir = tempDir()
  await sync(site, dir)
  await new Promise(resolve => site.server.close(resolve))

  const offline = await sync(site, dir)
  assert.equal(offline.code, 0)
  assert.match(offline.stderr, /couldn't update/)
  assert.equal(JSON.parse(offline.stdout).version, "aaa111")

  const empty = await sync(site, tempDir())
  assert.equal(empty.code, 1)
  assert.equal(empty.stdout, "")
})

test("a home page without a version leaves the cache alone", async t => {
  const site = await fakeSite()
  t.after(() => site.server.close())
  site.version = ""
  const fresh = await sync(site, tempDir())
  assert.equal(fresh.code, 1)
  assert.match(fresh.stderr, /couldn't update/)
})
