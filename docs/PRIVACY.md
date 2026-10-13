# Privacy

RyzenStatus is built to be local-first. Core features run on your Mac, and the app has no RyzenStatus account, cloud dashboard or backend.

## The short version

- **No account.** There is nothing to sign up for and nobody to log in as.
- **No subscription.** The app is free and stays free, with nothing held back behind a paid tier.
- **No telemetry.** RyzenStatus gathers no usage stats, no crash reports, no device identifiers and no diagnostics.
- **No RyzenStatus analytics or tracking.** There are no analytics kits, no ad networks and no third party tracking anywhere in the app.
- **No data selling.** There is nothing to sell, because none of your information is collected to begin with.
- **Your settings stay put.** Preferences and saved state live in the app's own local storage on your Mac and are never uploaded.

## What it reads, and where that stays

Everything RyzenStatus shows you, from the CPU and memory load to the temperatures, the battery details, the network rates, the window list, per app volume and the files on the Shelf, is read locally through native macOS APIs and shown to you right there. None of it is sent anywhere, logged remotely or shared.

Clipboard history, including the images and files you copy, lives in the app's local storage on your Mac and never leaves it. Copy text from screen recognizes the text entirely on device with Apple's Vision framework, and the temporary capture is deleted as soon as the text is read.

When a feature needs a macOS permission such as Accessibility or Screen Recording, that access is used only for the local feature it belongs to. The [permissions guide](PERMISSIONS.md) breaks down each one.

## Network connections

RyzenStatus opens only a few kinds of connection, and each one belongs to a visible feature.

1. **The update check, automatic and easy to switch off.** So it can tell you when a newer version exists, RyzenStatus asks GitHub's public releases API at `api.github.com` for this project's latest release. The request carries only a standard user agent with the app name and its version, and no account, identifier or usage data go along with it. It runs a short while after launch and now and then while the app is open. You can turn it off in Settings under About, and once it is off no update requests are made. If you choose to install an offered update, the disk image comes from GitHub.

2. **The internet speed test, only when you ask.** The optional speed test in the Network section reaches Cloudflare's public speed endpoints at `speed.cloudflare.com` to measure latency and your download and upload throughput. This happens only when you start a test yourself, and never on its own.

3. **Homebrew actions, only when you use the Homebrew manager.** Search, install and uninstall actions run the local `brew` command, which may contact Homebrew, GitHub and package vendor hosts to search metadata or download files. Popularity badges use Homebrew's public aggregate analytics JSON from `formulae.brew.sh`. RyzenStatus does not send its own analytics, capture passwords or run `brew` as root.

4. **Now Playing lyrics & animated artwork, only when enabled.** When viewing the Now Playing details pane, synced and plain lyrics may be looked up via the public keyless `lrclib.net` API or from local Apple Music AppleScript. When live motion artwork is turned on, animated cover video streams are loaded from public Apple Music media CDNs. These requests include only the track metadata needed to locate the lyrics or artwork; no personal identifiers, account tokens, or telemetry are ever sent, and results are cached locally in memory.

5. **App Store updates check, only when viewing the App Updates panel.** When checking for updates to Mac App Store applications, RyzenStatus queries Apple's public iTunes Search API at `itunes.apple.com/lookup` using the bundle identifiers of installed Mac App Store apps and your system region to check current store versions. No account information or user identifiers are transmitted.

6. **Release highlights showcase media, only when viewing the What's New panel.** When opening the release highlights window after an update, showcase preview media is downloaded from GitHub release assets at `github.com`.

7. **Feedback, only when you send it.** Settings, the panel and the command bar can draft a bug report or a feature idea. The app sends nothing itself: it opens a prefilled "new issue" page of this project's public GitHub repository in your browser, with your text and, only if you tick the box, the version, macOS, Mac model, language and update channel shown in the window. You review it there, sign in with your own GitHub account and decide whether to submit it. Submitted issues are public.

8. **AI agents in the Dynamic Island, only when you turn the section on.** It is off by default. While on, it reads the history files the Claude Code, Codex, OpenCode and GitHub Copilot tools already keep on this Mac (and the plan percentages the Claude app saves) to show tokens, limits and work in progress. Those files are read in place and never uploaded; the totals it keeps stay in the app's own local storage. With price updates on, it downloads the public price list from this project's GitHub repository at most once a day, with no usage or identifiers in the request; otherwise it uses the list built into the app. Reading Codex's banked resets, or using one, runs your own installed Codex tool, which talks to its maker with its own sign-in; RyzenStatus never reads those credentials, and a reset is used only after you confirm it.

That is the entire list. There are no RyzenStatus servers, no hidden beacons and no background uploads.

## Changes to this document

This page describes how the current version of RyzenStatus behaves. If the app's behavior around privacy ever changes, this page changes with it.

## Questions

If anything here is unclear, open a question in [GitHub issues](https://github.com/DrogaBox/ryzenstatus-utils/issues), or have a look at [support](../SUPPORT.md).
