# Doppio

Setup, layout and commands are in `README.md`. What an agent needs on top:

- Use the Makefile targets. Only the Command Line Tools are installed (no Xcode). There is no test target yet.
- Every build must be signed with the "Doppio Dev" identity, or launch at login is lost on rebuild. If `make app` falls back to ad-hoc signing, run `make cert` once.
- `make install` replaces the app in `/Applications` and relaunches it; use it to check a change in the menu bar.
- Releases: `make release:patch` or `make release:minor` from a clean `main`. It builds, tags, pushes the tag and publishes the GitHub release.
- Icons: ask for a reference image first (the menu bar icon only worked from one). Show 3 to 5 options on one sheet at real size (14 pt for the menu bar), show every image inline, and give each iteration a new file name. SF Symbols are not allowed in app icons (Apple's license).
