#!/usr/bin/env python3
"""Rebuild Ishara's Arabic speech-to-text model from EgypTalk-ASR-v2.

Exports the CTC branch of NAMAA-Space/EgypTalk-ASR-v2 (CC BY 4.0) to ONNX,
adds the metadata sherpa-onnx reads, writes tokens.txt and quantizes the
weights to int8. CPU only. Following sherpa-onnx
scripts/nemo/fast-conformer-hybrid-transducer-ctc/export-onnx-ctc-non-streaming.py.

Tested (Linux x86_64, Python 3.12) with exactly:
    torch==2.15.0+cpu  (https://download.pytorch.org/whl/cpu)
    nemo_toolkit[asr]==3.0.0  onnx==1.23.2  onnxruntime==1.32.0

    python egyptalk_export.py OUT_DIR

Writes OUT_DIR/egyptalk-asr-v2-ctc.int8.onnx and OUT_DIR/egyptalk-asr-v2-tokens.txt
(and the fp32 egyptalk-asr-v2-ctc.onnx it quantizes). With those versions
the output matched these SHA-256 byte for byte; other versions may differ:
"""

import hashlib
import sys
from pathlib import Path

import onnx
import torch
from huggingface_hub import hf_hub_download
from nemo.collections.asr.models import ASRModel
from onnxruntime.quantization import QuantType, quantize_dynamic

REPO = "NAMAA-Space/EgypTalk-ASR-v2"
REVISION = "d23895cf2512efc62b5a34eafa8672b26c530953"
NEMO_FILE = "asr-egyptian-nemo-v2.0.nemo"
NEMO_SHA256 = "6fbaa3740d17a11956f009ce0d39a8aa713a6889f13226c18106d3e02c333481"
EXPECTED = {
    "egyptalk-asr-v2-ctc.int8.onnx": "e311a80d77a2c05db0090df0edeae75ce426de2fb5521a0a54a14a15016b585e",
    "egyptalk-asr-v2-tokens.txt": "9b938381a19a69bb279cdcfc299419f25a049ea1de192e0d10317274a0f20074",
}


def sha256(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for block in iter(lambda: f.read(1 << 20), b""):
            h.update(block)
    return h.hexdigest()


def main():
    if len(sys.argv) != 2:
        sys.exit("usage: egyptalk_export.py OUT_DIR")
    out = Path(sys.argv[1])
    out.mkdir(parents=True, exist_ok=True)

    nemo = hf_hub_download(REPO, NEMO_FILE, revision=REVISION)
    if sha256(nemo) != NEMO_SHA256:
        sys.exit(f"{NEMO_FILE}: SHA-256 differs from the pinned one")

    torch.set_grad_enabled(False)
    m = ASRModel.restore_from(nemo, map_location="cpu")
    m.eval()
    m.change_decoding_strategy(decoder_type="ctc")
    m.set_export_config({"decoder_type": "ctc"})

    fp32 = out / "egyptalk-asr-v2-ctc.onnx"
    m.export(str(fp32))

    normalize = m.cfg.preprocessor.normalize
    meta = {
        # CTC: sherpa-onnx takes the output size (tokens + blank)
        "vocab_size": m.tokenizer.vocab_size + 1,
        "normalize_type": "" if normalize == "NA" else normalize,
        "subsampling_factor": 8,
        "model_type": "EncDecHybridRNNTCTCBPEModel",
        "version": "1",
        "model_author": "NAMAA-Space (NeMo)",
        "url": "https://huggingface.co/NAMAA-Space/EgypTalk-ASR-v2",
        "license": "CC-BY-4.0",
        "comment": "Only the CTC branch is exported",
    }
    model = onnx.load(str(fp32))
    while len(model.metadata_props):
        model.metadata_props.pop()
    for k, v in meta.items():
        p = model.metadata_props.add()
        p.key, p.value = k, str(v)
    onnx.save(model, str(fp32))

    vocabulary = m.ctc_decoder.vocabulary
    with open(out / "egyptalk-asr-v2-tokens.txt", "w", encoding="utf-8") as f:
        for i, t in enumerate(vocabulary):
            f.write(f"{t} {i}\n")
        f.write(f"<blk> {len(vocabulary)}\n")

    quantize_dynamic(
        model_input=str(fp32),
        model_output=str(out / "egyptalk-asr-v2-ctc.int8.onnx"),
        weight_type=QuantType.QUInt8,
    )

    for name, want in EXPECTED.items():
        got = sha256(out / name)
        print(f"{got}  {name}  {'matches' if got == want else 'DIFFERS from the release'}")


if __name__ == "__main__":
    main()
