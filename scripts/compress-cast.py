#!/usr/bin/env python3
"""Compress an asciinema .cast file for demo GIFs.

Reads step markers from the actual terminal output (e.g. "Step 1/7:")
and compresses long stretches between them. The final credential banner
is held for extra time so viewers can read it.

This is generic — it detects markers from the output, not hardcoded timestamps.

Usage: compress-cast.py input.cast output.cast [--hold-end SECONDS]
"""
import json
import re
import sys


def strip_ansi(text):
    """Remove ANSI escape codes from text."""
    return re.sub(r'\x1b\[[0-9;]*m', '', text)


def main():
    if len(sys.argv) < 3:
        print(f"Usage: {sys.argv[0]} input.cast output.cast [--hold-end SECONDS]")
        sys.exit(1)

    input_path = sys.argv[1]
    output_path = sys.argv[2]
    hold_end = 8.0

    if '--hold-end' in sys.argv:
        idx = sys.argv.index('--hold-end')
        hold_end = float(sys.argv[idx + 1])

    # Parse the cast file
    with open(input_path) as f:
        lines = f.readlines()

    header = json.loads(lines[0])
    events = []
    for line in lines[1:]:
        line = line.strip()
        if line:
            events.append(json.loads(line))

    if not events:
        print("No events found in cast file")
        sys.exit(1)

    # Find marker frames: "Step N/M:" patterns and the final banner
    # A marker is any frame whose text (stripped of ANSI) contains these patterns
    STEP_RE = re.compile(r'Step \d+/\d+:')
    BANNER_RE = re.compile(r'SelfPrivacy Tor VM is ready')

    markers = []  # list of (event_index, marker_type)
    for i, ev in enumerate(events):
        if len(ev) >= 3:
            text = strip_ansi(ev[2]) if isinstance(ev[2], str) else ''
            if STEP_RE.search(text):
                markers.append((i, 'step'))
            elif BANNER_RE.search(text):
                markers.append((i, 'banner'))

    # Build segments: [start_idx, end_idx) between markers
    # We also add implicit segments for before first marker and after last
    segments = []
    prev = 0
    for marker_idx, marker_type in markers:
        if marker_idx > prev:
            segments.append({
                'start': prev,
                'end': marker_idx,
                'type': 'gap',
            })
        segments.append({
            'start': marker_idx,
            'end': marker_idx + 1,
            'type': marker_type,
        })
        prev = marker_idx + 1

    # Add final segment (after last marker to end)
    if prev < len(events):
        segments.append({
            'start': prev,
            'end': len(events),
            'type': 'tail',
        })

    # Now rebuild the timeline with compressed gaps
    # Strategy:
    # - Marker frames: keep as-is (just adjust timestamp)
    # - Gap segments where real duration > 10s: keep first 2s and last 2s of
    #   frames, compress the middle to 0.5s total
    # - Gap segments <= 10s: play at 3x speed
    # - Tail (after banner): play at real speed, then add hold_end pause

    MAX_GAP_SPEED = 3.0      # speed up short gaps by this factor
    LONG_GAP_THRESHOLD = 10.0 # seconds before we hard-compress
    KEEP_HEAD_SECS = 2.0      # keep this many seconds at start of long gap
    KEEP_TAIL_SECS = 2.0      # keep this many seconds at end of long gap
    COMPRESSED_MIDDLE = 0.5   # compressed middle duration

    new_events = []
    current_time = 0.0

    for seg in segments:
        seg_events = events[seg['start']:seg['end']]
        if not seg_events:
            continue

        seg_start_ts = seg_events[0][0]
        seg_end_ts = seg_events[-1][0]
        seg_duration = seg_end_ts - seg_start_ts

        if seg['type'] in ('step', 'banner'):
            # Marker frame: emit at current_time, advance by small amount
            ev = seg_events[0]
            new_events.append([current_time, ev[1], ev[2]])
            current_time += 0.1
        elif seg['type'] == 'tail':
            # After the banner: play at real speed, then hold
            for ev in seg_events:
                offset = ev[0] - seg_start_ts
                new_events.append([current_time + offset, ev[1], ev[2]])
            current_time += seg_duration + hold_end
        elif seg_duration > LONG_GAP_THRESHOLD:
            # Long gap: keep head frames, compress middle, keep tail frames
            head_evs = []
            tail_evs = []
            for ev in seg_events:
                offset = ev[0] - seg_start_ts
                if offset <= KEEP_HEAD_SECS:
                    head_evs.append(ev)
                elif (seg_end_ts - ev[0]) <= KEEP_TAIL_SECS:
                    tail_evs.append(ev)

            # Emit head at real speed
            for ev in head_evs:
                offset = ev[0] - seg_start_ts
                new_events.append([current_time + offset, ev[1], ev[2]])

            head_duration = min(KEEP_HEAD_SECS, seg_duration)
            current_time += head_duration

            # Emit a "..." indicator in the compressed middle
            new_events.append([current_time, 'o',
                '\r\n\x1b[90m  ··· (fast-forwarding) ···\x1b[0m\r\n'])
            current_time += COMPRESSED_MIDDLE

            # Emit tail at real speed
            if tail_evs:
                tail_start_ts = tail_evs[0][0]
                for ev in tail_evs:
                    offset = ev[0] - tail_start_ts
                    new_events.append([current_time + offset, ev[1], ev[2]])
                tail_duration = tail_evs[-1][0] - tail_start_ts
                current_time += tail_duration + 0.1
        else:
            # Short gap: play at accelerated speed
            for ev in seg_events:
                offset = (ev[0] - seg_start_ts) / MAX_GAP_SPEED
                new_events.append([current_time + offset, ev[1], ev[2]])
            current_time += seg_duration / MAX_GAP_SPEED + 0.1

    # Update header duration
    if new_events:
        header['duration'] = new_events[-1][0] + 0.1

    # Write output
    with open(output_path, 'w') as f:
        f.write(json.dumps(header) + '\n')
        for ev in new_events:
            f.write(json.dumps(ev) + '\n')

    orig_dur = events[-1][0] if events else 0
    new_dur = header.get('duration', 0)
    print(f"  Compressed: {orig_dur:.0f}s -> {new_dur:.0f}s "
          f"({len(events)} -> {len(new_events)} frames)")


if __name__ == '__main__':
    main()
