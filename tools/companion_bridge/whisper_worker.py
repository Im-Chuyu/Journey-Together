"""Optional offline ASR process. Microphone opens only in explicit recognition modes."""
import argparse
from collections import deque
import json
import os
from pathlib import Path
import sys
import threading
import time


def emit(**data):
    print(json.dumps(data, ensure_ascii=False), flush=True)


def main():
    sys.stdout.reconfigure(encoding="utf-8")
    parser = argparse.ArgumentParser()
    parser.add_argument("--mode", choices=("prepare", "check", "recognize", "hold", "continuous", "wave"), required=True)
    parser.add_argument("--model", required=True)
    parser.add_argument("--language", default="zh")
    parser.add_argument("--wave")
    args = parser.parse_args()
    if args.mode == "prepare":
        model_path = Path(args.model).resolve()
        os.environ["HF_HUB_DISABLE_XET"] = "1"
        from faster_whisper.utils import download_model
        download_model("small", output_dir=str(model_path), cache_dir=str(model_path / ".cache" / "hub"))
        emit(status="ready", model=str(model_path))
        return
    import numpy as np
    import sounddevice as sd
    model_path = Path(args.model)
    if not (model_path / "model.bin").is_file():
        raise ValueError("离线模型未准备好，请在语音设置中点击安装/准备离线识别。")
    if args.mode == "check":
        emit(status="ready", model=str(model_path))
        return
    model = None
    finished = threading.Event()
    paused = threading.Event()
    resume_at = [0.0]

    def controls():
        for line in sys.stdin:
            if line.strip() == "finish":
                finished.set()
            elif line.strip() == "pause":
                paused.set()
            elif line.strip() == "resume":
                resume_at[0] = time.monotonic() + 1
                paused.clear()

    if args.mode in ("continuous", "hold"):
        threading.Thread(target=controls, daemon=True).start()

    def transcribe(audio):
        nonlocal model
        if model is None:
            from faster_whisper import WhisperModel
            model = WhisperModel(str(model_path), device="cpu", compute_type="int8", cpu_threads=4, local_files_only=True)
        segments, _ = model.transcribe(audio, language=args.language, beam_size=5,
            vad_filter=True, condition_on_previous_text=False)
        segments = list(segments)
        text = "".join(s.text for s in segments if s.no_speech_prob < .6).strip()
        emit(status="recognized" if text else "no_speech", text=text, backend="whisper")

    if args.mode == "wave":
        if not args.wave:
            raise ValueError("wave mode requires --wave")
        transcribe(args.wave)
        return
    while True:
        frames, lead = [], deque(maxlen=3)
        silence, voiced, recorded = 0.0, 0.0, 0.0
        deadline = time.monotonic() + 20
        with sd.InputStream(samplerate=16000, channels=1, dtype="float32", blocksize=3200) as stream:
            while time.monotonic() < deadline and not (args.mode=="hold" and finished.is_set()):
                audio, overflow = stream.read(3200)
                audio = audio[:, 0].copy()
                if paused.is_set() or time.monotonic() < resume_at[0]:
                    frames.clear(); lead.clear(); silence = voiced = recorded = 0.0
                    continue
                rms = float(np.sqrt(np.mean(audio * audio)))
                if not frames:
                    lead.append(audio)
                    if rms < .008:
                        continue
                    frames.extend(lead); lead.clear()
                else:
                    frames.append(audio)
                recorded += .2
                if rms >= .008:
                    voiced += .2; silence = 0
                else:
                    silence += .2
                if (recorded >= 12 or silence >= .9) and args.mode != "hold":
                    break
        if frames and voiced >= .3:
            transcribe(np.concatenate(frames))
        elif args.mode != "continuous":
            emit(status="no_speech", text="", backend="whisper")
        if args.mode != "continuous":
            return


if __name__ == "__main__":
    try:
        main()
    except Exception as error:
        emit(status="error", error=str(error))
        sys.exit(1)
