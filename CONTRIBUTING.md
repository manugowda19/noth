# Contributing to NØTH

Thanks for helping. Bug reports, feature ideas and pull requests are all
welcome.

## Reporting a bug

Open an issue with:

- your macOS version and Mac model (notch or no notch, Apple silicon or Intel),
- the NØTH version (menu-bar icon › About NØTH),
- what you did, what you expected, and what happened — a screenshot helps.

## Making a change

1. Fork the repo and create a branch.
2. Build and run: `./build.sh debug && open Noth.app`.
3. Run the tests: `Scripts/run_tests.sh`.
4. Open a pull request describing what changed and how you checked it.

## Ground rules

- **Privacy first.** No analytics, no accounts. Anything that uses the
  network or a macOS permission is opt-in and says so in Settings.
- **Public APIs first.** A private API only when there's no other way: loaded
  with `dlsym`, opt-in, and the feature switches off cleanly if it's missing.
- **Keep it light.** Prefer the standard library and macOS frameworks over new
  dependencies.
- **Accessibility.** Icon-only controls need a label; use the components in
  `DesignSystem.swift`, which handle labels, hit areas and Reduce Motion.
- **Pure logic gets a test** in `Scripts/test_pure_models.swift`.

See [ARCHITECTURE.md](ARCHITECTURE.md) for how the pieces fit together.
