# Qwen3.5 Support Matrix

This document describes the **standard MLX** Qwen3.5 compatibility policy implemented by `MLXFoundationModels`.

## Supported

`MLXFoundationModels` supports Qwen3.5 variants when all of the following are true:

- `model_type` is `qwen3_5` or `qwen3_5_moe`
- the repository uses standard MLX config and weight layout
- the quantization is standard MLX bf16 or group-wise quantized weights
- the runtime path can be derived deterministically from config metadata

Representative model IDs:

| Family | Runtime | Quantization | Representative ID |
| --- | --- | --- | --- |
| Dense small | LLM | 6bit | `mlx-community/Qwen3.5-2B-6bit` |
| Dense small | VLM / conditional generation | 4bit | `mlx-community/Qwen3.5-4B-MLX-4bit` |
| Dense small | LLM | bf16 | `mlx-community/Qwen3.5-2B-bf16` |
| Dense mid | LLM | 8bit | `mlx-community/Qwen3.5-9B-8bit` |
| Dense large | LLM | 4bit | `mlx-community/Qwen3.5-27B-4bit` |
| MoE medium | LLM | 4bit | `mlx-community/Qwen3.5-35B-A3B-4bit` |
| MoE large | LLM | 4bit | `mlx-community/Qwen3.5-122B-A10B-4bit` |

## Explicitly Unsupported

The loader fails fast for third-party or custom quantization formats that do not match the standard MLX contract.

Unsupported markers include:

- `mxfp`
- `nvfp`
- `optiq`
- `qx`
- `gptq`
- `awq`
- `gguf`

These variants are rejected before model instantiation so they do not fall through into long prefill stalls or ambiguous loader failures.

## Notes

- Qwen3.5 routing is deterministic. The loader chooses `MLXLLM` vs `MLXVLM` based on inspected config metadata instead of trampoline ordering.
- Qwen3.5 `GatedDelta` execution is shared between LLM and conditional-generation paths to avoid divergent performance behavior.
- Runtime smoke tests are environment-gated and intended for maintainers validating representative families on suitable hardware.
