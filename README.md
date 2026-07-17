# RunPod LTX 2.3 10Eros v12 automatic template

This package configures an existing RunPod ComfyUI image so a fresh Pod automatically installs the workflow's custom nodes, downloads the 10Eros v12 model and supporting files, installs the workflow, and starts ComfyUI.

## Important limitation

A RunPod template stores image/settings, not arbitrary files from your computer. The bootstrap files therefore need a small public URL. The easiest method is a public GitHub repository containing this folder. Large models are **not** stored in GitHub; the script downloads them directly from Civitai and Hugging Face each time.

## One-time GitHub setup

1. Create a new public GitHub repository, for example `runpod-ltx23-10eros`.
2. Upload the contents of this folder to the repository root. Do not upload the ZIP itself as the only file.
3. Your raw base URL will look like:

   `https://raw.githubusercontent.com/YOUR_GITHUB_NAME/runpod-ltx23-10eros/main`

## Create the RunPod template

Use your existing ComfyUI template (`n8lwel36v3`) as the base or duplicate its settings.

Add these environment variables:

| Variable | Value |
|---|---|
| `RUNPOD_SETUP_BASE_URL` | Your raw GitHub base URL shown above |
| `CIVITAI_TOKEN` | Your Civitai API key, when required |
| `HF_TOKEN` | Your Hugging Face token; optional for public files |
| `COMFY_PORT` | `8188` |
| `UPDATE_COMFYUI` | `1` |

Set the container/Docker command to:

```bash
bash -lc 'curl -fsSL "$RUNPOD_SETUP_BASE_URL/bootstrap.sh" | bash'
```

Expose HTTP port `8188`. Keep any other ports from the original template that you use for JupyterLab or file management.

## Storage sizing

Use at least **75 GB** of writable disk; **90 GB** is safer for models, node dependencies, temporary `.part` downloads, input files, and generated videos. A 24 GB GPU can run the workflow using its memory-saving/offload behavior, but higher-VRAM GPUs will be more comfortable.

## First launch behavior

The first ComfyUI connection will not be ready until the downloads finish. Open the Pod logs to watch progress. When setup completes, the script starts ComfyUI on port 8188. The workflow will be available as:

`LTX23_10Eros_v12_RunPod.json`

## What is included

- `ltx2310eros_v12.safetensors` from the Civitai link supplied by the user
- Gemma 3 12B FP8 text encoder and LTX 2.3 projection encoder
- Video and audio VAEs
- LTX 2.3 spatial upscaler
- MelBandRoFormer
- ID, IC/control, detailer, and distilled-support LoRAs
- Custom nodes detected in the supplied workflow
- A workflow copy switched from the standard FP8 branch to 10Eros v12

The unused standard LTX FP8 and GGUF base models are intentionally excluded to avoid roughly tens of gigabytes of unnecessary downloading.

## Troubleshooting

- `Could not locate ComfyUI`: add `COMFYUI_DIR` as an environment variable with the actual ComfyUI directory.
- Civitai 401/403: confirm `CIVITAI_TOKEN` is correct.
- Hugging Face 401/403: accept any required model license and set `HF_TOKEN`.
- A missing-node warning after launch: check Pod logs for the corresponding Git or Manager installation failure.
- To retry a partial download, restart the Pod; `.part` files resume when the same writable volume still exists.
