# Installing the app on your Apple Watch

`build.sh` opened the Xcode project for you. The watch app is **embedded in the
iPhone app**, so you install it by running the iPhone app once — that pushes the
watch app to your paired Apple Watch. Follow these steps exactly.

## Before you start
- Your **Apple Watch is paired to your iPhone** (normal pairing).
- An **Apple ID** (a free one works — see the 7-day note at the bottom).
- A **USB cable** for the iPhone (first install over cable is most reliable).

## Step 1 — Plug in the iPhone
Connect the iPhone to the Mac. Unlock it. If it asks **"Trust This Computer?"**,
tap **Trust** and enter your passcode.

### Want it cable-free? (wireless deploy)
You only need the cable **once**. After Step 1, in Xcode open **Window → Devices
and Simulators**, select your iPhone, and tick **Connect via network**. Unplug —
now, whenever the Mac and iPhone are on the **same Wi-Fi** (both awake), the
iPhone shows up as a wireless run destination and ▶ deploys over the air.

If the Mac isn't near you at all, the only way to install remotely is
**TestFlight**, which needs a **paid Apple Developer account ($99/yr)**: upload a
build from the Mac (or a cloud Mac / CI) once, then install via the TestFlight
app on the iPhone from anywhere. Building still requires a Mac somewhere — Apple
does not allow building/signing iOS apps from the phone alone.

## Step 2 — Set the signing team (one time)
In Xcode's left sidebar, click the blue **ClaudeWatch** project at the top, then:

1. Select the **ClaudeWatch** target → **Signing & Capabilities** tab.
2. Tick **Automatically manage signing**.
3. **Team** → pick your Apple ID. (No team listed? Click *Add an Account…*, sign
   in with your Apple ID, then pick it.)
4. Repeat 1–3 for the **ClaudeWatchWatch** target.

If you see **"bundle identifier is not available"** or **"the app identifier
cannot be registered to your development team"**, the default id is the original
author's — use your own. Easiest:

```bash
BUNDLE_ID=com.YOURNAME.claudewatch ./build.sh    # reuses your relay, rewrites the id, regenerates
```

Or manually: `cd ios/ClaudeWatch && sed -i '' 's/com\.shobhit\.claudewatch/com.YOURNAME.claudewatch/g' project.yml "ClaudeWatch watchOS/Info.plist" && xcodegen generate`.
Then redo signing (Step 2). If `com.YOURNAME.claudewatch` is also taken, make it
more unique (e.g. `com.YOURNAME.cw`).

## Step 3 — Choose where to run
At the top of the Xcode window, next to the ▶ button:
- Left dropdown (scheme): choose **ClaudeWatch** (the iPhone app — **not** the
  watch-only scheme).
- Right dropdown (destination): choose **your iPhone** by name.

## Step 4 — Run it
Press **▶** (or **Cmd+R**). Xcode builds and installs the app on the iPhone, and
bundles the watch app with it. Wait for "Build Succeeded" and the app to launch
on the phone.

## Step 5 — Trust the developer (first time only)
If the iPhone says the app is from an untrusted developer:
**Settings → General → VPN & Device Management → (your Apple ID) → Trust**.
Then open the app on the iPhone once.

## Step 6 — Get it onto the watch
Usually it auto-installs within a minute. If not:
1. Open the **Watch** app on the iPhone.
2. Scroll to **Available Apps** → tap **Install** next to **Agent Watch**.
   (Or under *My Watch* find it and toggle **Show App on Apple Watch**.)
3. On the watch, the app appears in the app grid.

## Step 7 — Open and pair
Open **Agent Watch** on the watch and **type the 6-digit code**. The bridge
auto-starts when you start a Claude session via the `cw` alias and the session
announces the code (or start it manually: `node skill/bridge/server.js`).
With a relay configured, the code is all you need. No relay? Tap **Enter URL
manually** and enter the LAN IP / tunnel URL, then the code.

---

## Enable Developer Mode (required — fixes the infinite install spinner)

watchOS won't install a development build until Developer Mode is on. The toggle
often only appears after Xcode has tried an install **and** the device restarts.

1. **iPhone first:** Settings → Privacy & Security → (bottom) **Developer Mode →
   On** → restart the iPhone. (If it's missing on the iPhone too, do one Xcode ▶
   run to the iPhone and it appears.)
2. **Restart the watch** (side button → Power Off → on).
3. On the watch: Settings → Privacy & Security → scroll to the bottom →
   **Developer Mode → On** (it asks to restart again). Requires watchOS 9+.
4. Still missing? Run ▶ from Xcode again — a "Developer Mode required" prompt
   appears, after which the toggle shows up.
5. **Trick that works when it's truly absent:** the toggle only appears once Xcode
   actually *connects* to the watch. Force it: Xcode → Window → Devices and
   Simulators (or the macOS **Console** app) → **open the live console for the
   iPhone, then for the Apple Watch**. That handshake makes **Developer Mode**
   appear in the watch's Privacy & Security. (Needs iPhone on USB to the Mac, and
   Mac/iPhone/watch on the same Wi-Fi SSID + Bluetooth on.)

If the watch shows an **endless "Installing…" spinner**: cancel it (iPhone Watch
app → the app → turn its install toggle off), enable Developer Mode as above,
then redeploy **via the iPhone scheme** (not directly to the watch). Keep the
watch on its charger, unlocked, right next to the iPhone, on the same Wi-Fi, and
out of Low Power Mode. If it still hangs, restart both devices and retry once.

## Troubleshooting
- **"Signing for ClaudeWatch requires a development team"** — you skipped Step 2
  for one of the two targets. Set the Team on **both**.
- **App won't appear on the watch** — Watch app → General → make sure
  **Automatic App Install** is on, or install manually (Step 6). Keep the watch
  on its charger and nearby during the first install.
- **"unsupported architecture" / build errors** — Xcode menu **Product → Clean
  Build Folder** (Cmd+Shift+K), then Run again. Make sure the scheme is
  **ClaudeWatch**, not ClaudeWatchWatch.
- **"The app could not be installed at this time"** — usually a signing/leftover
  conflict. Fixes, in order: (1) **delete any existing copy** of the app from BOTH
  the iPhone and the watch (an old build with a different signature blocks the new
  one); (2) confirm Developer Mode is actually **On** (above); (3) **Product →
  Clean Build Folder** (Cmd+Shift+K) and Run again; (4) confirm bundle IDs match —
  iPhone `com.you.claudewatch`, watch `com.you.claudewatch.watchkitapp` (the sed
  one-liner keeps them in sync); (5) restart both devices and retry — it's often
  transient ("this time").
- **Free Apple ID** — apps signed with a free account **stop working after 7
  days**; just re-run Step 4 to reinstall. A paid Apple Developer account
  ($99/yr) removes this limit.
