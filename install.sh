#!/bin/bash
set -e

APP_NAME="MacCleaner"
BUNDLE_DIR="/Applications/${APP_NAME}.app"
CONTENTS_DIR="${BUNDLE_DIR}/Contents"
MACOS_DIR="${CONTENTS_DIR}/MacOS"
RESOURCES_DIR="${CONTENTS_DIR}/Resources"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

echo "=== Building ${APP_NAME} ==="
cd "${SCRIPT_DIR}"
swift build -c release 2>&1

# Find the built binary
BINARY_PATH=$(swift build -c release --show-bin-path)/${APP_NAME}

if [ ! -f "${BINARY_PATH}" ]; then
    echo "Error: Build failed. Binary not found at ${BINARY_PATH}"
    exit 1
fi

echo "=== Creating app bundle ==="

# Remove old bundle if exists
if [ -d "${BUNDLE_DIR}" ]; then
    echo "Removing existing ${BUNDLE_DIR}..."
    rm -rf "${BUNDLE_DIR}"
fi

# Create bundle structure
mkdir -p "${MACOS_DIR}"
mkdir -p "${RESOURCES_DIR}"
FRAMEWORKS_DIR="${CONTENTS_DIR}/Frameworks"
mkdir -p "${FRAMEWORKS_DIR}"

# Copy binary
cp "${BINARY_PATH}" "${MACOS_DIR}/${APP_NAME}"

# Copy Info.plist
cp "${SCRIPT_DIR}/Info.plist" "${CONTENTS_DIR}/Info.plist"

# Copy any frameworks emitted alongside the binary (Sparkle, etc.) so the app
# can load @rpath/<Framework>.framework from Contents/Frameworks at runtime.
BIN_DIR=$(swift build -c release --show-bin-path)
for fw in "${BIN_DIR}"/*.framework; do
    [ -d "${fw}" ] || continue
    echo "Embedding $(basename "${fw}")"
    cp -R "${fw}" "${FRAMEWORKS_DIR}/"
done

# SwiftPM bakes @loader_path as the only @rpath, which resolves to Contents/MacOS.
# Add the conventional Cocoa rpath so dyld looks in Contents/Frameworks too.
# Idempotent: install_name_tool errors if the path already exists, so swallow that.
install_name_tool -add_rpath "@executable_path/../Frameworks" \
    "${MACOS_DIR}/${APP_NAME}" 2>/dev/null || true

# Generate a simple app icon (blue circle with broom)
# We'll create a basic icns from a simple PNG using sips
ICON_DIR=$(mktemp -d)
ICONSET_DIR="${ICON_DIR}/${APP_NAME}.iconset"
mkdir -p "${ICONSET_DIR}"

# Create a simple icon using Python (available on macOS)
python3 - "${ICONSET_DIR}" <<'PYEOF'
import sys, struct, zlib

def create_png(width, height):
    """Create a simple blue circle icon as PNG."""
    pixels = []
    cx, cy = width / 2.0, height / 2.0
    r = min(cx, cy) * 0.85
    inner_r = r * 0.45

    for y in range(height):
        row = []
        for x in range(width):
            dx, dy = x - cx, y - cy
            dist = (dx*dx + dy*dy) ** 0.5

            if dist <= r:
                # Gradient blue circle
                t = dist / r
                red = int(30 + t * 20)
                green = int(120 + t * 30)
                blue = int(230 - t * 30)
                alpha = 255
                if dist > r - 2:
                    alpha = int(255 * (r - dist) / 2)
                    alpha = max(0, min(255, alpha))
                row.append((red, green, blue, alpha))
            else:
                row.append((0, 0, 0, 0))
        pixels.append(row)

    # Encode as PNG
    def make_chunk(chunk_type, data):
        c = chunk_type + data
        return struct.pack('>I', len(data)) + c + struct.pack('>I', zlib.crc32(c) & 0xFFFFFFFF)

    sig = b'\x89PNG\r\n\x1a\n'
    ihdr = make_chunk(b'IHDR', struct.pack('>IIBBBBB', width, height, 8, 6, 0, 0, 0))

    raw = b''
    for row in pixels:
        raw += b'\x00'
        for r, g, b, a in row:
            raw += struct.pack('BBBB', r, g, b, a)

    idat = make_chunk(b'IDAT', zlib.compress(raw))
    iend = make_chunk(b'IEND', b'')

    return sig + ihdr + idat + iend

iconset_dir = sys.argv[1]
sizes = [16, 32, 64, 128, 256, 512]
for s in sizes:
    png = create_png(s, s)
    with open(f"{iconset_dir}/icon_{s}x{s}.png", 'wb') as f:
        f.write(png)
    # @2x versions
    if s <= 256:
        png2x = create_png(s*2, s*2)
        with open(f"{iconset_dir}/icon_{s}x{s}@2x.png", 'wb') as f:
            f.write(png2x)

print("Icon PNGs created.")
PYEOF

# Convert iconset to icns
if command -v iconutil &>/dev/null; then
    iconutil -c icns "${ICONSET_DIR}" -o "${RESOURCES_DIR}/AppIcon.icns" 2>/dev/null && \
        echo "App icon created." || echo "Warning: Could not create icon. App will use default icon."
fi
rm -rf "${ICON_DIR}"

# Final ad-hoc resigning — done LAST, after every file in the bundle exists,
# so the seal covers everything. Without this, dyld rejects the binary on
# launch ("library not loaded") because modifying the binary's rpath
# invalidates the original ad-hoc signature.
echo "=== Signing bundle ==="
xattr -cr "${BUNDLE_DIR}" 2>/dev/null || true
codesign --force --deep --sign - "${BUNDLE_DIR}" 2>&1 | tail -3
codesign --verify --verbose "${BUNDLE_DIR}" 2>&1 | tail -3 || \
    echo "Warning: codesign verification reported issues — the app may still launch but Gatekeeper might complain on first run."

echo ""
echo "=== Installation complete! ==="
echo "App installed to: ${BUNDLE_DIR}"
echo ""
echo "You can now:"
echo "  1. Find '${APP_NAME}' in Launchpad"
echo "  2. Open it from /Applications"
echo "  3. Or run: open '${BUNDLE_DIR}'"
echo ""

# Ask to open
read -p "Open ${APP_NAME} now? (y/n) " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    open "${BUNDLE_DIR}"
fi
