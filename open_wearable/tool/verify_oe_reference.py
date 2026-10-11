"""Independent strict decoder for a private v3 stereo microphone reference.

Usage: python3 tool/verify_oe_reference.py INPUT.oe OUTPUT.json
Then: OE_REFERENCE_JSON=OUTPUT.json flutter test test/models/oe
Uses only Python's standard library. No personal recording is checked in.
"""
import hashlib
import json
import struct
import sys
from pathlib import Path

source, destination = map(Path, sys.argv[1:])
b = source.read_bytes()
version, timestamp, header_size, parse_size, device, side = struct.unpack_from('<HQIIQB', b)
assert version == 3 and header_size == 27 + parse_size and header_size <= len(b)
# Require that the file actually declares the expected layout; Dart separately
# validates the complete schema. This tool intentionally accepts mic-only logs.
assert b'MICROPHONE\x05OUTER' in b[27:header_size]
assert b'MICROPHONE\x05INNER' in b[27:header_size]
outer, inner, times = bytearray(), bytearray(), bytearray()
offset = header_size
packets = 0
while offset < len(b):
    assert len(b) - offset >= 10, f'truncated header at {offset}'
    sid, size, time = struct.unpack_from('<BBQ', b, offset)
    assert sid == 2 and size > 0 and size % 4 == 0, f'unsupported packet at {offset}'
    assert offset + 10 + size <= len(b), f'truncated payload at {offset}'
    times.extend(b[offset + 2:offset + 10])
    for i in range(offset + 10, offset + 10 + size, 4):
        outer.extend(b[i:i+2]); inner.extend(b[i+2:i+4])
    offset += 10 + size
    packets += 1
h = lambda x: hashlib.sha256(x).hexdigest()
result = dict(source=str(source.resolve()), sha256=h(b), frames=len(inner)//2,
              packets=packets, pcm_sha256_outer_inner=[h(outer), h(inner)],
              timestamps_sha256=h(times), header_timestamp_us=timestamp)
destination.write_text(json.dumps(result, indent=2) + '\n')
print(json.dumps(result, indent=2))
