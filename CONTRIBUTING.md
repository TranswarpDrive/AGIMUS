# Contributing To AGIMUS

Thanks for helping improve AGIMUS.

## Branch Strategy

- `main`: stable branch
- `develop`: integration branch for active work
- `feature/*`: new features
- `fix/*`: bug fixes
- `docs/*`: documentation-only changes

Unless a maintainer says otherwise, open pull requests against `develop`.

## Development Setup

1. Open `AGIMUS/AGIMUS.xcodeproj` in Xcode.
2. Select the shared `AGIMUS` scheme.
3. Build and run the app on a simulator or device.
4. Configure at least one provider in the in-app settings before testing chat flows.

## Pull Request Expectations

- Keep pull requests focused.
- Explain what changed and why.
- Include screenshots for UI changes when possible.
- Mention any manual verification you performed.
- Update documentation if behavior or setup changed.

## Coding Guidelines

- Follow the existing UIKit and Swift style in the repository.
- Prefer small, understandable changes over broad rewrites.
- Avoid committing secrets, personal endpoints, or local-only configuration.
- Preserve user-facing behavior unless the pull request intentionally changes it.

## Before Opening A PR

- Build the project locally in Xcode if possible.
- Verify changed flows manually.
- Check that CI passes.
- Rebase or merge from the latest target branch if needed.

## Reporting Bugs

Use the bug report issue template and include:

- iOS version
- device or simulator
- reproduction steps
- expected behavior
- actual behavior
- screenshots or logs when helpful
