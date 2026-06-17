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

If you see **"bundle identifier is not available"**, change the prefix to
something unique to you: open `ios/ClaudeWatch/project.yml`, replace every
`com.shobhit.claudewatch` with `com.YOURNAME.claudewatch`, then re-run
`./build.sh --no-relay` (regenerates the project) and redo signing.

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
Open **Agent Watch** on the watch and **type the 6-digit code** the bridge
printed (`/claude-watch-anywhere:claude-watch`, or `node skill/bridge/server.js`).
With a relay configured, the code is all you need. No relay? Tap **Enter URL
manually** and enter the LAN IP / tunnel URL, then the code.

---

## Troubleshooting
- **"Signing for ClaudeWatch requires a development team"** — you skipped Step 2
  for one of the two targets. Set the Team on **both**.
- **App won't appear on the watch** — Watch app → General → make sure
  **Automatic App Install** is on, or install manually (Step 6). Keep the watch
  on its charger and nearby during the first install.
- **"unsupported architecture" / build errors** — Xcode menu **Product → Clean
  Build Folder** (Cmd+Shift+K), then Run again. Make sure the scheme is
  **ClaudeWatch**, not ClaudeWatchWatch.
- **Free Apple ID** — apps signed with a free account **stop working after 7
  days**; just re-run Step 4 to reinstall. A paid Apple Developer account
  ($99/yr) removes this limit.
