#!/usr/bin/env python3
"""Parse a GBCTV IR Lab .sav dump (e.g. SAVER/GBCTV.SAV from an EZ-Flash Jr).

The save is up to 16 banks of 8KB, one per profile. Each written bank starts
with a 16-byte header:

  +0  "IR"                magic
  +2  flags              bit0 = raw samples valid, bit1 = learned widths
                         valid; $03 means both derive from the SAME press
  +3  version            1
  +4  raw sample period, M-cycles   +5  raw capture CPU speed (2=double)
  +6  learned width unit, M-cycles  +7  learned unit CPU speed (1=normal)
  +8  learned source: 1 = live learner, 2 = derived from raw

Learned payload ($A010): marks1[127] spaces1[127] marks2[127]
spaces2[127], parallel width-count arrays, mark array zero-terminated.
Raw payload ($A210-$BFFF): one byte per ~4.3us sample, bit 0 = light.

--check re-derives the widths from the raw samples (same algorithm as
the on-device converter) and diffs them against the stored arrays.
"""
import argparse
import sys

BANK = 0x2000
RLE_OFF = 0x10
RAW_OFF = 0x210
ARR = 0x7F
GAP_FILTER_SAMPLES = 16
SAMP_PER_UNIT = 23
MCYCLE_NORMAL_US = 4 / 4.194304   # 0.9537 us
MCYCLE_DOUBLE_US = MCYCLE_NORMAL_US / 2


def sample_period_us(mcycles, speed):
    return mcycles * (MCYCLE_DOUBLE_US if speed == 2 else MCYCLE_NORMAL_US)


def raw_to_pulses(payload, period_us):
    """Collapse raw samples (bit0 = light) into (level, duration_us) runs."""
    runs = []
    prev, count = None, 0
    for b in payload:
        bit = b & 1
        if bit == prev:
            count += 1
        else:
            if prev is not None:
                runs.append((prev, count * period_us))
            prev, count = bit, 1
    if prev is not None:
        runs.append((prev, count * period_us))
    return runs


def dump_pulses(pulses, limit=None):
    shown = pulses[:limit] if limit else pulses
    for i, (level, us) in enumerate(shown):
        print(f"  {i:4d}  {'MARK ' if level else 'space'}  {us:9.1f} us")
    if limit and len(pulses) > limit:
        print(f"  ... {len(pulses) - limit} more (use --all)")


def parse_rle_frame(marks, spaces, unit_us):
    pulses = []
    for m, s in zip(marks, spaces):
        if m == 0:
            break
        pulses.append((1, m * unit_us))
        pulses.append((0, s * unit_us))
    return pulses


def derive_widths(raw):
    """Mirror of the on-device IRConvertRaw: chop-filter + quantize.

    Returns (marks, spaces) width lists, or ([], []) if no light found.
    """
    bits = [b & 1 for b in raw]
    i = 0
    while i < len(bits) and not bits[i]:
        i += 1
    if i == len(bits):
        return [], []
    marks, spaces = [], []

    def div(samples):
        return max(1, min(255, (samples + (SAMP_PER_UNIT - 1) // 2) // SAMP_PER_UNIT))

    while len(marks) < 0x7D:
        mark, dark = 0, 0
        while i < len(bits):
            if bits[i]:
                mark += dark + 1
                dark = 0
            else:
                dark += 1
                if dark >= GAP_FILTER_SAMPLES:
                    break
            i += 1
        if i == len(bits):                      # EOF mid-mark
            marks.append(div(mark))
            spaces.append(0x64)
            break
        i += 1                                  # consume the 16th dark sample
        marks.append(div(mark))
        space = GAP_FILTER_SAMPLES
        while i < len(bits) and space < 0x900 and not bits[i]:
            space += 1
            i += 1
        spaces.append(div(space))
        if i == len(bits) or space >= 0x900:    # frame gap or EOF
            break
    return marks, spaces


def read_rle_frame(chunk, frame):
    base = RLE_OFF + frame * 2 * ARR
    marks, spaces = [], []
    for m, s in zip(chunk[base:base + ARR], chunk[base + ARR:base + 2 * ARR]):
        if m == 0:
            break
        marks.append(m)
        spaces.append(s)
    return marks, spaces


def main():
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("sav")
    ap.add_argument("--bank", type=int, help="only this profile/bank")
    ap.add_argument("--all", action="store_true", help="print every pulse")
    ap.add_argument("--csv", metavar="FILE", help="write pulses as CSV")
    ap.add_argument("--check", action="store_true",
                    help="re-derive widths from raw and diff vs stored arrays")
    args = ap.parse_args()

    data = open(args.sav, "rb").read()
    nbanks = len(data) // BANK
    if nbanks == 0:
        sys.exit(f"{args.sav}: too small ({len(data)} bytes)")

    csv_rows = []
    for bank in range(nbanks):
        if args.bank is not None and bank != args.bank:
            continue
        chunk = data[bank * BANK:(bank + 1) * BANK]
        if chunk[0:2] != b"IR":
            continue
        flags, ver = chunk[2], chunk[3]
        has_raw, has_rle = bool(flags & 1), bool(flags & 2)
        src = {1: "live-learned", 2: "derived-from-raw"}.get(chunk[8], "?")
        desc = "+".join(n for n, f in (("raw", has_raw), ("rle", has_rle)) if f)
        print(f"bank {bank}: {desc or f'flags={flags:#x}'} v{ver}"
              + (f" ({src})" if has_rle else ""))
        pulses = []

        if has_rle:
            unit_us = sample_period_us(chunk[6], chunk[7])
            for frame in (0, 1):
                marks, spaces = read_rle_frame(chunk, frame)
                fp = parse_rle_frame(marks, spaces, unit_us)
                if not fp:
                    print(f"  frame {frame + 1}: empty")
                    continue
                print(f"  frame {frame + 1}: {len(fp) // 2} pulses "
                      f"(unit {unit_us:.2f}us)")
                dump_pulses(fp, None if args.all else 40)
                pulses = pulses or fp

        if has_raw:
            period_us = sample_period_us(chunk[4], chunk[5])
            rp = raw_to_pulses(chunk[RAW_OFF:], period_us)
            while rp and rp[0][0] == 0:         # leading dark before trigger
                rp.pop(0)
            print(f"  raw: {len(rp)} edges after first mark "
                  f"({period_us:.2f}us/sample)")
            dump_pulses(rp, None if args.all else 40)
            pulses = pulses or rp

        if args.check:
            if has_raw and has_rle:
                dm, ds = derive_widths(chunk[RAW_OFF:])
                sm, ss = read_rle_frame(chunk, 0)
                if dm == sm and ds == ss:
                    print(f"  check: OK ({len(sm)} widths match)")
                else:
                    print(f"  check: MISMATCH")
                    print(f"    stored  marks={sm} spaces={ss}")
                    print(f"    derived marks={dm} spaces={ds}")
            else:
                print("  check: skipped (needs raw+rle from the same press)")

        if args.csv:
            t = 0.0
            for level, us in pulses:
                csv_rows.append(f"{bank},{t:.1f},{level},{us:.1f}")
                t += us

    if args.csv:
        with open(args.csv, "w") as f:
            f.write("bank,t_us,level,duration_us\n")
            f.write("\n".join(csv_rows) + "\n")
        print(f"wrote {len(csv_rows)} rows to {args.csv}")


if __name__ == "__main__":
    main()
