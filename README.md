# AGIMUS

[![CI](https://github.com/TranswarpDrive/AGIMUS/actions/workflows/ios-ci.yml/badge.svg)](https://github.com/TranswarpDrive/AGIMUS/actions/workflows/ios-ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

AGIMUS is a native iOS chat client for OpenAI-compatible LLM providers.

It is built for people who want a local-first mobile app that can talk to different model providers, stream responses in real time, optionally call web search, and keep API secrets on-device instead of in the repository.

## Highlights

- Multiple chat providers with independent base URLs, model lists, API keys, and generation settings
- Streaming and non-streaming responses
- Optional thinking or reasoning display for supported models
- Optional web search integration through multiple search providers
- Local conversation history
- API keys stored in the iOS Keychain
- Automatic Chinese conversation title generation
- Light mode, dark mode, and system-following appearance

## Tech Stack

- UIKit
- Swift 5
- Xcode project, no package-manager dependency required for the app itself
- iOS 12.0 deployment target

## Project Layout

- `AGIMUS/AGIMUS/Models`: data models for sessions, messages, providers, search, and token usage
- `AGIMUS/AGIMUS/Services`: networking, search integration, persistence, settings, and keychain storage
- `AGIMUS/AGIMUS/ViewControllers`: session list, chat, settings, and provider management screens
- `AGIMUS/AGIMUS/Views`: reusable chat UI components
- `AGIMUS/AGIMUS/Utils`: theme, markdown, and helper utilities
- `.github`: CI workflow, issue templates, PR template, and release-note config

## Getting Started

1. Open `AGIMUS/AGIMUS.xcodeproj` in Xcode.
2. Select the shared `AGIMUS` scheme.
3. Build and run on an iPhone simulator or device.
4. Open the in-app settings screen.
5. Add at least one OpenAI-compatible provider.
6. Enter the provider base URL, API key, and model.
7. Optionally add a search provider if you want tool-assisted web search.

## Configuration Notes

- AGIMUS is designed around OpenAI-compatible endpoints such as `/chat/completions` and `/models`.
- API keys are not stored in this repository. They are saved locally in the iOS Keychain at runtime.
- Search providers are optional. If none are configured, chat still works normally.
- Chat history is stored locally on the device.

## Open Source Workflow

- `main` is the stable branch.
- `develop` is the integration branch for ongoing work.
- New work should usually start from feature branches and open a pull request into `develop`.
- Release tags follow `vX.Y.Z`.

See [CONTRIBUTING.md](CONTRIBUTING.md) for the full contribution workflow.

## Security And Privacy

This repository does not intentionally include any production API keys.

Before publishing your own fork, double-check that you have not committed:

- personal `xcuserdata` files
- local assistant or tooling config
- screenshots containing private data
- custom provider endpoints or secrets you do not want to disclose

If you find a security issue, please follow [SECURITY.md](SECURITY.md).

## Branding Note

The current app name, icon, or related media may reference third-party intellectual property. If you plan to redistribute AGIMUS publicly beyond source code sharing, make sure you have the rights to use the branding and assets you ship.

## License

MIT. See [LICENSE](LICENSE).
