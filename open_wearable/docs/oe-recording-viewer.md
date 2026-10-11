# Original OE recording importer and viewer

Open **Sensors → Recorder → Recorded OE logs → Import .oe file** on iOS or macOS.
The desktop app and phone app share the same parser and UI. No wearable connection
is required. Files are selected through the native file picker. On macOS the
sandbox grants access only to user-selected files.

## Data contract

- Only self-describing OE v3 files are accepted. Older versions are rejected
  because their layouts cannot be established from the file alone.
- The original is copied unchanged into application support storage. SHA-256 and
  byte length are checked after writing and on every reopen. The source is never
  overwritten. Browser imports are explicitly temporary.
- Metadata and packets are bounds-checked. Unknown IDs/types, inconsistent
  lengths, malformed UTF-8, unexpected metadata and partial records block import.
  There is no byte skipping, resynchronization, or partial-success display.
- Header labels, units and numeric types are retained. Packet timestamps remain
  integer microseconds in original file order. Clock origin and synchronization
  are not assumed. Repeated/backward timestamps are retained and counted.
- A file can end on a valid packet boundary without proving the recording was
  complete. The OE format does not provide an end-to-end payload checksum.
  Copy verification does not prove sensor accuracy or pre-import integrity.
- Known microphone SID 2 requires the declared OUTER, INNER layout. Firmware
  stores signed 16-bit PCM even when its ParseInfo declares uint16. The viewer
  labels that interpretation and exposes the declared numeric value alongside it.
  No other sensor's signedness or calibration is changed.
- Buffered non-audio samples retain their trailing delta field and containing
  packet timestamp. The viewer does not claim a reconstructed sample timestamp.
- Waveforms use frame index, not an inferred time axis. Each display bin includes
  every finite value and shows exact min/max; values are never averaged. Zooming
  reaches individual samples. Non-finite values remain in the inspector and are
  counted when excluded from plotting. Auto-scaled axes are labeled numerically.
- Header frequency options describe defaults and available rates, not necessarily
  the rate used during recording. No active audio rate is automatically selected.
- Playback/WAV require an explicit user-selected rate. Export copies the channel's
  original PCM bytes, without gain changes, filtering or resampling. It concatenates
  packet samples without filling gaps. Therefore its duration is a *derived playback
  duration*, not measured recording duration. Export includes JSON provenance with
  source hash, channel, header default, user assumption and timing limitations.

## Format evidence

Verified against OpenEarable firmware commit
`0ac3767d4aa20e98a0701dd9cb59996e62761e43`:

- [ParseInfo layout](https://github.com/OpenEarable/open-earable-2/blob/0ac3767d4aa20e98a0701dd9cb59996e62761e43/src/ParseInfo/README)
- `src/ParseInfo/DefaultSensors.h`: OUTER then INNER, declared UINT16.
- `src/audio/audio_datapath.c`: signed int16 stereo payload and timestamp.
- `src/SD_Card/SDLogger/SDLogger.cpp`: v3 fixed header and embedded ParseInfo.

Cross-checked with official `open-wearables` Python parser 0.2.1. Unlike that
parser's recovery mode, this importer rejects corrupt records rather than
attempting to resynchronize. Source checksums are identifiers, not signatures.

## Verification

```sh
flutter test test/models/oe test/widgets/oe
python3 tool/verify_oe_reference.py /path/to/private-microphone-log.oe /tmp/oe-reference.json
OE_REFERENCE_JSON=/tmp/oe-reference.json flutter test test/models/oe
```

The optional reference test compares *every channel byte* and *every packet
integer timestamp* against an independent Python standard-library decoder.
Private recordings and their extracted samples must not be checked in.

The importer currently limits files to 128 MiB to bound memory use on phones.
It retains the original bytes and packet indices instead of expanding all
samples into boxed objects. Parsing, plot aggregation and WAV generation run
outside the UI isolate on native platforms.
