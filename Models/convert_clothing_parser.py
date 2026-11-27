#!/usr/bin/env python3
"""Convert the SegFormer-B2 clothing parser to a Core ML package.

The source model is ``mattmdjaga/segformer_b2_clothes`` on Hugging Face, pinned to
an exact revision so builds are reproducible. The converted model:

* takes a 512x512 RGB image (``image``) and bakes in the ImageNet normalisation,
* upsamples the logits to 512x512 and returns the per-pixel class index
  (``labels``, shape [1, 512, 512], int32) so the app never handles raw logits.

Usage::

    python Models/convert_clothing_parser.py --output Models/build/ClothingParserModel.mlpackage

On macOS the script can also validate the Core ML output against PyTorch
(``--validate-image path.jpg``); prediction is not available on Linux.
"""
from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

import numpy as np
import torch
from PIL import Image

MODEL_ID = "mattmdjaga/segformer_b2_clothes"
MODEL_REVISION = "584abc1e1d260e23c0fc627c5217a09b2b461046"
INPUT_SIZE = 512
LABELS = [
    "Background", "Hat", "Hair", "Sunglasses", "Upper-clothes", "Skirt", "Pants", "Dress", "Belt",
    "Left-shoe", "Right-shoe", "Face", "Left-leg", "Right-leg", "Left-arm", "Right-arm", "Bag", "Scarf",
]
IMAGENET_MEAN = (0.485, 0.456, 0.406)
IMAGENET_STD = (0.229, 0.224, 0.225)


class ParserWrapper(torch.nn.Module):
    """Normalises a [0, 1] RGB tensor, runs SegFormer and returns class indices."""

    def __init__(self, model: torch.nn.Module) -> None:
        super().__init__()
        self.model = model
        self.register_buffer("mean", torch.tensor(IMAGENET_MEAN).view(1, 3, 1, 1))
        self.register_buffer("std", torch.tensor(IMAGENET_STD).view(1, 3, 1, 1))

    def forward(self, image: torch.Tensor) -> torch.Tensor:  # image: [1, 3, H, W] in [0, 1]
        x = (image - self.mean) / self.std
        logits = self.model(pixel_values=x, return_dict=False)[0]
        logits = torch.nn.functional.interpolate(
            logits, size=(INPUT_SIZE, INPUT_SIZE), mode="bilinear", align_corners=False
        )
        return torch.argmax(logits, dim=1).to(torch.int32)


def load_wrapper() -> ParserWrapper:
    from transformers import SegformerForSemanticSegmentation

    model = SegformerForSemanticSegmentation.from_pretrained(MODEL_ID, revision=MODEL_REVISION)
    model.eval()
    config_labels = [model.config.id2label[i] for i in range(len(model.config.id2label))]
    if config_labels != LABELS:
        raise SystemExit(f"Unexpected label set: {config_labels}")
    return ParserWrapper(model).eval()


def image_tensor(path: Path) -> torch.Tensor:
    img = Image.open(path).convert("RGB").resize((INPUT_SIZE, INPUT_SIZE), Image.BILINEAR)
    arr = np.asarray(img).astype(np.float32) / 255.0
    return torch.from_numpy(arr).permute(2, 0, 1).unsqueeze(0)


def convert(output: Path, quantize: bool) -> None:
    import coremltools as ct

    wrapper = load_wrapper()
    example = torch.rand(1, 3, INPUT_SIZE, INPUT_SIZE)
    with torch.no_grad():
        traced = torch.jit.trace(wrapper, example, strict=False)

    mlmodel = ct.convert(
        traced,
        inputs=[
            ct.ImageType(
                name="image",
                shape=(1, 3, INPUT_SIZE, INPUT_SIZE),
                scale=1.0 / 255.0,
                bias=[0.0, 0.0, 0.0],
                color_layout=ct.colorlayout.RGB,
            )
        ],
        outputs=[ct.TensorType(name="labels", dtype=np.int32)],
        convert_to="mlprogram",
        minimum_deployment_target=ct.target.iOS17,
        compute_precision=ct.precision.FLOAT16,
    )
    if quantize:
        from coremltools.optimize.coreml import (
            OpLinearQuantizerConfig,
            OptimizationConfig,
            linear_quantize_weights,
        )

        config = OptimizationConfig(
            global_config=OpLinearQuantizerConfig(mode="linear_symmetric", weight_threshold=2048)
        )
        mlmodel = linear_quantize_weights(mlmodel, config=config)

    mlmodel.short_description = (
        "Clothing parser (SegFormer-B2, 18 classes). Input: 512x512 RGB. Output: per-pixel class index."
    )
    mlmodel.author = f"Converted from {MODEL_ID}@{MODEL_REVISION[:12]}"
    mlmodel.license = "See NOTICE: SegFormer / ATR-derived weights, non-commercial use."
    mlmodel.user_defined_metadata["labels"] = json.dumps(LABELS)
    mlmodel.user_defined_metadata["source_revision"] = MODEL_REVISION
    mlmodel.version = "1.0"
    output.parent.mkdir(parents=True, exist_ok=True)
    mlmodel.save(str(output))
    print(f"Saved {output}")


def validate(package: Path, images: list[Path], min_agreement: float) -> None:
    """Compare Core ML labels with the PyTorch reference (macOS only)."""
    import coremltools as ct

    wrapper = load_wrapper()
    mlmodel = ct.models.MLModel(str(package), compute_units=ct.ComputeUnit.CPU_ONLY)
    worst = 1.0
    for path in images:
        tensor = image_tensor(path)
        with torch.no_grad():
            reference = wrapper(tensor)[0].numpy()
        pil = Image.open(path).convert("RGB").resize((INPUT_SIZE, INPUT_SIZE), Image.BILINEAR)
        predicted = np.asarray(mlmodel.predict({"image": pil})["labels"]).reshape(INPUT_SIZE, INPUT_SIZE)
        agreement = float((predicted == reference).mean())
        present = sorted({LABELS[i] for i in np.unique(predicted)})
        print(f"{path.name}: pixel agreement {agreement:.4f}; classes {present}")
        worst = min(worst, agreement)
    if worst < min_agreement:
        raise SystemExit(f"Core ML output diverges from PyTorch: {worst:.4f} < {min_agreement}")
    print(f"Validation passed (worst agreement {worst:.4f}).")


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--output", type=Path, default=Path("Models/build/ClothingParserModel.mlpackage"))
    parser.add_argument("--no-quantize", action="store_true", help="Keep float16 weights (larger package).")
    parser.add_argument("--skip-convert", action="store_true", help="Only run validation on an existing package.")
    parser.add_argument("--validate-image", type=Path, action="append", default=[])
    parser.add_argument("--min-agreement", type=float, default=0.97)
    args = parser.parse_args(argv)

    torch.manual_seed(0)
    if not args.skip_convert:
        convert(args.output, quantize=not args.no_quantize)
    if args.validate_image:
        validate(args.output, args.validate_image, args.min_agreement)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
