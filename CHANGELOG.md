# Changelog

All notable changes to this project will be documented in this file.

The format loosely follows Keep a Changelog and uses semantic version tags.

## [1.3.0] - 2026-04-10

### Added

- Chat history search with highlighted hits and searchable snippets in the session list
- Search history suggestions and a clear-history action in the session list search UI
- Reply regeneration and previous-user-message editing with multi-version paging
- User-message copy actions and assistant-error messages that remain in the conversation as copyable, regeneratable replies
- In-app background continuation for ongoing AI generation when navigating away from the chat screen

### Changed

- Streaming output now renders character by character, including streamed thinking content
- Thinking panels appear as soon as `<think>` content starts and update their live character count during streaming
- Chat updates no longer force-scroll to the bottom when expanding thinking or refreshing existing content
- Chat toolbar layout and search result presentation were refined for narrow screens
- README documentation updated to reflect the current feature set

## [0.1.0] - 2026-04-07

Initial public open-source release.

### Added

- Native iOS chat client for OpenAI-compatible LLM providers
- Multi-provider configuration with per-provider base URL, API key, model, and generation settings
- Streaming and non-streaming response support
- Optional reasoning or thinking display for compatible models
- Optional web search tool integration through multiple search providers
- Local conversation storage and automatic title generation
- On-device Keychain storage for API keys
- GitHub community files, CI workflow, contribution guide, and release metadata
