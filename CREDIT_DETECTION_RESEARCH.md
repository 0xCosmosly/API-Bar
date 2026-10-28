# APIBar: automatic credit detection research

October 22, 2026. Research only; provider detection has not been implemented or authenticated.

## What CodexBar actually does

CodexBar uses different data sources for different providers. Its most useful pattern for APIBar is **an authenticated dashboard API request using a saved session**, not a permanently open browser tab.

### Account balances from documented APIs

**OpenRouter**: CodexBar calls `/api/v1/credits` and calculates the remaining balance as `total_credits - total_usage`. Because the provider supplies the funding total as well as consumption, purchases can be reflected in subsequent responses. Key-level spending caps are separate from account money. This is a good architectural example, but those endpoints are OpenRouter-specific and cannot be used to read Fireworks or Google balances. [CodexBar OpenRouter documentation](https://github.com/steipete/CodexBar/blob/main/docs/openrouter.md)

**DeepSeek**: Its balance endpoint reports total, granted, and topped-up balances. CodexBar can authenticate this endpoint with an API key. Dashboard-only detailed usage uses a separate website session. This demonstrates why a true balance response is preferable to subtracting a rolling spending estimate. [CodexBar DeepSeek documentation](https://github.com/steipete/CodexBar/blob/main/docs/deepseek.md)

### Account data from a saved website session

**Cursor**: CodexBar can import a session cookie, cache it in macOS Keychain, and request `https://cursor.com/api/usage-summary` directly. It also supports a usable Cursor app session. Browser import and later HTTP polling are separate operations. Code inspection confirms that the usage-summary request uses `URLSession` with a Cookie header; it does not read a live tab. An expired or rejected session requires sign-in recovery. [Cursor provider documentation](https://github.com/steipete/CodexBar/blob/main/docs/cursor.md), [request implementation](https://github.com/steipete/CodexBar/blob/main/Sources/CodexBarCore/Providers/Cursor/CursorStatusProbe.swift), [Keychain cookie cache](https://github.com/steipete/CodexBar/blob/main/Sources/CodexBarCore/CookieHeaderCache.swift)

This corrects the earlier overly broad suggestion that dashboard-derived balances necessarily require Brave and billing tabs to stay open. That requirement applied to the proposed tab-reading extension. A reusable session plus direct HTTP requests can work without open tabs, where the provider permits it.

## What this means for the two target providers

| Provider | Confirmed CodexBar implementation | Missing for APIBar |
| --- | --- | --- |
| Fireworks | API-key authentication, account discovery, and 30-day rated spending from `/v1/accounts/{account}/billing/summary` | An authenticated response containing actual available credits, including purchases and grants |
| Vertex / Google Cloud | gcloud authentication and Cloud Monitoring quota/identity; Claude Code logs for local token costs | Billing-account available credit grants and their remaining values; request quota is not money |

**Fireworks**: The installed CodexBar 0.73.0 plugin was inspected directly. It returns a 30-day cost total, not available credits. Its documentation explicitly identifies the website as the authoritative balance source. Reusing this fetcher alone would not detect top-ups. [Fireworks provider documentation](https://github.com/steipete/CodexBar/blob/main/docs/fireworks.md)

**Google Cloud**: Copying CodexBar's Vertex provider would not solve this task: quota percentage and remaining promotional dollars are different measurements. Google's public Billing API documentation focuses on account/project administration and pricing, while the Credits console displays grant status, original value, remaining value, scope, and expiration. Billing exports can help audit applied credits and spending, but do not by themselves establish every newly available grant or account payment balance. [CodexBar Vertex documentation](https://github.com/steipete/CodexBar/blob/main/docs/vertexai.md), [Google Billing API overview](https://docs.cloud.google.com/billing/docs/develop), [Google credit documentation](https://docs.cloud.google.com/billing/docs/how-to/resolve-issues)

## Recommended next proof of concept

Build a **session-backed balance fetcher**, beginning with Fireworks:

1. Identify the exact read-only request its signed-in dashboard uses for the Credits amount. Verify the response, currency, and account identity against the displayed number.
2. Determine whether it accepts an API key. If it requires a website session, validate a supported session acquisition and renewal path. Merely saving an ordinary inference key is not enough.
3. Keep reusable secrets in APIBar's own macOS Keychain entries, scoped to the selected provider account. Never put them in the project, diagnostics, or the balance JSON.
4. Test native background requests after closing the browser. Demonstrate a real decrease and a real top-up/credit grant before calling automatic detection complete.
5. Investigate Google's Credits request separately. Confirm account scope, pagination, grant eligibility, expiry, and session requirements. Do not assume that Fireworks and Google authentication work alike.

**Feasibility remains unproven for these two exact credit endpoints.** CodexBar provides a working design pattern, not an already-built Fireworks/Google credit detector. No private billing endpoint or reusable session has been validated in this work, and no cookies or credentials were imported.

If a provider blocks reusable native sessions, the implementation must report that limitation rather than quietly replacing an actual balance with a spending estimate. Both providers may also publish billing changes with a delay.

## Acceptance criteria for the eventual connector

- Account-wide balance across all tools and machines.
- Actual money plus active credits, including automatic top-up recognition.
- No requirement to leave Brave or a billing tab open after authentication, if supported by the tested provider session.
- Expired credits excluded; valid zero balances preserved; failures never converted to zero.
- Account-bound credentials and snapshot timestamps; stale or failed reads disclosed in the menu.
- Verified arithmetic and an explicit funding-reference policy for the percentage when new money or grants arrive.

## Current app verification

APIBar was built, locally signed, relaunched, and checked through its own native diagnostics. Both status items are visible. Their percentage text uses the proportional macOS system font at 13pt. The extra dot is removed; a thin-space gap separates the icon and number. The menu follows CodexBar's native rich-card structure and typography, adapted to APIBar's own account data and controls. Automatic detection remains unconnected.

The last verified dollars remain $300.00 and $10.07. Their calculated percentage is 100% against the saved references. A temporary requested 99% preview was removed; the app does not fabricate a monetary decrement from a report of “a little” usage.
