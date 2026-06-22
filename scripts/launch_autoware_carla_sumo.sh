#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Thin wrapper for the full CARLA + SUMO + Autoware launcher. Keep behavior in
# CARLA/start_autoware_carla_sumo.sh so both entrypoints stay consistent.
export CARLA_ARGS="${CARLA_ARGS:--prefernvidia -quality-level=Epic -nosound}"

exec "${REPO_ROOT}/CARLA/start_autoware_carla_sumo.sh" "$@"
