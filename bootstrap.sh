#!/usr/bin/env bash
set -Eeuo pipefail

log() { printf '\n[%s] %s\n' "$(date '+%H:%M:%S')" "$*"; }
die() { echo "ERROR: $*" >&2; exit 1; }

SCRIPT_URL="${RUNPOD_SETUP_BASE_URL:-}"
INSTALL_ROOT="${RUNPOD_SETUP_DIR:-/workspace/runpod-ltx23-10eros}"
COMFY_PORT="${COMFY_PORT:-8188}"
UPDATE_COMFYUI="${UPDATE_COMFYUI:-1}"

# When piped from curl, retrieve the companion files from the same GitHub raw directory.
if [[ ! -f "${INSTALL_ROOT}/models.tsv" ]]; then
  [[ -n "$SCRIPT_URL" ]] || die "RUNPOD_SETUP_BASE_URL is not set. See README.md."
  mkdir -p "$INSTALL_ROOT/workflows"
  for file in models.tsv custom_nodes.tsv registry_nodes.txt workflows/LTX23_10Eros_v12_RunPod.json; do
    mkdir -p "${INSTALL_ROOT}/$(dirname "$file")"
    curl -fL --retry 5 --retry-delay 3 "${SCRIPT_URL%/}/$file" -o "${INSTALL_ROOT}/$file"
  done
fi

find_comfy() {
  local candidates=(
    "${COMFYUI_DIR:-}"
    /workspace/ComfyUI
    /workspace/comfyui/ComfyUI
    /workspace/runpod-slim/ComfyUI
    /ComfyUI
    /app/ComfyUI
  )
  local p
  for p in "${candidates[@]}"; do
    [[ -n "$p" && -f "$p/main.py" ]] && { echo "$p"; return 0; }
  done
  find /workspace /app / -maxdepth 4 -type f -name main.py -path '*/ComfyUI/main.py' 2>/dev/null | head -n1 | xargs -r dirname
}

COMFYUI_DIR="$(find_comfy)"
[[ -n "$COMFYUI_DIR" && -f "$COMFYUI_DIR/main.py" ]] || die "Could not locate ComfyUI. Set COMFYUI_DIR in the template."
PYTHON_BIN="${PYTHON_BIN:-$(command -v python3 || command -v python)}"
[[ -x "$PYTHON_BIN" ]] || die "Python was not found."

log "ComfyUI: $COMFYUI_DIR"
log "Python: $PYTHON_BIN"

if [[ "$UPDATE_COMFYUI" == "1" && -d "$COMFYUI_DIR/.git" ]]; then
  log "Updating ComfyUI"
  git -C "$COMFYUI_DIR" pull --ff-only || echo "ComfyUI update skipped because the image has local changes."
fi

