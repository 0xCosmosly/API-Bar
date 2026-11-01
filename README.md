# ⚡️ API Bar

> **A native macOS companion to [CodexBar](https://github.com/steipete/CodexBar)** built to track the AI APIs it doesn't cover yet — right from your menu bar with zero API key hassle.

I built API Bar because some of the AI providers I use every day (like Google Cloud Vertex AI, Fireworks, Cerebras, and Google AI Studio) weren't tracked by CodexBar. API Bar lives alongside it in your menu bar, automatically pulling balances from your signed-in browser sessions and keeping an eye on your remaining credits so you never hit an unexpected quota cutoff mid-prompt.

---

### ✨ Highlights

- **Live Credit Gauges in Your Menu Bar**: See your remaining credits at a glance as a percentage or dollar amount.
- **Single or Multi-Icon Display**: Merge all providers into one sleek status icon with easy switching, or display separate gauges for each platform.
- **Zero API Key Hassle (Brave Import)**: Seamlessly reads your authenticated browser sessions directly from Brave. No need to hunt down admin keys.
- **Local Apple AI Model (AFM)**: Add unsupported or custom AI APIs in seconds. Just paste a cURL or let local Apple intelligence detect the balance format on-device.
- **Automatic 100% Reference Baseline**: Smart tier detection automatically calculates your 100% baseline from your latest payment, top-up, or grant.
- **Built-In Updates**: Checks GitHub Releases for new versions, shows the changelog, and installs the update in place — no separate downloader.
- **100% Private & Local**: Zero telemetry, zero third-party cloud servers. Your sessions stay locked safely in your macOS Keychain.

---

### 🚀 Supported Providers

| Provider | What it tracks | How it connects |
| :--- | :--- | :--- |
| **Vertex AI / Google Cloud** | Active billing credits & trial grants | Brave session |
| **Fireworks AI** | Inference balance & prepaid credits | Brave session |
| **Cerebras** | Fast inference platform credits | Brave session |
| **Google AI Studio** | Developer quota & tier credits | Brave session |
| **Crowbot** | Chat & API usage credits | Brave session |
| **Refuseless** | Prepaid USD balance & top-up ledger | Brave session |
| **Custom / Any API** | Venice, OpenRouter, Groq, Together, etc. | Local AI detection or Bearer token |

---

### 🛠️ Getting Started

1. **Download & Run**:
   - Double-click `API Bar.app` to start (requires macOS 13 Ventura or later).
2. **Quick Onboarding**:
   - Select the providers you want to track (or tap *Select All*).
   - Pick your Brave profile and click **Connect All from Brave**.
   - Customize your menu bar look (merged vs. separate icons, sort order).
3. **Done!** Your live balances now refresh every 5 minutes in your menu bar.

---

### 🔒 Privacy & Security

- **Strictly Local**: API Bar never sends your credentials, tokens, or balance data to external servers.
- **Keychain Protected**: Session cookies and auth tokens are stored encrypted in your local macOS Keychain.
- **Silent Background Refresh**: Periodic updates are forbidden from prompting for Keychain permissions in the background.

---

### 💻 Build from Source

You can build API Bar locally using standard Apple Swift command line tools (no paid Apple Developer account needed):

```sh
git clone https://github.com/0xCosmosly/api-bar.git
cd api-bar
./check.command    # runs test suites & validation
./build.command    # builds & installs to /Applications/API Bar.app
```

`check.command` runs its tests against a throwaway directory, so it never reads, overwrites, or deletes your real saved sessions or `balances.json`.

---

### 📦 Publishing a Release

API Bar updates itself from GitHub Releases, so publishing is just a tag plus an asset:

1. Bump `CFBundleShortVersionString` in `Resources/Info.plist`.
2. Run `./build.command` — this writes `APIBar-app.zip` next to the project.
3. Create a GitHub Release tagged `vX.Y.Z` and attach `APIBar-app.zip`.

Running copies poll `releases/latest` in the background, show the release body as a changelog window when the tag is newer, and install the attached zip in place. No hosting, CDN, or appcast is required.

---

### ❓ FAQ (Quick Answers)

**Q: Do I need an API key for every provider?**  
Nope! For natively supported providers, API Bar can safely read your existing signed-in browser session from Brave. You can also paste an admin Bearer token if you prefer.

**Q: How does the 100% gauge work?**  
API Bar automatically infers your top-up baseline (e.g., a $5 top-up or $300 Google Cloud grant) and displays your remaining percentage. You can also click the reference amount in Settings anytime to customize it.

**Q: Can I monitor other providers like OpenRouter or Venice?**  
Yes! Open Settings and expand **Add Custom Provider**. Type in the provider name or paste a cURL command, and Apple's local Foundation Model will automatically configure the endpoint and parser.

**Q: How do I update API Bar?**  
Pick **Check for Updates…** from the menu, or let it check in the background. When a newer release exists you'll see the changelog and a one-click install.

---

### License & Attribution

Independent, open-source project. Provider symbols and menu styling inspired by [CodexBar](https://github.com/steipete/CodexBar) (MIT). Not affiliated with Google, Fireworks, Cerebras, or Brave.
