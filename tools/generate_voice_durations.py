"""Read FSB5 sample lengths without changing audio assets.

Run from the mod root: python tools/generate_voice_durations.py [--check]
FSB5 layout reference: https://github.com/HearthSim/python-fsb5/blob/master/fsb5/__init__.py
Only headers and the sample-name table are read; audio decoding is unnecessary.
"""
import argparse
import math
from pathlib import Path
import re
import struct

ROOT = Path(__file__).resolve().parents[1]
OUTPUT = ROOT / "scripts/my_friend_voice_durations.lua"
RATES = {1: 8000, 2: 11000, 3: 11025, 4: 16000, 5: 22050,
         6: 24000, 7: 32000, 8: 44100, 9: 48000}


def read_bank(path):
    with path.open("rb") as source:
        header = source.read(60)
        if len(header) != 60 or header[:4] != b"FSB5":
            raise ValueError(f"{path}: expected an FSB5 header")
        version, count, header_size, names_size = struct.unpack_from("<4I", header, 4)
        if version not in (0, 1):
            raise ValueError(f"{path}: unsupported FSB5 version {version}")
        if version == 0:
            source.read(4)
        data = source.read(header_size + names_size)
    if len(data) != header_size + names_size or names_size < count * 4:
        raise ValueError(f"{path}: truncated sample/name headers")
    event_bank = path.with_suffix(".fev").read_bytes()
    bank = int(path.stem[2:])
    cursor = 0
    for index in range(count):
        bits, = struct.unpack_from("<Q", data, cursor)
        cursor += 8
        more, rate, samples = bits & 1, RATES.get((bits >> 1) & 15), bits >> 34
        while more:
            chunk, = struct.unpack_from("<I", data, cursor)
            cursor += 4
            more, size, kind = chunk & 1, (chunk >> 1) & 0xFFFFFF, chunk >> 25
            if kind == 2:
                if size != 4:
                    raise ValueError(f"{path}: invalid frequency chunk")
                rate, = struct.unpack_from("<I", data, cursor)
            cursor += size
        if cursor > header_size or not rate or samples <= 0:
            raise ValueError(f"{path}: invalid sample header")
        offset, = struct.unpack_from("<I", data, header_size + index * 4)
        if offset < count * 4 or offset >= names_size:
            raise ValueError(f"{path}: invalid sample name offset")
        start = header_size + offset
        end = data.index(b"\0", start)
        name = data[start:end].decode("ascii")
        match = re.fullmatch(r"fn([1-9][0-9]*)", name)
        if match is None or name.encode() + b".wav\0" not in event_bank:
            raise ValueError(f"{path}: sample {name} has no matching FEV wave reference")
        number = int(match[1])
        if (number - 1) // 70 + 1 != bank:
            raise ValueError(f"{path}: {name} is assigned to another bank")
        # Round up to milliseconds so the estimate never shortens a recording.
        yield number, math.ceil(samples * 1000 / rate) / 1000
    if cursor != header_size:
        raise ValueError(f"{path}: sample header length mismatch")


def render():
    values = {}
    for path in sorted((ROOT / "sound").glob("fs*.fsb")):
        for number, duration in read_bank(path):
            if number in values:
                raise ValueError(f"duplicate fn{number}")
            values[number] = duration
    if not values or set(values) != set(range(1, max(values) + 1)):
        raise ValueError("voice catalogue is empty or contains missing fn numbers")
    lines = ["-- Generated from sound/fs*.fsb sample counts and frequencies.",
             "-- Regenerate after audio export: python tools/generate_voice_durations.py",
             "-- Values are seconds indexed by the permanent fn number; no audio is modified.",
             "return {"]
    for bank_start in range(1, max(values) + 1, 70):
        bank_end = min(bank_start + 69, max(values))
        lines.append(f"    -- fs{(bank_start - 1) // 70 + 1}: fn{bank_start}–fn{bank_end}")
        for first in range(bank_start, bank_end + 1, 7):
            entries = [f"[{number}] = {values[number]:.3f}"
                       for number in range(first, min(first + 7, bank_end + 1))]
            lines.append("    " + ", ".join(entries) + ",")
    lines.append("}\n")
    return "\n".join(lines), len(values)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true", help="verify metadata without writing")
    args = parser.parse_args()
    result, count = render()
    if args.check:
        if not OUTPUT.exists() or OUTPUT.read_text(encoding="utf-8") != result:
            raise SystemExit("Voice durations are outdated; run this script without --check.")
        print(f"Verified {count} voice durations against audio banks.")
    else:
        OUTPUT.write_text(result, encoding="utf-8", newline="\n")
        print(f"Wrote {count} voice durations to {OUTPUT.relative_to(ROOT)}.")


if __name__ == "__main__":
    main()
