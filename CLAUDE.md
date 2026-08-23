# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

xRate is a native macOS currency converter: SwiftUI + Swift 6, Xcode project (no
SPM/CocoaPods), deployment target macOS 26.0, sandboxed with network-client
entitlement only. Bundle id `com.fono.xRate`.

## Commands

```bash
# Test (builds both targets)
xcodebuild -project xRate.xcodeproj -scheme xRate -destination 'platform=macOS' test

# Single test / single class
xcodebuild -project xRate.xcodeproj -scheme xRate -destination 'platform=macOS' \
  test -only-testing:xRateTests/ConverterModelTests/testFormatRule

# Build
xcodebuild -project xRate.xcodeproj -scheme xRate -configuration Release -destination 'platform=macOS' build
```

`xcodebuild` on this machine prints CoreSimulator "out of date" warnings at
startup — harmless for a macOS destination.

**The `xRate.app` at the repo root is the user's Dock app.** It is gitignored and
is *not* updated by a build. After a user-visible change, quit running instances,
build Release, and `ditto` the product over that path — same path and bundle id
keep the Dock tile and the sandbox container (saved currencies/base/amount).

**Adding a Swift file requires hand-editing `project.pbxproj`.** It is written
by hand with sequential fake IDs (`FR…`/`BF…` file refs and build files, `GR…`
groups, `PH…` phases), not Xcode-managed synchronized folders. A new file needs
four entries: `PBXFileReference`, `PBXBuildFile`, its group's `children`, and the
target's Sources phase (`PH…A1` = app, `PH…A4` = tests). Verify with
`plutil -lint xRate.xcodeproj/project.pbxproj`.

## Architecture

`ConverterModel` (`@Observable @MainActor`) is the whole app's state. Everything
else is a view or a pure helper.

**One amount, many rows.** `ConverterModel.amount: Double` is the single numeric
source of truth and is always expressed in `baseCode`. Each `CurrencyRow` renders
that same amount converted into its own currency. Typing in a row therefore
*makes that row the base* (`applyInput` → `setBase`) before storing the value —
which is why editing any row silently changes `baseCode`, and why the base row is
always the one being edited. Conversion goes through the snapshot's anchor
currency (`convert`: from → anchor → to), so `rates` need not be keyed to
`baseCode`.

**Persistence is `UserDefaults` via `didSet`.** `currencies`, `baseCode`,
`amount` and `snapshot` each persist on assignment under `xrate.*` keys
(`ConverterModel.Keys`). Transient state (`errorMessage`, `isLoading`,
`availableCurrencies`, `expressionResult`) deliberately is not. `init` takes a
`UserDefaults` so tests can inject an isolated suite. The legacy
`xrate.amountText` string key is migrated on load — don't reintroduce it.

**`AmountField` is AppKit, and its focus code is protected.** It is an
`NSViewRepresentable` around `NSTextField` that takes a `Double` down and pushes
raw text up; it never round-trips text through a binding. `updateNSView` rewrites
`stringValue` only when the field is unfocused or on the focus-gain edge, so
typing is never clobbered by re-renders — and so an unfocused field always
re-renders from the model, which is how a typed expression collapses to its
result for free.

The user has said explicitly that the tab order, click-focus and refresh
behaviour there took several iterations and must not regress. `updateNSView`,
`doCommandBy` (Tab/Shift-Tab), `controlTextDidEndEditing` and all of
`ClickFocusTextField` (mouseDown / selectText / becomeFirstResponder) are
off-limits by default. Solve new requirements in the model or in `CurrencyRow`
first; if that file must change, state the line-level blast radius up front and
let the user decide. There is no UI test target, so regressions there are
invisible to CI.

**Two-stage input parsing.** Raw field text → `ConverterModel.value(forInput:)`,
which routes to `ExpressionEvaluator.evaluate` when the text contains an operator
and to `ConverterModel.parse` otherwise. Both are `nonisolated static` and
locale-agnostic: `parse` treats a lone separator with exactly three trailing
digits as grouping (`1.234` → 1234), and expression number tokens go through the
same `parse`, so `1.234*2` is 2468. `ExpressionEvaluator` is a hand-written
recursive-descent parser specifically *because* `NSExpression(format:)` raises an
uncatchable ObjC exception on half-typed input like `70*`; it is total (returns
`nil`) and tolerant (drops trailing operators, auto-closes parens) so every
keystroke yields a live result.

**Two display formatters, different rules.** `ConverterModel.format` is for
amounts: `0` renders as `""` (empty field, not "0" — callers showing a result
must handle that), and a value that rounds to an integer at 2 decimals drops its
fraction digits. `NumberFormatting.perUnit` is for the per-unit rate lines (max 4
fraction digits).

**Row layout invariant.** Every `CurrencyRow` reserves two `.caption2` lines in
`rateInfo`. Non-base rows show both directions of the rate; the base row shows
"Base currency" plus either the expression result or a `Text(" ").hidden()`
spacer. Keep the second line occupied so row heights stay uniform.

**Menu commands cross the scene boundary via `NotificationCenter`**
(`.xrateShowAddSheet`, `.xrateRefresh` in `xRateApp.swift`), because the commands
live in the `App` and the state lives in `ContentView`.

**`RatesService`** is an `actor` hitting `api.frankfurter.dev/v2/`. It uses
`URLSession.shared` directly with no injection point, so it has no test coverage;
tests build a `RateSnapshot` by hand instead.

## Tests

XCTest (not Swift Testing), `@MainActor` classes, host-app based
(`TEST_HOST`/`BUNDLE_LOADER`), so `@testable import xRate` works. Model tests get
isolation from a per-test `UserDefaults(suiteName: "xrate.tests.<UUID>")` plus a
hardcoded EUR-anchored snapshot — reuse the existing `makeModel` helper rather
than adding a new harness. Views are untested.
