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

## Mac accelerometer sonification

On macOS only, a recorded component whose header group is `ACCELEROMETER`
gets a synthetic-audio panel. The entire selected axis is processed in file
order, one value per audio frame. The user must explicitly choose an output
rate and peak level. Conversion is `round(value / max(abs(values)) * level *
32767)` to mono signed 16-bit PCM; all-zero input produces silence. Non-finite
values cause rejection, never omission. No DC removal, filtering, resampling,
or gap padding occurs. This is not calibrated audio, and physical amplitudes
cannot be compared between peak-scaled recordings. Original values and plots
remain unchanged. Output rate is not asserted to be the acquisition rate.
The conversion's source peak, exact formula, sample count and duration are
shown before playback. This feature plays existing recorded acceleration;
it does not enable additional sensors or alter device recording settings.

## Mac live readouts

Live sensor graphs also show the latest received axis values and units before
any graph filters, the provider-session sample count, original sensor timestamp
and host-observed arrival age. These are UI snapshots, not a display of every
sample. Once the rolling window is empty, the UI reports no samples in that
window. The separate system-audio graph reports its existing normalized 0–1
level, not raw PCM or calibrated sound pressure.

## Explicit partial interpretation

Strict import still rejects malformed packets. After rejection, an explicit
`Inspect parsed prefix · unparsed tail` action can inspect complete packets
accepted before the first error. It never scans forward to guess another
boundary. Header errors remain fatal. The full original bytes and their hash
are retained; the viewer prominently reports the stopping offset and number
of uninterpreted bytes. Plots, counts and derived audio cover only that prefix.
The original export includes the tail unchanged. WAV provenance records the
parse error and prefix boundary. This temporary view is not added to the
complete-recording library. A parse failure alone does not establish whether
the source file is corrupt or the format is unsupported.

An exact duplicated suffix is recognized automatically only at a packet parse
failure: every remaining byte must equal the immediately preceding block of
identical length (at least 10 bytes). This does not repair the source or assert
a firmware cause. The original full file is saved and hashed; a visible notice
and exported provenance disclose the duplicate boundary. The repeated bytes
are not counted again. Other malformed tails still require explicit partial
inspection and are never silently discarded.

## Recorded microphone transport and chart

The microphone transport appears above the waveform and requires an explicit
rate. It supports play from the beginning, pause/resume, stop, seek, and output
volume. Volume affects playback only; WAV export retains original PCM bytes.
The chart uses sample index until a rate is selected, then labels seconds as
assumed playback time (concatenated samples, not reconstructed packet time).
The playhead follows the audio player's reported position. Hover displays the
exact selected sample, units and containing packet timestamp. Overview bins
still retain every finite sample's min/max. At individual-sample zoom, adjacent
finite points are joined as visual guides; the line is not measured data
between samples. Fit-all, 300-sample inspection and a five-second window at
the playback position provide quick navigation.

## Metadata and human labels

Recording details expose header identity, ear side, per-sensor packet/frame
counts (including declared sensors with no samples), byte size, parse status
and the range of original packet timestamps. Calendar dates are explicitly
Unix-microsecond interpretations, not proof of clock synchronization. Device
uptime-like values outside 2000–2100 are not shown as recording dates. Both UTC
and this Mac's local timezone are identified; no acquisition timezone is inferred.

OE v3 headers here contain no place/GPS, active-rate setting or firmware version.
A session name, place and notes can be entered by the user and are stored in
separate hash-keyed annotation JSON files. They are labeled as user-entered and
never written into, or used to reinterpret, the original OE bytes. The library
shows a cached header date/side and these labels. Existing verified originals
are indexed on first use to populate their metadata.
