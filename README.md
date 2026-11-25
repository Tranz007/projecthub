# ProjectHub

ProjectHub is a local macOS app for finding code projects, opening them in an editor or AI command-line tool, and starting development servers.

## Features

- Choose folders to scan or add an individual project with `.git`, `package.json`, or `pyproject.toml`.
- Browse in a list or cards, with automatic or selected card columns and a collapsible sidebar.
- See technology logos, local server status, and an optional external hosting provider. Hover over a logo for its name, a project name for its description, or a repository or hosting icon for details. Click a repository or hosting icon to open its URL.
- Open a project in Cursor, Visual Studio Code, Zed, or a custom editor.
- Launch Codex, Claude Code, Gemini CLI, or a custom command in a project-scoped Terminal session. Install those tools separately.
- Start or stop a development server from a list row or card. The server indicator shows stopped, starting, running, warning, or unexpected exit, with details on hover. List row server actions provide the local site and logs. Managed servers stop when ProjectHub quits. A standard Node `dev` script is detected automatically; other projects can use a configured command with `{port}`. ProjectHub selects a free local port when starting a server.

## Build and run

Requires macOS 14 or later and Xcode command-line tools with Swift 6 support.

```sh
git clone https://github.com/Tranz007/projecthub.git
cd projecthub
./script/build_and_run.sh
```

The script builds an ad hoc signed app at `dist/Project Hub.app` and opens it locally. `./script/build_and_run.sh --build` builds without launching. This local bundle is not a notarized public download.

On first launch, choose a scan folder, add one project, or continue with the default `~/Desktop` scan. ProjectHub scans only the immediate subfolders of each scan folder. Use **Add** in the main window or **Settings** / **⌘,** to manage sources. Settings also selects an editor and AI tool. Each project's **Configure** control stores its command, external hosting provider and site URL, and favorite state. External hosting details are set by the user; ProjectHub does not query deployment status.

Settings are stored locally at `~/Library/Application Support/ProjectHub/settings.json`. ProjectHub does not require an account or send project data to a server. Configured project and AI commands run locally with your user permissions; review commands before saving them.

## Contributing

Run `swift build -c release` and `swift test` before opening a pull request. Please include clear steps to reproduce a bug or a short description of the behavior a change adds.

## License

Code and original app artwork are available under [MIT](LICENSE). Technology logos are credited separately in [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md); brand marks remain the property of their owners.
