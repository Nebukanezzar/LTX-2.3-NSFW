# RunPod LTX 2.3 / 10Eros automatic setup

This revision incorporates the fixes discovered while building the working RunPod installation.

## Important fixes included

- Preserves proper newlines and tab-separated TSV formatting.
- Uses `python3` when available.
- Installs `portaudio19-dev` before TTS Audio Suite.
- Prevents Impact Pack's SAM2 setup from replacing the CUDA PyTorch build.
- Pins Kornia to `0.8.2` after all node installations.
- Uses the confirmed 10Eros download URL.
- Adds the missing LayerStyle Advance and CRT node repositories.
- Adds all required LTX 2.3 support models and LoRAs.
- Resumes partial downloads and checks for obviously incomplete files.
- Uses `git fetch` plus `git reset --hard origin/main` rather than fragile pulls.
- Starts ComfyUI with `python3 -u` and `--enable-cors-header`.

The old `LayerColor: Brightness Contrast` node remains disabled in the working workflow. It is obsolete; use the newer LayerStyle brightness/contrast node if color correction is needed later.

## Files to replace in GitHub

Upload these files to the repository root, replacing the current versions:

- `bootstrap.sh`
- `custom_nodes.tsv`
- `models.tsv`
- `registry_nodes.txt`
- `README.md`

Keep the existing `workflows` folder.

GitHub's web editor must preserve line breaks. Do not paste the files as one long line.

## RunPod environment variables

```text
RUNPOD_SETUP_BASE_URL=https://raw.githubusercontent.com/Nebukanezzar/LTX-2.3-NSFW/main
CIVITAI_TOKEN=your_current_civitai_token
HF_TOKEN=optional_hugging_face_token
COMFYUI_DIR=/workspace/runpod-slim/ComfyUI
COMFY_PORT=8188
UPDATE_COMFYUI=0
START_COMFYUI=1
```

Leaving `UPDATE_COMFYUI=0` is safer for a known-working base image. Set it to `1` only when intentionally testing a ComfyUI core update.

## Container command

```bash
bash -lc 'curl -fsSL "$RUNPOD_SETUP_BASE_URL/bootstrap.sh" | bash'
```

## Manual test command on a running pod

```bash
RUNPOD_SETUP_BASE_URL="https://raw.githubusercontent.com/Nebukanezzar/LTX-2.3-NSFW/main" \
CIVITAI_TOKEN="YOUR_CURRENT_TOKEN" \
COMFYUI_DIR="/workspace/runpod-slim/ComfyUI" \
UPDATE_COMFYUI=0 \
START_COMFYUI=1 \
bash -c 'curl -fsSL "$RUNPOD_SETUP_BASE_URL/bootstrap.sh" | bash'
```

Never commit a Civitai or Hugging Face token into GitHub.

## Recommended clean-pod test

Run the revised bootstrap on a fresh pod with at least 90 GB of writable storage. Watch the pod logs until `Setup complete` appears. This is the only reliable way to prove that no package was inherited from the pod used during debugging.
