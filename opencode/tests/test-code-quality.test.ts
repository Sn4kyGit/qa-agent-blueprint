import { describe, expect, test } from "bun:test"
import { mkdtempSync, mkdirSync, readFileSync, writeFileSync } from "node:fs"
import { tmpdir } from "node:os"
import { join, resolve } from "node:path"
import { fileURLToPath } from "node:url"
import { loadQualityConfig, scanTestCode, scanTestFiles, SCAN_VERSION } from "../../.claude/scripts/qa-test-code-scan.mjs"
import qaBlueprint from "../plugins/qa-blueprint.ts"
import { fakeCtx, fileBefore } from "./fixtures/payloads.ts"

const root = resolve(fileURLToPath(new URL("../..", import.meta.url)))
const fixtures = join(root, ".claude/hooks/tests/fixtures/test-code")
const fixture = (name: string) => readFileSync(join(fixtures, name), "utf8")
const ids = (report: ReturnType<typeof scanTestCode>) => report.findings.map((item) => item.ruleId)

describe("test code scanner rules", () => {
  test("reports the high-precision rule set with locations", () => {
    const report = scanTestCode(fixture("violations.spec.ts"), { filePath: "tests/violations.spec.ts", config: false })
    for (const ruleId of [
      "no-dotenv", "fixed-sleep", "hardcoded-base-url", "xpath-selector", "brittle-selector",
      "observation-fixture-import", "missing-ac-title", "missing-tc-title", "disabled-test", "retry-override",
    ]) expect(ids(report)).toContain(ruleId)
    expect(report.findings.every((item) => item.line > 0 && item.column > 0)).toBe(true)
    expect(report.findings.every((item) => item.severity === "warning")).toBe(true)
    expect(report.version).toBe(SCAN_VERSION)
  })

  test("accepts stable Playwright code and documented disabled tests", () => {
    const report = scanTestCode(fixture("clean.spec.ts"), { filePath: "tests/clean.spec.ts", config: false })
    expect(report.findings).toEqual([])
    expect(report.diagnostics).toEqual([])
  })

  test("accepts WebdriverIO without imposing Playwright fixture imports", () => {
    const report = scanTestCode(fixture("clean.wdio.spec.ts"), { filePath: "tests/clean.wdio.spec.ts", framework: "webdriverio", config: false })
    expect(report.findings).toEqual([])
  })

  test("keeps uncertain matches at warning even under strict config", () => {
    const report = scanTestCode(fixture("uncertain.spec.ts"), {
      filePath: "tests/uncertain.spec.ts",
      strict: true,
      config: { rules: { "fixed-sleep": "error", "brittle-selector": "error", "missing-ac-title": "error", "missing-tc-title": "error" } },
    })
    expect(report.findings.length).toBeGreaterThan(0)
    expect(report.findings.every((item) => item.severity === "warning" && item.confidence !== "high")).toBe(true)
  })

  test("does not scan comments as executable code", () => {
    const report = scanTestCode("// page.waitForTimeout(100); page.goto('https://stage.invalid');\n", { filePath: "tests/a.spec.ts", fragment: true, config: false })
    expect(report.findings).toEqual([])
  })

  test("accepts environment URLs and condition-based waits", () => {
    const source = "test('AC1 / TC-A-001: ok', async ({ page }) => { await page.goto(process.env.STAGE_BASE_URL); await page.getByRole('status').waitFor(); });"
    expect(ids(scanTestCode(source, { filePath: "tests/a.spec.ts", config: false }))).toEqual([])
  })

  test("recognizes AC2 and AC-2 title forms", () => {
    for (const ac of ["AC2", "AC-2"]) {
      const report = scanTestCode(`test('${ac} / TC-CHK-001: works', () => {});`, { filePath: "tests/a.spec.ts", config: false })
      expect(ids(report)).not.toContain("missing-ac-title")
      expect(ids(report)).not.toContain("missing-tc-title")
    }
  })

  test("does not require metadata in fragment mode", () => {
    const report = scanTestCode("await page.waitForTimeout(10)", { filePath: "fragment.ts", fragment: true, config: false })
    expect(ids(report)).toEqual(["fixed-sleep"])
  })

  test("does not flag CI-conditional config retries", () => {
    const source = "export default { retries: process.env.CI ? 2 : 0, use: { baseURL: process.env.STAGE_BASE_URL } };"
    expect(scanTestCode(source, { filePath: "playwright.config.ts", config: false }).findings).toEqual([])
  })

  test("flags static nonzero config retries", () => {
    const report = scanTestCode("export default { retries: 2 };", { filePath: "playwright.config.ts", config: false })
    expect(ids(report)).toEqual(["retry-override"])
  })
})

