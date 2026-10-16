# Watch G7 direct (step 1)

The watch connects to the Dexcom G7 itself, in the sensor's **watch** display
slot (the phone keeps its own), so glucose and low/high alerts keep working
when the iPhone is out of reach. Display and alerts only: nothing here doses.

## Files

- `G7SensorKit/`: copied unchanged from LoopKit/G7SensorKit pull request #80
  (Jeremy Barnum's Sport Mode watch support), commit `1353226`. MIT licence,
  © LoopKit Authors. These are the Bluetooth, authentication and crypto layers,
  which need no LoopKit and already run on watchOS there, including the watch
  acquisition design (`G7WatchAcquisition`) and the faster P-256 maths that
  pairing on a watch needs.
- `WatchG7Session.swift`: the session half of G7SensorKit's `G7Sensor` (direct
  mode), rewritten without LoopKit.
- `WatchG7Messages.swift`: glucose and backfill parsing without LoopKit.
- `WatchG7Reader.swift`: settings, history, alerts, and what the phone sends.
- `WatchG7View.swift`: the third page of the watch app.
- `TrioWatchAppDelegate.swift`: launches the reader at every (also background)
  launch and holds Bluetooth wakes.

## Keeping it current

The copied files are not tied to the phone's G7SensorKit submodule, so changes
to g7-direct on the phone never break the watch build. When the upstream watch
support changes, copy the same files again from the newer commit and check
`WatchG7Session.swift` against `G7Sensor.swift` there.
