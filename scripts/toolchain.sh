#!/bin/bash
set -euo pipefail
if [[ -z "${DEVELOPER_DIR:-}" ]]; then
    for candidate in /Applications/Xcode.app/Contents/Developer "$HOME/Downloads/Xcode.app/Contents/Developer"; do
        if [[ -d "$candidate" ]]; then
            export DEVELOPER_DIR="$candidate"
            break
        fi
    done
fi
export CLANG_MODULE_CACHE_PATH="${TMPDIR:-/tmp}/codex-signal-clang-cache"
swift_options=(--cache-path .build/cache --scratch-path .build)
if [[ "${SIGNAL_NESTED_SANDBOX:-0}" == 1 ]]; then
    swift_options+=(--disable-sandbox)
fi