describe("suppressions and reports", () => {
  test("moves reasoned inline suppressions to a separate stable collection", () => {
    const report = scanTestCode(fixture("suppressed.spec.ts"), { filePath: "tests/suppressed.spec.ts", config: false })
    expect(report.findings).toEqual([])
    expect(report.suppressed.map((item) => item.ruleId).sort()).toEqual(["fixed-sleep", "missing-ac-title", "missing-tc-title"])
    expect(report.suppressed.every((item) => item.suppressionLine > 0)).toBe(true)
  })

  test("no-suppressions restores findings", () => {
    const report = scanTestCode(fixture("suppressed.spec.ts"), { filePath: "tests/suppressed.spec.ts", config: false, noSuppressions: true })
    expect(report.suppressed).toEqual([])
    expect(report.findings.length).toBe(3)
  })

  test("rejects unreasoned suppressions with a diagnostic", () => {
    const source = "// qa-scan-disable-next-line fixed-sleep\nawait page.waitForTimeout(10);"
    const report = scanTestCode(source, { filePath: "tests/a.spec.ts", fragment: true, config: false })
    expect(ids(report)).toEqual(["fixed-sleep"])
    expect(report.diagnostics.some((item) => item.severity === "warning")).toBe(true)
  })

  test("sorts findings deterministically without source excerpts", () => {
    const source = "await page.goto('https://private.example.test');\nawait page.waitForTimeout(10);"
    const first = scanTestCode(source, { filePath: "tests/z.spec.ts", fragment: true, config: false })
    const second = scanTestCode(source, { filePath: "tests/z.spec.ts", fragment: true, config: false })
    expect(first).toEqual(second)
    expect(ids(first)).toEqual(["hardcoded-base-url", "fixed-sleep"])
    const serialized = JSON.stringify(first)
    expect(serialized).not.toContain("private.example.test")
    expect(serialized).not.toContain("waitForTimeout(10)")
    expect(serialized).not.toContain("excerpt")
  })
})

describe("config and file APIs", () => {
  test("loads the nearest strict config and writeGate", () => {
    const dir = mkdtempSync(join(tmpdir(), "qa-quality-config-"))
    mkdirSync(join(dir, "suite/tests"), { recursive: true })
    writeFileSync(join(dir, ".qa-test-quality.json"), JSON.stringify({ version: 1, strict: true, writeGate: true, rules: { "fixed-sleep": "error" } }))
    const config = loadQualityConfig(join(dir, "suite/tests/example.spec.ts"))
    expect(config.strict).toBe(true)
    expect(config.writeGate).toBe(true)
    expect(config.rules["fixed-sleep"]).toBe("error")
    expect(config.configPath).toBe(join(dir, ".qa-test-quality.json"))
  })

  test("invalid config produces diagnostics instead of throwing", () => {
    const dir = mkdtempSync(join(tmpdir(), "qa-quality-invalid-"))
    writeFileSync(join(dir, ".qa-test-quality.json"), "not json")
    const config = loadQualityConfig(dir)
    expect(config.writeGate).toBe(false)
    expect(config.diagnostics.some((item) => item.severity === "error")).toBe(true)
  })

  test("rule overrides can disable or elevate high-confidence findings", () => {
    const source = "await page.waitForTimeout(10);"
    const off = scanTestCode(source, { filePath: "a.ts", fragment: true, config: { rules: { "fixed-sleep": "off" } } })
    const error = scanTestCode(source, { filePath: "a.ts", fragment: true, config: { rules: { "fixed-sleep": "error" } } })
    expect(off.findings).toEqual([])
    expect(error.findings[0].severity).toBe("error")
  })

  test("scanTestFiles aggregates sorted source files", () => {
    const dir = mkdtempSync(join(tmpdir(), "qa-quality-files-"))
    writeFileSync(join(dir, "b.spec.ts"), "await page.waitForTimeout(10);")
    writeFileSync(join(dir, "a.spec.ts"), "await page.goto('https://stage.example.test');")
    const report = scanTestFiles([dir], { config: false, fragment: true })
    expect(report.summary.files).toBe(2)
    expect(report.findings.map((item) => item.file)).toEqual(report.findings.map((item) => item.file).sort())
  })

  test("missing files are operational diagnostics", () => {
    const report = scanTestFiles([join(tmpdir(), "definitely-missing-qa-quality.spec.ts")], { config: false })
    expect(report.diagnostics.some((item) => item.severity === "error")).toBe(true)
  })
})

describe("opencode write gate", () => {
  async function gatedHooks(strict: boolean) {
    const dir = mkdtempSync(join(tmpdir(), "qa-quality-plugin-"))
    if (strict) {
      writeFileSync(join(dir, ".qa-test-quality.json"), JSON.stringify({
        version: 1,
        writeGate: true,
        strict: true,
        framework: "playwright",
        rules: { "fixed-sleep": "error" },
      }))
    }
    const { ctx } = fakeCtx(dir)
    return qaBlueprint.server(ctx as never)
  }

  test("blocks the same fixed sleep as the Claude write hook", async () => {
    const hooks = await gatedHooks(true)
    const call = fileBefore("write", "tests/bad.spec.ts", "await page.waitForTimeout(10)")
    await expect(hooks["tool.execute.before"](call.input as never, call.output as never)).rejects.toThrow("fixed-sleep")
  })

  test("allows clean code through the active gate", async () => {
    const hooks = await gatedHooks(true)
    const call = fileBefore("write", "tests/good.spec.ts", "test('AC1 / TC-CHK-001: works', () => {});")
    await expect(hooks["tool.execute.before"](call.input as never, call.output as never)).resolves.toBeUndefined()
  })

  test("keeps legacy suites without quality config unaffected", async () => {
    const hooks = await gatedHooks(false)
    const call = fileBefore("write", "tests/legacy.spec.ts", "await page.waitForTimeout(10)")
    await expect(hooks["tool.execute.before"](call.input as never, call.output as never)).resolves.toBeUndefined()
  })
})
