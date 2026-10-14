# Settings and Logging Pages

## `SettingsPage` (`lib/widgets/settings/settings_page.dart`)
- Needs:
  - Callbacks from shell:
    - `onLogsRequested`
    - `onConnectRequested`
    - `onGeneralSettingsRequested`
- Does:
  - Shows top-level app settings entry points.
  - Routes to general settings, logs, and about flow.
- Provides:
  - Central settings navigation hub.

## `GeneralSettingsPage` (`lib/widgets/settings/general_settings_page.dart`)
- Needs:
  - Static settings backends initialized at app startup:
    - `AutoConnectPreferences`
    - `AppShutdownSettings`
- Does:
  - Binds switch controls to persisted app settings.
  - Serializes save operations via `_isSaving` guard.
- Provides:
  - Runtime policy controls (auto-connect, shutdown behavior, live graph behavior).

## `_AboutPage` (`lib/widgets/settings/settings_page.dart`)
- Needs:
  - Internet/external app availability for URL launches (`url_launcher`).
- Does:
  - Shows app/about/legal context and external links.
  - Exposes entry into open-source license listing page.
- Provides:
  - Product attribution and legal discoverability.

## `_OpenSourceLicensesPage` (`lib/widgets/settings/settings_page.dart`)
- Needs:
  - Flutter `LicenseRegistry` data.
- Does:
  - Loads and groups licenses by package.
  - Displays per-package license details.
- Provides:
  - In-app third-party license compliance view.

## `LogFilesScreen` (`lib/widgets/logging/log_files_screen.dart`)
- Needs:
  - `LogFileManager` provider.
  - File share plugin support (`share_plus`).
- Does:
  - Lists collected log files and metadata.
  - Supports share/delete per file and clear-all with confirmation.
  - Navigates to log file detail viewer.
- Provides:
  - Diagnostic log management for users/developers.

## `LogFileDetailScreen` (`lib/widgets/logging/log_file_detail_screen.dart`)
- Needs:
  - Constructor input: `File file`.
- Does:
  - Loads file contents once and renders scrollable/selectable text.
  - Handles empty/error states for file reading.
- Provides:
  - Raw log content inspection view.

### Timed sensor experiments

Each configurable device (or combined left/right pair) has **Experiment mode**.
Save a firmware-compatible profile, choose **Set up experiment**, select the
profile and its duration in whole seconds, and optionally **Add stage** to build
a sequence. Start applies the first profile immediately. Each countdown begins
after fresh hardware configuration reports confirm the requested settings on
both members of a combined pair. At expiry the next profile is applied; after
the last stage, the built-in **Off** profile is applied automatically. **Stop and
turn Off** cancels the sequence and requests Off immediately. Durations exclude
profile switching/acknowledgement time. An acknowledgement timeout (10 seconds)
or incompatible setting fails the experiment and attempts Off on both devices;
the status distinguishes confirmed Off from an unconfirmed shutdown.

The timer belongs to the connected device provider and continues when navigating
away from sensor configuration. Keep the app running and devices connected;
this is app-side scheduling, not a firmware deadline. Disconnection cancels
scheduling and attempts shutdown on the partner. A disconnected device cannot
be guaranteed to stop. Bluetooth command latency and OS suspension mean stage
boundaries are not sample-perfect or proof of synchronized left/right capture.
SD recording follows the saved profile’s targets; experiment mode does not
start a separate phone recording, power down the hardware, or alter OE headers.
The expandable timing history shows UTC application, confirmation, expiry and
failure events for the current app session.

Experiment setup remembers the last profile sequence and entered durations for
each device or combined pair, including drafts dismissed with Cancel. These
choices persist across navigation and app restarts. Adding a stage copies the
previous stage’s profile. If a remembered profile is deleted or no longer
compatible with the device’s firmware, its stage remains unselected and requires
an explicit replacement; it never silently runs a default profile instead.

Each experiment stage has a **Remove stage** button. Add stage stays beside the
Start/Cancel actions so it remains reachable when the stage list scrolls.
Removing a stage preserves the other stages’ profiles, durations and efforts.
An empty sequence cannot start.

