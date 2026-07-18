#!/usr/bin/env bash
set -Eeuo pipefail

log() { printf '\n[%s] %s\n' "$(date '+%H:%M:%S')" "$*"; }
warn() { printf '\nWARNING: %s\n' "$*" >&2; }
die() { printf '\nERROR: %s\n' "$*" >&2; exit 1; }

SETUP_BASE_URL="${RUNPOD_SETUP_BASE_URL:-}"
INSTALL_ROOT="${RUNPOD_SETUP_DIR:-/workspace/runpod-ltx23-10eros}"
COMFY_PORT="${COMFY_PORT:-8188}"
UPDATE_COMFYUI="${UPDATE_COMFYUI:-0}"
START_COMFYUI="${START_COMFYUI:-1}"
REFRESH_SETUP_FILES="${REFRESH_SETUP_FILES:-1}"
KORNIA_VERSION="${KORNIA_VERSION:-0.8.2}"
MIN_FREE_GB="${MIN_FREE_GB:-20}"

fetch_setup_files() {
  [[ -n "$SETUP_BASE_URL" ]] || die "RUNPOD_SETUP_BASE_URL is not set."
  mkdir -p "$INSTALL_ROOT/workflows"
  local files=("models.tsv" "custom_nodes.tsv" "registry_nodes.txt")
  for file in "${files[@]}"; do
    curl -fL --retry 5 --retry-delay 3 --retry-all-errors \
      "${SETUP_BASE_URL%/}/$file" -o "${INSTALL_ROOT}/$file"
  done
  curl -fL --retry 3 --retry-delay 3 --retry-all-errors \
    "${SETUP_BASE_URL%/}/workflows/LTX23_10Eros_v12_RunPod.json" \
    -o "${INSTALL_ROOT}/workflows/LTX23_10Eros_v12_RunPod.json" || true
}

if [[ "$REFRESH_SETUP_FILES" == "1" || ! -s "$INSTALL_ROOT/models.tsv" || ! -s "$INSTALL_ROOT/custom_nodes.tsv" || ! -s "$INSTALL_ROOT/registry_nodes.txt" ]]; then
  log "Retrieving setup files"
  fetch_setup_files
fi

find_comfy() {
  local candidates=("${COMFYUI_DIR:-}" "/workspace/runpod-slim/ComfyUI" "/workspace/ComfyUI" "/workspace/comfyui/ComfyUI" "/ComfyUI" "/app/ComfyUI")
  local p
  for p in "${candidates[@]}"; do
    if [[ -n "$p" && -f "$p/main.py" ]]; then printf '%s\n' "$p"; return 0; fi
  done
  find /workspace /app / -maxdepth 5 -type f -name main.py -path '*/ComfyUI/main.py' 2>/dev/null | head -n 1 | xargs -r dirname
}

COMFYUI_DIR="$(find_comfy)"
[[ -n "$COMFYUI_DIR" && -f "$COMFYUI_DIR/main.py" ]] || die "Could not locate ComfyUI. Set COMFYUI_DIR in the RunPod template."

if [[ -n "${PYTHON_BIN:-}" ]]; then :
elif [[ -x "$COMFYUI_DIR/.venv-cu128/bin/python" ]]; then PYTHON_BIN="$COMFYUI_DIR/.venv-cu128/bin/python"
elif [[ -x "$COMFYUI_DIR/.venv/bin/python" ]]; then PYTHON_BIN="$COMFYUI_DIR/.venv/bin/python"
else PYTHON_BIN="$(command -v python3 || command -v python || true)"
fi
[[ -n "$PYTHON_BIN" && -x "$PYTHON_BIN" ]] || die "Python was not found."

log "ComfyUI: $COMFYUI_DIR"
log "Python: $PYTHON_BIN"
available_kb="$(df -Pk "$COMFYUI_DIR" | awk 'NR==2 {print $4}')"
required_kb=$((MIN_FREE_GB * 1024 * 1024))
(( available_kb >= required_kb )) || die "Only $((available_kb / 1024 / 1024)) GiB free; at least ${MIN_FREE_GB} GiB is required."
log "Free space: $((available_kb / 1024 / 1024)) GiB"

