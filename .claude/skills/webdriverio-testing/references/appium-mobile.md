# Mobile via Appium — as a WDIO operating mode

Load this when the suite's capabilities carry `appium:` options or
`platformName: iOS|Android`. Appium is the driver WDIO talks to; the spec style,
TC-IDs, retry discipline, and evidence rules from the parent skill do not
change. What changes: where the app under test lives, the two context problem,
and gestures.

## Setup

- Local runs typically use the `wdio-appium-service` in `wdio.conf.ts`; CI and
  device farms (BrowserStack, Sauce) are remote endpoints with credentials as
  **secret references** — never values (`.claude/rules/core/security.md`).
- Core capabilities: `platformName`, `appium:platformVersion`,
  `appium:deviceName`, and exactly one of `appium:app` (path/URL to the build —
  state where the artifact comes from in the project's PROJECT.md, not in the
  spec) or `appium:bundleId` / `appium:appPackage`+`appium:appActivity` for an
  installed app. `appium:noReset`/`appium:fullReset` decide test-data isolation —
  pick one deliberately per suite and record why in the config, because it
  changes what "clean state" means between specs.

## The two-context problem (the #1 mobile flake source)

Hybrid apps expose `NATIVE_APP` and one or more `WEBVIEW_*` contexts. Selectors
only resolve in the context they belong to:

- Switch explicitly (`browser.switchContext(...)`) and assert the context you
  landed in before interacting — an element lookup in the wrong context fails
  with a locator error that looks exactly like a broken selector.
- After actions that cross the boundary (login in webview → native permission
  dialog), wait for the expected context to appear instead of sleeping.
- Native system dialogs (permissions, push prompts) live in `NATIVE_APP` even
  when the flow is otherwise pure webview — budget for them on every
  fresh-install run; they never appear on subsequent launches.

## Gestures and input

- Use the W3C Actions API (`browser.action('pointer')...`) or Appium's
  `mobile:` commands (`mobile: swipe`, `mobile: scrollGesture`) — never
  coordinate-math helpers that assume a fixed viewport; device matrices break
  them.
- Deep links: `browser.execute('mobile: deepLink', { url, package })` (Android)
  / `mobile: openDeepLink` where supported — faster and more deterministic than
  driving a browser to redirect into the app.

## Evidence on mobile

Screenshots on failure plus the Appium server log excerpt for every FAIL (it
carries the real driver error the client stack truncates). Record device,
OS version, and app build in `execution_summary.json` notes — a mobile failure
without the device line is not reproducible.