For devices with SD recording support, **Name SD logs automatically** supplies
an effort selector (empty/vocal/silent), paragraph increment/decrement controls,
and a preview. Names contain the profile, effort, paragraph, automatic take
number and readable **local computer time**, e.g.
`IMU_vocal_p003_t002_13-10-26_14-35-09_<device-time>.oe`. The firmware still appends
its raw device timestamp; that suffix cannot be reformatted through the exposed
SDK. Readable time includes minutes, uses DD-MM-YY_HH-mm-ss, and avoids colons.
Profile names are sanitized to ASCII and shortened to 20 characters to respect
the device’s 63-character prefix limit. Both members of a pair receive the same
prefix and it is read back before recording is enabled.

Effort, paragraph and naming preferences persist. Take counters persist
separately per device group/profile/effort/paragraph. They advance only when a
stage attempts to record, not when setup opens or a stage is removed. Failed
attempts can leave gaps because a partially created recording must not reuse a
take number. Each stage first confirms Off, sets its new prefix, then enables
its recording profile; this also separates repeated stages into distinct files.

Experiment configuration writes are serialized per sensor and await individual
hardware reports, including partial reports. Async errors from the SDK’s void
configuration setter are captured instead of escaping as unhandled futures.
Shutdown attempts all settings even when one fails, and errors identify the
device and configuration. Cancellation prevents the rest of an in-flight stage
from enabling sensors after Stop. These checks do not diagnose firmware LED
states or guarantee shutdown after a physical disconnection.
Settings already confirmed by the device are not resent: firmware may omit a
notification for a no-op, which previously caused false shutdown timeouts.


### Recording diagnostics

The Log Files page now also lists `recording-diagnostics.log` and its rotated files from the `logs/recording` subdirectory. Each line is a JSON event with UTC time, app session and ordered sequence. Events record device IDs/names, actual reported setting keys, requested settings, per-setting confirmation/failure latency (10-second limit), experiment stage durations, stop attempts, prefix write/readback, device removal and Bluetooth availability. These logs exclude sensor samples and survive ordinary verbose-log rotation separately (4 MB per file, 20 rotated files). Recording events request immediate flushing through the logger output; this is not a crash-proof audit journal.

A configuration acknowledgement verifies reported sensor settings, not SD mounting, free space, completed file writes or final file integrity. The current SDK does not expose that evidence. Preserve the original SD files when investigating recording failures. Normal Apply logs now say Requested rather than claiming confirmed application.

Shutdown remains sequential per device. A missing acknowledgement can consume 10 seconds before the next sensor's Off command is issued. The new timing events make this delay diagnosable; changing command ordering/firmware semantics requires separate validation.


### Archive sensor profiles

In Profiles, open a saved profile's actions and choose Archive. Archived profiles remain stored with the same payload/key, but disappear from active profiles and new experiment selections. Show archived opens the archive list, where details remain available and Restore returns the profile to active use. Off cannot be archived. Archived names remain reserved to prevent a new save overwriting an archived profile. Archiving does not send device commands or alter recordings and does not interrupt an experiment already running.


### Paired experiment confirmation

Profile badges subscribe to both configuration providers, including when only the partner reports a change. Incremental configuration reports retain other sensors' last-known settings. Experiments verify all requested settings after each device's write sequence and recheck both targets after the slower target completes. A later rejection/reversion prevents the stage timer from starting and triggers the existing Off cleanup. Experiment profile mapping requires the same sampling rate and data targets on the partner; it rejects approximate substitutions. These are sensor configuration checks, not proof of successful SD writes.

### Speech corpus collection

Experiment setup includes the frozen version 1 corpus (P001–P120), with the
original training, development and test allocation. Select the passage, speaking
mode, environment (`silent`, `ambient`, `noisy`) and posture (`walking`,
`standing`, `sitting`), then preview before beginning. `empty` means a resting
baseline and is stored outside the passage labels. Silent speaking mode means
unvoiced mouthing; it is independent of the environment label.

The reader keeps the full passage available, preserves its scroll position and
keeps the display awake. Manual finish is enabled by default: sixty seconds is
only a guide. Finish after the last word, allow the one-second recorded tail,
and wait for Off confirmation before powering down. Text size can be adjusted
before reading; there is no automatic scrolling or audible cue. Timed stages
remain available by turning manual finish off.

Take numbers are reserved before starting, shared by simultaneous ears, and
increase across retries without overwriting earlier takes. The filename includes
the passage ID, take and abbreviated conditions: `sil`/`amb`/`noi` and
`wal`/`sta`/`sit`. Condition-labelled profile names use up to eight characters to
stay within the firmware's 63-character prefix limit. Full condition labels,
corpus version, profile and both device IDs are also recorded in the diagnostic
log. Configuration acknowledgements do not verify the resulting SD file.