mkdir -p "$COMFYUI_DIR/custom_nodes"
while IFS=$'\t' read -r dirname repo; do
  [[ -z "${dirname:-}" || "$dirname" == \#* ]] && continue
  target="$COMFYUI_DIR/custom_nodes/$dirname"
  if [[ -d "$target/.git" ]]; then
    log "Updating node: $dirname"
    git -C "$target" pull --ff-only || true
  elif [[ -e "$target" ]]; then
    log "Node exists without Git metadata: $dirname"
  else
    log "Installing node: $dirname"
    git clone --depth 1 "$repo" "$target"
  fi
  if [[ -f "$target/requirements.txt" ]]; then
    "$PYTHON_BIN" -m pip install --disable-pip-version-check -r "$target/requirements.txt"
  fi
  if [[ -f "$target/install.py" ]]; then
    (cd "$target" && "$PYTHON_BIN" install.py) || true
  fi
done < "$INSTALL_ROOT/custom_nodes.tsv"

log "Applying LTXVideo Kornia compatibility fix"
"$PYTHON_BIN" -m pip install --disable-pip-version-check --upgrade "kornia<0.8.3"

# Install registry-only nodes through the Manager CLI if available.
MANAGER_DIR=""

# Install registry-only nodes through the Manager CLI if available.
MANAGER_DIR=""
for p in "$COMFYUI_DIR/custom_nodes/ComfyUI-Manager" "$COMFYUI_DIR/custom_nodes/comfyui-manager"; do
  [[ -f "$p/cm-cli.py" ]] && MANAGER_DIR="$p" && break
done
if [[ -n "$MANAGER_DIR" ]]; then
  while IFS= read -r node; do
    [[ -z "$node" || "$node" == \#* ]] && continue
    log "Manager install/check: $node"
    (cd "$MANAGER_DIR" && "$PYTHON_BIN" cm-cli.py install "$node" --mode remote) || \
      echo "WARNING: Manager could not install $node; ComfyUI will report it if required."
  done < "$INSTALL_ROOT/registry_nodes.txt"
else
  echo "WARNING: ComfyUI-Manager CLI not found; registry-only nodes were skipped."
fi

# aria2 is preferred for large resumable downloads; curl is the fallback.
if ! command -v aria2c >/dev/null 2>&1; then
  apt-get update -qq && apt-get install -y -qq aria2 >/dev/null 2>&1 || true
fi

download_file() {
  local rel="$1" url="$2" auth="$3" dest="$COMFYUI_DIR/$1" tmp="${COMFYUI_DIR}/$1.part"
  mkdir -p "$(dirname "$dest")"
  [[ -s "$dest" ]] && { log "Already present: $rel"; return; }

  local final_url="$url" header=()
  if [[ "$auth" == "civitai" && -n "${CIVITAI_TOKEN:-}" ]]; then
    if [[ "$final_url" == *\?* ]]; then final_url="${final_url}&token=${CIVITAI_TOKEN}"; else final_url="${final_url}?token=${CIVITAI_TOKEN}"; fi
  elif [[ "$auth" == "huggingface" && -n "${HF_TOKEN:-}" ]]; then
    header=(-H "Authorization: Bearer ${HF_TOKEN}")
  fi

  log "Downloading: $rel"
  if command -v aria2c >/dev/null 2>&1; then
    local aria_header=()
    [[ ${#header[@]} -gt 0 ]] && aria_header=(--header="Authorization: Bearer ${HF_TOKEN}")
    aria2c -c -x 8 -s 8 --file-allocation=none --allow-overwrite=true \
      "${aria_header[@]}" -d "$(dirname "$dest")" -o "$(basename "$tmp")" "$final_url"
  else
    curl -fL --retry 8 --retry-all-errors -C - "${header[@]}" "$final_url" -o "$tmp"
  fi
  [[ -s "$tmp" ]] || die "Download produced an empty file: $rel"
  mv -f "$tmp" "$dest"
}

while IFS=$'\t' read -r rel url auth; do
  [[ -z "${rel:-}" || "$rel" == \#* ]] && continue
  download_file "$rel" "$url" "$auth"
done < "$INSTALL_ROOT/models.tsv"

WORKFLOW_DIR="$COMFYUI_DIR/user/default/workflows"
mkdir -p "$WORKFLOW_DIR"
cp -f "$INSTALL_ROOT/workflows/LTX23_10Eros_v12_RunPod.json" "$WORKFLOW_DIR/"

log "Validating required files"
missing=0
while IFS=$'\t' read -r rel _url _auth; do
  [[ -z "${rel:-}" || "$rel" == \#* ]] && continue
  if [[ ! -s "$COMFYUI_DIR/$rel" ]]; then echo "MISSING: $rel"; missing=1; fi
done < "$INSTALL_ROOT/models.tsv"
[[ "$missing" == 0 ]] || die "One or more model downloads failed."

log "Setup complete."

if ss -ltn 2>/dev/null | grep -q ":${COMFY_PORT} "; then
  log "ComfyUI is already running on port $COMFY_PORT."
  log "Restart ComfyUI from the RunPod interface so it loads the newly installed nodes."
else
  log "Starting ComfyUI on port $COMFY_PORT"
  cd "$COMFYUI_DIR"
  exec "$PYTHON_BIN" main.py --listen 0.0.0.0 --port "$COMFY_PORT"
fi
