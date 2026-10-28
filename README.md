# API Bar

A native macOS menu bar companion showing remaining account credits for Vertex AI / Google Cloud, Fireworks, and Crowbot. The menu follows CodexBar's layout and system typography. Start at Login is available in the menu and Settings.

## Local use

Double-click **API Bar.app**. No Apple Developer account is needed to build or use it locally. Requires macOS 13 or later.

Sign in to the provider in Brave, then choose **Settings → Connect from Brave**. This explicit action may ask for access to Brave Safe Storage and API Bar's saved sessions. Sessions are stored in macOS Keychain, never in the project, logs, or balance JSON. After connection, Brave and its tabs can be closed. Expired sessions may need a manual reconnect.

Background refresh runs every five minutes and is prohibited from presenting Keychain dialogs. If access requires approval, Settings shows an error and the previous balance is retained. Local ad-hoc signing changes the app identity on rebuild, so a rebuilt version can require an explicit reconnect even after a previous Always Allow choice. This is separate from background prompt suppression. No Keychain access controls are weakened.

Fireworks' account balance endpoint has been live-verified, including its authenticated refresh. Google Cloud's credit-grant connector has now passed a live balance check against the billing dashboard. The two providers can be connected independently. A connection failure retains the previous value and timestamp; it does not fabricate a balance.

The personal defaults are the balances verified on October 22, 2026: $300 Google Cloud credit and $10.07 Fireworks. These defaults are snapshots until connected. The expired Google grant is excluded. Percentages are `floor(remaining / reference × 100)`, with `<1%` for a positive balance below one percent. You can edit the 100% reference in Settings. If a connected balance exceeds the reference, the reference grows to that balance. Smaller top-ups raise the percentage against the saved reference. Provider accounting may lag usage.

Balances and reference amounts are saved at `~/Library/Application Support/APIBar/balances.json`. Credentials are stored separately in Keychain. Disconnect removes the saved session.

## Build and check

Install Apple's Swift command line tools, then run:

```sh
./check.command
./build.command
```

The build targets this Mac's architecture and uses ad-hoc signing. Checks cover percentages, money parsing, account validation, active/expired/duplicate credit grants, and the no-interaction Keychain policy. Checks do not read credentials or display approval dialogs.

## GitHub distribution

This folder is a personal prototype, with account-specific defaults. Before publishing, replace those defaults with an account setup flow and finish the Google connector. No repository or release has been published.

