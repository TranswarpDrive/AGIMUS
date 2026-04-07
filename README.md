# AGIMUS

AGIMUS is a native iOS chat client for OpenAI-compatible LLM providers.

It supports multi-provider configuration, streaming responses, reasoning/thinking display, optional web search tools, conversation history, and automatic title generation for chats.

## Features

- Multiple chat providers with independent base URLs, model lists, API keys, and generation settings
- Streaming and non-streaming chat responses
- Optional thinking/reasoning display for supported models
- Optional web search integration through multiple search providers
- Conversation history stored locally on device
- API keys stored in the iOS Keychain
- Automatic Chinese conversation title generation
- Light mode, dark mode, and system-following appearance

## Requirements

- Xcode
- iOS 12.0 or later
- Swift 5

## Project Structure

- `AGIMUS/AGIMUS/Models`: data models for sessions, messages, providers, and token usage
- `AGIMUS/AGIMUS/Services`: networking, search integration, persistence, settings, and keychain storage
- `AGIMUS/AGIMUS/ViewControllers`: session list, chat, settings, and provider management screens
- `AGIMUS/AGIMUS/Views`: reusable chat UI components
- `AGIMUS/AGIMUS/Utils`: theme and markdown helpers

## Getting Started

1. Open `AGIMUS/AGIMUS.xcodeproj` in Xcode.
2. Build and run the app on a simulator or device.
3. Open `设置`.
4. Add at least one chat provider.
5. Enter the provider base URL, API key, and select a model.
6. Optionally add a search provider if you want web search tool support.

## Notes

- AGIMUS is designed around OpenAI-compatible chat APIs such as `/chat/completions` and `/models`.
- API keys are not stored in the repository. They are saved locally in the iOS Keychain at runtime.
- Search providers are optional. If not configured, chat still works normally.
- Chat history is stored locally on the device.

## Security

This repository does not intentionally include any production API keys.

Before publishing your own fork, double-check that you have not committed:

- personal `xcuserdata` files
- local assistant/tooling config
- screenshots containing private data
- custom provider endpoints or secrets you do not want to disclose

## License

MIT. See [LICENSE](LICENSE).
