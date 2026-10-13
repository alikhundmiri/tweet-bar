# tweet-bar

A tiny macOS menu bar app for writing tweets. Click the icon, type, polish it with Apple Intelligence, and send.

- **One click** on the menu bar icon opens a compose box.
- **AI buttons:** Rewrite, Rephrase, Catchy, Shorten. They use Apple's on-device model, so they're free and your text never leaves your Mac. ↩︎ undoes the last AI change.
- **Never loses your text.** What you type is saved on every keystroke. It survives closing the box, quitting, and restarting.
- **Drafts:** click **Draft** to save the text, then find it in the **Drafts** tab. **Edit** loads a draft back. If the composer already has text, that text is saved as a draft first, never thrown away.
- **Send** (⌘↩), with two modes, picked under the ⚙︎ gear:
  - **Free (browser), the default.** Opens X's official share page with your tweet filled in. You click Post. No account setup, no cost.
  - **Direct (X API), optional.** Posts straight from the box using your own X developer keys. X charges per post (see [X API pricing](https://docs.x.com/x-api/getting-started/pricing)).

## Requirements

- A Mac running **macOS 26 (Tahoe) or later**. The AI buttons need an Apple silicon Mac.
- **Xcode 26 or later**, installed from the App Store and opened once so it finishes setup. The full Xcode is needed, not just the Command Line Tools, because the AI features use Apple's FoundationModels framework.
- **Apple Intelligence turned on** (System Settings → Apple Intelligence & Siri) for the AI buttons. Everything else works without it.

## Install

```sh
git clone https://github.com/alikhundmiri/tweet-bar.git
cd tweet-bar
./build.sh install
```

This builds the app, copies it to `/Applications/TweetBar.app`, and launches it. Look for the speech-bubble icon in the menu bar. There is no Dock icon; that's intentional.

To start it automatically, click the icon → ⚙︎ → **Launch at login**.

Other commands:

```sh
./build.sh                 # build only, into build/TweetBar.app
open build/TweetBar.app    # run without installing
```

### Update

```sh
cd tweet-bar && git pull && ./build.sh install
```

Your drafts, text and settings are kept.

### Uninstall

```sh
pkill -x TweetBar; rm -rf /Applications/TweetBar.app
rm -rf ~/Library/Application\ Support/TweetBar          # drafts and keys
defaults delete com.alikhundmiri.tweetbar               # composer text and settings
```

## Instructions for AI coding agents

If you're an AI agent (Claude Code, Codex, Cursor, etc.) asked to install this for a user:

1. **Check prerequisites.** Run `sw_vers -productVersion` (must be 26.0 or later), `uname -m` (`arm64` is needed for the AI buttons only), and `xcodebuild -version` (must be Xcode 26 or later). If `xcode-select -p` points at `/Library/Developer/CommandLineTools`, the build will fail to find FoundationModels. Ask the user to install Xcode, then run `sudo xcode-select -s /Applications/Xcode.app`. Don't run `sudo` yourself without asking.
2. **Build and install:** `./build.sh install` from the repo root. Success prints `Installed to /Applications and launched.`
3. **Verify:** `pgrep -lx TweetBar` should show a process. The app has no window until the user clicks the menu bar icon.
4. **Don't post tweets to test.** Posts are public. Free mode only opens a browser page, and nothing is posted unless the user clicks Post. Never enable Direct mode or enter API keys for the user.
5. **Never commit or print API keys.** They are stored in `~/Library/Application Support/TweetBar/x-credentials.json` (mode 600), outside the repo.

## Direct posting setup (optional, paid)

1. At [developer.x.com](https://developer.x.com), create a **Project** and an **App inside it**. Standalone apps (not in a Project) get a 403 error.
2. In the app's **User authentication settings**, set permissions to **Read and write**. For type, choose *Web App, Automated App or Bot*. Callback `http://localhost` is fine.
3. **Then**, under **Keys and tokens**, generate the **Access Token and Secret**. Tokens made before step 2 are read-only and get a 403 error. You also need the **API Key and Secret**. The OAuth 2.0 Client ID/Secret are *not* used.
4. Add credits under billing in the developer console.
5. In TweetBar: ⚙︎ → paste the 4 keys → **Save keys** → switch **Send mode** to **Direct**.

## Where things are stored

| What | Where |
|---|---|
| Current composer text, send mode | `defaults read com.alikhundmiri.tweetbar` |
| Drafts | `~/Library/Application Support/TweetBar/drafts.json` |
| X API keys (if added) | `~/Library/Application Support/TweetBar/x-credentials.json` (readable only by you) |

## How it's built

A Swift Package (no Xcode project) using SwiftUI `MenuBarExtra`. `build.sh` wraps the binary into an `.app` bundle with `LSUIElement` (menu bar only) and ad-hoc code-signs it.

| File | What it does |
|---|---|
| `Sources/TweetBar/TweetBarApp.swift` | Menu bar box: Compose, Drafts, Settings |
| `Sources/TweetBar/Store.swift` | Saves composer text and drafts; X-style character counter |
| `Sources/TweetBar/AI.swift` | Apple Intelligence rewrite actions (FoundationModels) |
| `Sources/TweetBar/XPoster.swift` | Share link, and optional direct posting (OAuth 1.0a) |