Source can be shared on GitHub for others to build locally without a paid Developer account. Downloadable builds must match the recipient's architecture (or be universal). Without Developer ID signing and notarization, macOS may require an explicit approval in Privacy & Security. See [Apple's instructions](https://support.apple.com/102445). A Developer account is only needed if you later choose Apple Developer ID signing and notarization. Stable signing is a separate requirement for preserving Keychain trust across updates.

## Attribution

Menu styling and provider symbols follow [CodexBar](https://github.com/steipete/CodexBar) (MIT). API Bar is independent and is not affiliated with CodexBar, Google, or Fireworks. See `THIRD_PARTY_NOTICES.md`.

## Menu bar identity and app icon

Version 0.2.1 includes a native app icon and stable menu bar identities for Thaw and other menu bar managers:
- `vertex` — API Bar — Vertex AI
- `fireworks` — API Bar — Fireworks

The menu bar uses native provider images and percentage text. Provider images are rasterized before being handed to the system menu-bar host. Accessible labels stay constant; the live percentage is also an accessibility value. Items are created once and retain their autosave names. A second launch reuses the running app. Thaw can restart API Bar without duplicate items.

On macOS 27, both items must use the same Thaw section because the OS hides items by app. Independent hiding would require separately bundled helper apps. API Bar does not change Thaw's layout or system menu bar preferences.

The icon artwork is maintained in `Tools/MakeIcon.swift`; the bundled icon is `Resources/AppIcon.icns`. This Mac's command line SDK 26.5 is selected in the build script because SDK 27's SwiftUI State macro is unavailable in the standalone tools.

## Connection access repair (0.2.2)

Settings now includes Choose Brave Profile. Select the Default or Profile folder used for the provider sign-ins. The system folder picker grants access to that chosen folder; the app saves a folder bookmark, not cookies, in preferences. Provider credentials are still saved only in Keychain after successful account validation.

Unreadable profile files and SQLite failures are reported as access/database errors rather than as missing sign-in sessions. The other-app-data privacy prompt explains why Brave data is needed. Reopening API Bar brings up Settings. Provider authentication still needs a live test after profile access is approved.

## Profile picker repair (0.2.3)

The local build now uses a regular folder bookmark, preserving the folder picker’s implicit access. Explicit App Sandbox bookmarks failed because this build does not adopt App Sandbox. Profile databases remain read-only and macOS privacy checks still apply. A temporary-folder bookmark round-trip is covered by the checks. Re-select the Brave profile if an older bookmark cannot be resolved.

## Routing icon (0.2.4)

The app icon uses an original black branching route on a white macOS tile. Render and assemble it with `swift Tools/MakeIcon.swift AppIcon.iconset Resources/AppIcon.icns`. The menu bar retains the distinct Vertex and Fireworks provider symbols and their stable accessibility identities. The routing artwork is used only for the application icon, including system prompts.

Google billing requests now select the named `LjgHrc` bootstrap client key and validate the single-result batch envelope before parsing grants. Checks cover unrelated client keys, ambiguous configuration, failed batches, and duplicate results.

## Live connection verification (0.2.5)

Both providers connected successfully on October 25, 2026. Google returned $300 in active credit expiring December 25, 2026, matching the signed-in dashboard; the separate expired grant was excluded. Fireworks returned $10.070595489. Actual usage decreases, future top-ups, and saved-session refresh across restarts remain separate acceptance checks. The monochrome routing icon is bundled under a new resource name so macOS can refresh its cached application artwork.

## Settings and Thaw previews (0.2.8)

API Bar appears in the Dock while Settings is open (including minimized Settings), and returns to menu-bar-only mode when Settings closes. A standard app menu provides Settings and Quit. A one-time migration removes the old anonymous Item-0/Item-1 visibility flags; it does not continuously override Thaw.

Thaw 3.0 beta skips hidden-item preview capture while macOS native notch overflow is active. On October 25, provider previews were recaptured after temporarily hiding CodexBar to clear that overflow, then restoring the original sections: CodexBar Visible, API Bar Hidden. Captured previews show Fireworks 100% and Vertex 99%. The app's displayed dollar balances are rounded to cents; percentages floor the full-precision amount. Saved-session approval after a rebuild remains separate from these display checks.

## Crowbot (0.3.0)

Crowbot has its own crow symbol, stable `crowbot` menu-bar identity, percentage, dashboard shortcut, and Connect from Brave controls. Connect reads only the `crowbot_key` cookie from the selected Brave profile. The account number is also a credential: it is saved only in macOS Keychain, and a one-way account fingerprint is used in the ordinary balance file. The connector reads `https://chat.crowbot.sh/api/me`, converting the integer `balance_microdollars` into USD. Requests are limited to that exact endpoint, without redirects or unrelated cookies. A changed account is rejected after the first successful connection.

Existing provider balances migrate into the three-provider list. Crowbot shows an em dash until connected; the first verified balance establishes its 100% reference. It refreshes every five minutes under the same no-background-Keychain-dialog policy. Balance parsing, account pinning, credential scope, and redirects are covered by the checks.

Crowbot connected live on October 25, 2026 and returned $4.996991 (displayed as $5.00), matching the signed-in dashboard. Its initial reference is that verified balance.

The saved Crowbot session also passed a noninteractive refresh after quitting and relaunching the installed 0.3.0 app. Vertex and Fireworks retain their balances but currently require explicit reconnect approval after the ad-hoc-signed update.

## Retina provider icons (0.3.1)

Menu-bar icons now contain explicit 18, 36, and 54 pixel representations for the same 18-point symbol. This preserves sharp Retina edges while retaining native template rendering and cached bitmap representations for menu-bar managers.

## Merged menu-bar item (0.4.0)

Settings → Merge provider icons switches between three individual status items and one combined item. The combined menu has provider tabs for Vertex AI, Fireworks, and Crowbot; selecting a tab updates the balance card, dashboard destination, and the menu-bar symbol and percentage. Both the merged preference and selected provider persist across launches. Turning merging off restores the individual provider identities and their saved positions. The merged item uses the stable identity `merged`, with the same Retina template artwork.

## Inward-connection identity and menu input (0.4.1)

API Bar now uses an original inward-connection mark: two opposed arrows surrounded by open arcs. The concept follows the design study of Jacques Nathan-Garamond’s mark #1329 in Yasaburo Kuwayama’s *Trademarks & Symbols, Volume 2* (1973, p. 138); the archived artwork is not bundled. The shared AppKit renderer is `Sources/BrandMark.swift`. It produces the white app tile, Settings branding, and the merged menu-bar template, with 1×, 2×, and 3× pixel representations. Individual provider symbols retain their provider identities. `build.command` generates the ICNS from the same source before building.

Merged provider tabs now use a persistent AppKit selector with direct matching mouse-down/mouse-up hit testing, following CodexBar’s MIT-licensed menu-tracking approach. Icon, text, and tab padding share one hit area. Switching only replaces the balance detail; it does not replace the selector under the pointer. Canceled drags do not activate another provider. Native accessibility button actions and left/right keyboard navigation remain available. Dashboard is a standard menu action targeting the selected provider.

`check.command` includes interaction checks for repeated clicks across each tab, canceled drags, accessibility activation, selector persistence, and Retina brand representations, alongside the existing connector checks.

## Compact credits footer and pixel bounds (0.4.2)

The merged menu fits its height to the tallest provider card, with a four-point footer inset. Provider tabs remain in a stable position across selection changes. Icon rasterization relies on the bitmap representation's point size to supply the Retina transform, avoiding a second manual scale. The checks verify visible pixel bounds in every brand and provider representation, so clipped high-resolution artwork fails validation.

## Selected provider symbol (0.4.3)

The merged menu-bar item displays the currently selected provider’s Retina symbol and percentage. Selecting Vertex, Fireworks, or Crowbot changes both immediately. The inward-arrow API Bar identity remains the app icon and Settings branding.

## Last checked timestamp, batch connection, and dashboard fallback (0.4.4)

Version 0.4.4 introduces:
- A single "Last checked" timestamp line on the balance detail card under remaining credits, updating dynamically with selected provider tabs.
- Cached in-memory Brave Safe Storage authorization during batch connections, preventing repeated system Keychain permission dialogs.
- "Connect All from Brave" in Settings to connect all providers in a single flow.
- Contextual button states: "Connect from Brave" is greyed out when an account is connected; "Disconnect" is enabled only for active accounts.
- Automatic default browser dashboard launch: attempting to connect an account without active session data automatically opens a tab in the system default browser to that provider's dashboard/login page.
- Cleaned balance card footer padding, removing excess bottom whitespace above the menu separator.
