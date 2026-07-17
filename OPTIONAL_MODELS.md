# Optional files intentionally omitted

These nodes are bypassed in the supplied workflow and are not needed for the selected 10Eros setup:

- Standard LTX 2.3 FP8 base model
- LTX 2.3 GGUF base model
- RIFE `rife49.pth`
- DWPose `yolox_l.onnx`
- DWPose `dw-ll_ucoco_384_bs5.torchscript.pt`
- SageAttention packages (the Sage patch node is bypassed)

They can be added to `models.tsv` later if those branches are enabled.
