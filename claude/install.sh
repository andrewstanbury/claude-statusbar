#!/usr/bin/env bash
# Deprecated: the installer is now unified at the repo root (component-aware,
# composes settings.json). This shim forwards so `bash claude/install.sh` and
# any existing muscle memory keep working.
exec bash "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/install.sh" "$@"
