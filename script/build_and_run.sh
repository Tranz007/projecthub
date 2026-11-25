#!/bin/zsh
set -euo pipefail

mode="${1:-run}"
root="$(cd "$(dirname "$0")/.." && pwd)"
bundle="$root/dist/Project Hub.app"
contents="$bundle/Contents"

cd "$root"
swift build -c release
mkdir -p "$root/dist"
rm -rf "$bundle"
mkdir -p "$contents/MacOS" "$contents/Resources"
cp .build/release/ProjectHub "$contents/MacOS/ProjectHub"
cp Resources/Info.plist "$contents/Info.plist"
cp Resources/AppIcon.icns "$contents/Resources/AppIcon.icns"
cp -R Resources/TechIcons "$contents/Resources/TechIcons"
cp -R Resources/RepoIcons "$contents/Resources/RepoIcons"
cp -R Resources/HostIcons "$contents/Resources/HostIcons"
codesign --force --sign - --timestamp=none "$bundle"

echo "Built $bundle"
case "$mode" in
  run)
    pkill -x ProjectHub >/dev/null 2>&1 || true
    /usr/bin/open -n "$bundle"
    ;;
  --build)
    ;;
  --verify)
    pkill -x ProjectHub >/dev/null 2>&1 || true
    /usr/bin/open -n "$bundle"
    sleep 2
    pgrep -x ProjectHub >/dev/null
    ;;
  --debug)
    lldb -- "$contents/MacOS/ProjectHub"
    ;;
  --logs|--telemetry)
    pkill -x ProjectHub >/dev/null 2>&1 || true
    /usr/bin/open -n "$bundle"
    /usr/bin/log stream --info --style compact --predicate 'process == "ProjectHub"'
    ;;
  *)
    echo "Usage: $0 [run|--build|--verify|--debug|--logs|--telemetry]" >&2
    exit 2
    ;;
esac
