# ProjectHub

ProjectHub is a local macOS app for finding code projects, opening them in an editor or AI command-line tool, and starting development servers.

## Features

- Scan folders you choose for projects with `.git`, `package.json`, or `pyproject.toml`.
- Browse in a list or cards, with automatic or selected card columns and a collapsible sidebar.
- See technology logos and local server status. Hover over a logo for its name, a project name for its description, or the GitHub icon for repository details.
- Open a project in Cursor, Visual Studio Code, Zed, or a custom editor.
- Launch Codex, Claude Code, Gemini CLI, or a custom command in a project-scoped Terminal session. Install those tools separately.
- Start or stop a development server from a list row or card. Open its local site and inspect the latest logs. A standard Node `dev` script is detected automatically; other projects can use a configured command and preferred port. ProjectHub selects a free port when starting a server.

## Build and run

Requires macOS 14 or later and Xcode command-line tools with Swift 6 support.

```sh
git clone https://github.com/Tranz007/projecthub.git
cd projecthub
./script/build_and_run.sh
```

The script builds an ad hoc signed app at `dist/Project Hub.app` and opens it locally. `./script/build_and_run.sh --build` builds without launching. This local bundle is not a notarized public download.

Use **Settings** or **⌘,** to choose scan folders, an editor, and an AI tool. The initial scan folder is `~/Desktop`. ProjectHub scans its immediate subfolders. Each project's **Configure** control stores its command, preferred port, and favorite state.

Settings are stored locally at `~/Library/Application Support/ProjectHub/settings.json`. ProjectHub does not require an account or send project data to a server. Configured project and AI commands run locally with your user permissions; review commands before saving them.

## Contributing

Build with `swift build -c release` before opening a pull request. Please include clear steps to reproduce a bug or a short description of the behavior a change adds.

## License

Code and original app artwork are available under [MIT](LICENSE). Technology logos are credited separately in [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md); brand marks remain the property of their owners.
