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
