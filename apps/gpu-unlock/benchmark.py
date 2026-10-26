#!/usr/bin/env python3
"""Benchmark CUDA tensor GEMM, or compare saved reports without loading PyTorch."""

import argparse
import json
import os
import platform
import statistics
import subprocess
import sys
from pathlib import Path


def positive_int(value):
    number = int(value)
    if number < 1:
        raise argparse.ArgumentTypeError("must be positive")
    return number


def driver_settings(uuid):
    """Optional NVML utility metadata, collected outside the timed region."""
    if uuid == "unavailable":
        return None
    try:
        result = subprocess.run(
            ["nvidia-smi", "-i", "GPU-" + uuid.removeprefix("GPU-"),
             "--query-gpu=driver_version,power.limit", "--format=csv,noheader,nounits"],
            check=True, capture_output=True, text=True, timeout=10,
        )
        driver, power = result.stdout.strip().split(",")
        return {"driver": driver.strip(), "power_limit_w": power.strip()}
    except (OSError, ValueError, subprocess.SubprocessError):
        return None


def compare(argv):
    parser = argparse.ArgumentParser(description="Compare gpu_unlock benchmark reports")
    parser.add_argument("before", type=Path)
    parser.add_argument("after", type=Path)
    args = parser.parse_args(argv)
    before = json.loads(args.before.read_text())
    after = json.loads(args.after.read_text())
    for key in ("gpu", "uuid", "visible_devices", "torch", "cuda", "kernel", "driver_settings",
                "size", "samples", "iterations_per_sample", "warmup_iterations",
                "reduced_precision_reduction"):
        if before.get(key) != after.get(key):
            parser.error(f"incomparable reports: {key} differs ({before.get(key)!r} vs {after.get(key)!r})")
    if before["results"].keys() != after["results"].keys():
        parser.error("incomparable reports: tested dtypes differ")
    print(f"{before['gpu']}, N={before['size']}; before -> after")
    for dtype, old in before["results"].items():
        new = after["results"][dtype]
        if "skipped" in old or "skipped" in new:
            print(f"{dtype:5} skipped")
            continue
        if not old["finite_output"] or not new["finite_output"]:
            parser.error(f"{dtype}: report contains nonfinite output")
        ratio = new["median_tflops"] / old["median_tflops"]
        print(f"{dtype:5} {old['median_tflops']:8.2f} -> {new['median_tflops']:8.2f} TFLOPS "
              f"({(ratio - 1) * 100:+.1f}%, {ratio:.2f}x)")
        print(f"      numerical spot-check relative error: "
              f"{old['spotcheck_relative_l2_error']:.3g} -> {new['spotcheck_relative_l2_error']:.3g}")


def main():
    if len(sys.argv) > 1 and sys.argv[1] == "compare":
        compare(sys.argv[2:])
        return
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--size", type=positive_int, default=8192)
    parser.add_argument("--samples", type=positive_int, default=5)
    parser.add_argument("--iterations", type=positive_int, default=50)
    parser.add_argument("--device", help="GPU UUID or index; restricts this process to that GPU")
    parser.add_argument("--save", type=Path, help="save the JSON report for gpu_unlock compare")
    args = parser.parse_args()
    if args.device is not None:
        os.environ["CUDA_VISIBLE_DEVICES"] = args.device

    # Import after argument parsing so --help works without a PyTorch install.
    import torch

    if not torch.cuda.is_available() or torch.version.hip is not None:
        parser.error("NVIDIA CUDA GPU unavailable; check the host driver and container CDI passthrough")

    torch.cuda.set_device(0)
    torch.manual_seed(1234)
    torch.backends.cuda.matmul.allow_fp16_reduced_precision_reduction = False
    torch.backends.cuda.matmul.allow_bf16_reduced_precision_reduction = False
    # Where supported, explicitly rule out full FP16 accumulation too.
    if hasattr(torch.backends.cuda.matmul, "allow_fp16_accumulation"):
        torch.backends.cuda.matmul.allow_fp16_accumulation = False

    properties = torch.cuda.get_device_properties(0)
    report = {
        "gpu": properties.name,
        "uuid": str(getattr(properties, "uuid", "unavailable")),
        "driver_settings": driver_settings(str(getattr(properties, "uuid", "unavailable"))),
        "torch": str(torch.__version__),
        "cuda": torch.version.cuda,
        "kernel": platform.release(),
        "visible_devices": os.environ.get("CUDA_VISIBLE_DEVICES", "all"),
        "cmdline": Path("/proc/cmdline").read_text().strip(),
        "boot_requested_targets": (
            Path("/sys/module/gpu_unlock/parameters/targets").read_text().strip()
            if Path("/sys/module/gpu_unlock/parameters/targets").exists() else None
        ),
        "size": args.size,
        "samples": args.samples,
        "iterations_per_sample": args.iterations,
        "warmup_iterations": 20,
        "reduced_precision_reduction": False,
        "results": {},
    }

    with torch.inference_mode():
        for label, dtype in (("fp16", torch.float16), ("bf16", torch.bfloat16), ("tf32", torch.float32)):
            torch.backends.cuda.matmul.allow_tf32 = label == "tf32"
            if label == "bf16" and not torch.cuda.is_bf16_supported():
                report["results"][label] = {"skipped": "BF16 unsupported"}
                continue
            a = torch.randn(args.size, args.size, dtype=dtype, device="cuda")
            a.div_(args.size**0.5)
            b = torch.randn_like(a)
            out = torch.empty_like(a)
            for _ in range(20):
                torch.mm(a, b, out=out)
            torch.cuda.synchronize()

            times = []
            start = torch.cuda.Event(enable_timing=True)
            end = torch.cuda.Event(enable_timing=True)
            for _ in range(args.samples):
                start.record()
                for _ in range(args.iterations):
                    torch.mm(a, b, out=out)
                end.record()
                end.synchronize()
                times.append(start.elapsed_time(end) / args.iterations)

            if not torch.isfinite(out).all().item():
                raise RuntimeError(f"{label}: GEMM produced NaN or infinity")
            # Check a block of the actual full-size output against a CPU FP64
            # reference using all K terms. This is a spot check, not an exhaustive
            # validation suite; timing excludes transfers and this reference.
            reference = a[:8, :].to(device="cpu", dtype=torch.float64) @ b[:, :8].to(
                device="cpu", dtype=torch.float64
            )
            observed = out[:8, :8].to(device="cpu", dtype=torch.float64)
            error = observed - reference
            median_ms = statistics.median(times)
            report["results"][label] = {
                "median_ms": median_ms,
                "median_tflops": 2 * args.size**3 / (median_ms / 1000) / 1e12,
                "sample_ms": times,
                "finite_output": True,
                "spotcheck_relative_l2_error": error.norm().item()
                / max(reference.norm().item(), 1e-30),
                "spotcheck_max_absolute_error": error.abs().max().item(),
            }
            del a, b, out

    for label, result in report["results"].items():
        if "skipped" in result:
            print(f"{label}: {result['skipped']}")
        else:
            print(f"{label}: {result['median_ms']:.3f} ms, {result['median_tflops']:.2f} TFLOPS; "
                  f"spot-check relative error {result['spotcheck_relative_l2_error']:.3g}")
    if args.save is not None:
        args.save.write_text(json.dumps(report, indent=2) + "\n")
        print(f"Saved {args.save}")


if __name__ == "__main__":
    main()
