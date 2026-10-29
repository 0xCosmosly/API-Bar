# ⚡️ API Bar

> **Keep an eye on your AI API credits and balances right from your Mac menu bar.** No more surprise cutoffs mid-prompt or dashboard tab gymnastics.

API Bar is a lightweight, privacy-first macOS menu bar app that tracks your remaining API credits and billing quotas across your favorite AI platforms — including **Google Cloud Vertex AI**, **Fireworks AI**, **Cerebras**, **Google AI Studio**, **Refuseless**, **Crowbot**, and custom providers like **Venice AI**, **OpenRouter**, or your own endpoints.

---

### ✨ Highlights

- **Live Credit Gauges in Your Menu Bar**: See your remaining credits at a glance as a percentage or dollar amount.
- **Single or Multi-Icon Display**: Merge all providers into one sleek status icon with easy switching, or display separate gauges for each platform.
- **Zero API Key Hassle (Brave Import)**: Seamlessly reads your authenticated browser sessions directly from Brave. No need to hunt down admin keys.
- **Local Apple AI Model (AFM)**: Add unsupported or custom AI APIs in seconds. Just paste a cURL or let local Apple intelligence detect the balance format on-device.
- **Automatic 100% Reference Baseline**: Smart tier detection automatically calculates your 100% baseline from your latest payment, top-up, or grant.
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
| **Refuseless** | DeepSeek reasoning credits | Brave session |
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

---

### ❓ FAQ (Quick Answers)

**Q: Do I need an API key for every provider?**  
Nope! For natively supported providers, API Bar can safely read your existing signed-in browser session from Brave. You can also paste an admin Bearer token if you prefer.

**Q: How does the 100% gauge work?**  
API Bar automatically infers your top-up baseline (e.g., a $5 top-up or $300 Google Cloud grant) and displays your remaining percentage. You can also click the reference amount in Settings anytime to customize it.

**Q: Can I monitor other providers like OpenRouter or Venice?**  
Yes! Open Settings and expand **Add Custom Provider**. Type in the provider name or paste a cURL command, and Apple's local Foundation Model will automatically configure the endpoint and parser.

---

### License & Attribution

Independent, open-source project. Provider symbols and menu styling inspired by [CodexBar](https://github.com/steipete/CodexBar) (MIT). Not affiliated with Google, Fireworks, Cerebras, or Brave.
