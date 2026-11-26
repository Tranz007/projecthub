#!/bin/zsh
set -euo pipefail

mode="${1:-run}"
root="$(cd "$(dirname "$0")/.." && pwd)"
bundle="$root/dist/Project Hub.app"
contents="$bundle/Contents"

cd "$root"
architectures=(x86_64 arm64)
for architecture in "${architectures[@]}"; do
  triple="${architecture}-apple-macosx14.0"
  scratch="$root/.build/universal-$architecture"
  swift build -c release --triple "$triple" --scratch-path "$scratch"
  binary_dir="$(swift build -c release --triple "$triple" --scratch-path "$scratch" --show-bin-path)"
  binaries+=("$binary_dir/ProjectHub")
done

mkdir -p "$root/dist"
rm -rf "$bundle"
mkdir -p "$contents/MacOS" "$contents/Resources"
lipo -create "${binaries[@]}" -output "$contents/MacOS/ProjectHub"
cp Resources/Info.plist "$contents/Info.plist"
cp Resources/AppIcon.icns "$contents/Resources/AppIcon.icns"
cp -R Resources/TechIcons "$contents/Resources/TechIcons"
cp -R Resources/RepoIcons "$contents/Resources/RepoIcons"
cp -R Resources/HostIcons "$contents/Resources/HostIcons"
codesign --force --sign - --timestamp=none "$bundle"
codesign --verify --deep --strict "$bundle"

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