export DEBIAN_FRONTEND=noninteractive
export PIP_NO_CACHE_DIR=1
if command -v apt-get >/dev/null 2>&1; then
  log "Installing system packages"
  apt-get update -qq
  apt-get install -y -qq aria2 curl git ffmpeg libsndfile1 portaudio19-dev build-essential >/dev/null
  apt-get clean
  rm -rf /var/lib/apt/lists/*
fi

"$PYTHON_BIN" -m pip install --disable-pip-version-check --no-cache-dir -U pip setuptools wheel huggingface_hub

if [[ "$UPDATE_COMFYUI" == "1" && -d "$COMFYUI_DIR/.git" ]]; then
  log "Updating ComfyUI"
  git -C "$COMFYUI_DIR" fetch origin
  git -C "$COMFYUI_DIR" reset --hard origin/main
fi

mkdir -p "$COMFYUI_DIR/custom_nodes"

install_requirements() {
  local dirname="$1" target="$2"
  [[ -f "$target/requirements.txt" ]] || return 0
  if [[ "$dirname" == "ComfyUI-Impact-Pack" ]]; then
    log "Installing Impact Pack requirements without SAM2/PyTorch replacement"
    grep -v -e 'facebookresearch/sam2' -e '^sam2' "$target/requirements.txt" > /tmp/impact-pack-requirements.txt || true
    [[ ! -s /tmp/impact-pack-requirements.txt ]] || "$PYTHON_BIN" -m pip install --disable-pip-version-check --no-cache-dir -r /tmp/impact-pack-requirements.txt
    return 0
  fi
  "$PYTHON_BIN" -m pip install --disable-pip-version-check --no-cache-dir -r "$target/requirements.txt"
}

while IFS=$'\t' read -r dirname repo; do
  [[ -z "${dirname:-}" || "$dirname" == \#* ]] && continue
  target="$COMFYUI_DIR/custom_nodes/$dirname"
  if [[ -d "$target/.git" ]]; then
    log "Updating node: $dirname"
    git -C "$target" fetch origin
    git -C "$target" reset --hard origin/main || true
  elif [[ -e "$target" ]]; then
    log "Node exists without Git metadata: $dirname"
  else
    log "Installing node: $dirname"
    git clone --depth 1 "$repo" "$target"
  fi
  install_requirements "$dirname" "$target"
  [[ "$dirname" == "ComfyUI-Impact-Pack" ]] && continue
  if [[ "$dirname" == "TTS-Audio-Suite" && -f "$target/install.py" ]]; then
    log "Running TTS Audio Suite installer"
    (cd "$target" && "$PYTHON_BIN" install.py)
  elif [[ -f "$target/install.py" ]]; then
    log "Running installer: $dirname"
    (cd "$target" && "$PYTHON_BIN" install.py) || warn "Optional install.py step failed for $dirname"
  fi
done < "$INSTALL_ROOT/custom_nodes.tsv"

LAYERSTYLE_SAM2="$COMFYUI_DIR/custom_nodes/ComfyUI_LayerStyle_Advance/sam2"
if [[ -e "$LAYERSTYLE_SAM2" ]]; then
  log "Disabling LayerStyle Advance bundled SAM2"
  rm -rf "${LAYERSTYLE_SAM2}.disabled"
  mv "$LAYERSTYLE_SAM2" "${LAYERSTYLE_SAM2}.disabled"
fi

log "Installing official SAM2 without replacing Torch"
"$PYTHON_BIN" -m pip install --disable-pip-version-check --no-cache-dir --no-build-isolation --no-deps "git+https://github.com/facebookresearch/sam2.git"
"$PYTHON_BIN" - <<'PY'
import sam2
print(f"SAM2 validation OK: {sam2.__file__}")
if "ComfyUI_LayerStyle_Advance" in str(sam2.__file__):
    raise RuntimeError("LayerStyle Advance SAM2 is still shadowing the official SAM2 package")
PY

MANAGER_DIR=""
for p in "$COMFYUI_DIR/custom_nodes/ComfyUI-Manager" "$COMFYUI_DIR/custom_nodes/comfyui-manager"; do
  if [[ -f "$p/cm-cli.py" ]]; then MANAGER_DIR="$p"; break; fi
done
if [[ -n "$MANAGER_DIR" ]]; then
  while IFS= read -r node; do
    [[ -z "$node" || "$node" == \#* ]] && continue
    log "Manager install/check: $node"
    (cd "$MANAGER_DIR" && "$PYTHON_BIN" cm-cli.py install "$node" --mode remote) || warn "Manager could not install $node"
  done < "$INSTALL_ROOT/registry_nodes.txt"
else
  warn "ComfyUI-Manager CLI was not found; registry-only checks were skipped."
fi

log "Pinning Kornia compatibility version: $KORNIA_VERSION"
"$PYTHON_BIN" -m pip install --disable-pip-version-check --no-cache-dir --force-reinstall --no-deps "kornia==$KORNIA_VERSION"
"$PYTHON_BIN" - <<'PY'
import kornia
from kornia.geometry.transform.pyramid import pad
print(f"Kornia validation OK: {kornia.__version__}")
PY

download_file() {
  local rel="$1" url="$2" auth="${3:-none}" minimum_bytes="${4:-1}"
  local dest="$COMFYUI_DIR/$rel" part="${dest}.part" final_url="$url"
  mkdir -p "$(dirname "$dest")"
  if [[ -s "$dest" ]]; then
    local current_size
    current_size="$(stat -c '%s' "$dest")"
    if (( current_size >= minimum_bytes )); then log "Already present: $rel"; return 0; fi
    warn "Existing file is too small and will be redownloaded: $rel"
    rm -f "$dest"
  fi

  local headers=()
  if [[ "$auth" == "civitai" ]]; then
    [[ -n "${CIVITAI_TOKEN:-}" ]] || die "CIVITAI_TOKEN is required for $rel"
    if [[ "$final_url" == *\?* ]]; then final_url="${final_url}&token=${CIVITAI_TOKEN}"; else final_url="${final_url}?token=${CIVITAI_TOKEN}"; fi
  elif [[ "$auth" == "huggingface" && -n "${HF_TOKEN:-}" ]]; then
    headers=(--header="Authorization: Bearer ${HF_TOKEN}")
  fi

  log "Downloading: $rel"
  if command -v aria2c >/dev/null 2>&1; then
    local aria_headers=() connections=8 splits=8
    if [[ "$auth" == "huggingface" ]]; then
      connections=1
      splits=1
      [[ -z "${HF_TOKEN:-}" ]] || aria_headers=(--header="Authorization: Bearer ${HF_TOKEN}")
    fi
    aria2c -c -x "$connections" -s "$splits" --min-split-size=16M --file-allocation=none \
      --allow-overwrite=true --auto-file-renaming=false --max-tries=8 --retry-wait=3 \
      --timeout=60 --connect-timeout=30 --summary-interval=10 "${aria_headers[@]}" \
      -d "$(dirname "$part")" -o "$(basename "$part")" "$final_url"
  else
    curl -fL --retry 8 --retry-delay 3 --retry-all-errors -C - "${headers[@]}" "$final_url" -o "$part"
  fi

  [[ -s "$part" ]] || die "Download produced an empty file: $rel"
  local downloaded_size
  downloaded_size="$(stat -c '%s' "$part")"
  (( downloaded_size >= minimum_bytes )) || die "Downloaded file is smaller than expected: $rel ($downloaded_size bytes)"
  mv -f "$part" "$dest"
  rm -f "${part}.aria2"
}

while IFS=$'\t' read -r rel url auth minimum_bytes; do
  [[ -z "${rel:-}" || "$rel" == \#* ]] && continue
  download_file "$rel" "$url" "$auth" "${minimum_bytes:-1}"
done < "$INSTALL_ROOT/models.tsv"

WORKFLOW_SOURCE="$INSTALL_ROOT/workflows/LTX23_10Eros_v12_RunPod.json"
WORKFLOW_DIR="$COMFYUI_DIR/user/default/workflows"
if [[ -s "$WORKFLOW_SOURCE" ]]; then mkdir -p "$WORKFLOW_DIR"; cp -f "$WORKFLOW_SOURCE" "$WORKFLOW_DIR/"; log "Workflow installed"; fi

log "Validating required files"
missing=0
while IFS=$'\t' read -r rel _url _auth minimum_bytes; do
  [[ -z "${rel:-}" || "$rel" == \#* ]] && continue
  full="$COMFYUI_DIR/$rel"
  if [[ ! -s "$full" ]]; then echo "MISSING: $rel"; missing=1; continue; fi
  size="$(stat -c '%s' "$full")"
  if (( size < ${minimum_bytes:-1} )); then echo "TOO SMALL: $rel ($size bytes)"; missing=1; fi
done < "$INSTALL_ROOT/models.tsv"
[[ "$missing" == "0" ]] || die "One or more model downloads failed validation."

log "Setup complete"
if [[ "$START_COMFYUI" == "1" ]]; then
  log "Starting ComfyUI on port $COMFY_PORT"
  cd "$COMFYUI_DIR"
  exec "$PYTHON_BIN" -u main.py --listen 0.0.0.0 --port "$COMFY_PORT" --enable-cors-header
else
  log "START_COMFYUI=0, so ComfyUI was not launched."
fi
