import AppKit
import CoreMotion
import MediaPlayer

// Head-tracking port of WatchPointer's Mac receiver (github.com/umarz317/WatchPointer).
// AirPods Pro report head attitude straight to the Mac, so there is no watch app and no Bluetooth protocol.
// Stem press: 1× click, 2× re-center, 3× pause/resume.

setvbuf(stdout, nil, _IONBF, 0) // show log lines immediately

// Settings: `swift run HeadPointer [speed] [steady=…] [quick=…]`
private let arguments = CommandLine.arguments.dropFirst()
private func setting(_ name: String) -> Double? {
    arguments.first { $0.hasPrefix(name + "=") }.flatMap { Double($0.dropFirst(name.count + 1)) }
}
/// Higher = less head turn needed to reach the edges.
let speed = arguments.lazy.compactMap(Double.init).first ?? 1.0
/// Head turn from the middle to reach the left/right edge. Necks turn less than wrists, so smaller than the watch's 25.
let reachDegrees = 20.0 / speed
let steadyCutoff = setting("steady") ?? 0.8
let quickness = setting("quick") ?? 0.01

/// 1€ filter (Casiez et al. 2012), same as WatchPointer.
struct OneEuroFilter {
    var minCutoff = steadyCutoff
    var beta = quickness
    var derivativeCutoff = 1.0
    private var value: Double?
    private var velocity = 0.0

    mutating func callAsFunction(_ x: Double, dt: Double) -> Double {
        guard let previous = value, dt > 0 else { value = x; return x }
        func alpha(_ cutoff: Double) -> Double { 1 / (1 + 1 / (2 * .pi * cutoff * dt)) }
        velocity += alpha(derivativeCutoff) * ((x - previous) / dt - velocity)
        let smoothed = previous + alpha(minCutoff + beta * abs(velocity)) * (x - previous)
        value = smoothed
        return smoothed
    }

    mutating func reset() { value = nil; velocity = 0 }
}

final class HeadPointer {
    private let motion = CMHeadphoneMotionManager()
    private let queue = DispatchQueue(label: "HeadPointer.pointer", qos: .userInteractive)
    private var frameTimer: DispatchSourceTimer?

    // Only touched on `queue`.
    private var reference: CMAttitude?
    private var recenter = true
    private var paused = false
    private var left = 0.0 // degrees turned left since re-center
    private var filterX = OneEuroFilter(), filterY = OneEuroFilter()
    private var target: CGPoint?
    private var shown = CGPoint.zero
    private var lastTimestamp: TimeInterval? // AirPods' own sample time
    private var lastSample = 0.0             // arrival time, only to notice the AirPods going quiet
    private var lastLog = 0.0

    init() {
        guard motion.isDeviceMotionAvailable else {
            print("Head tracking unavailable. Needs AirPods Pro / Max / 3rd gen or later connected to this Mac.")
            exit(1)
        }
        let ops = OperationQueue()
        ops.underlyingQueue = queue
        motion.startDeviceMotionUpdates(to: ops) { [weak self] m, error in
            if let error { print("\nmotion error: \(error.localizedDescription)") }
            if let m { self?.sample(m) }
        }
        queue.async { self.startFrameLoop() }
        listenToStem()
        print("Put in your AirPods, look at the middle of the screen. Stem: 1× click, 2× re-center, 3× pause.")
    }

    // MARK: Aim → cursor

    private func sample(_ m: CMDeviceMotion) {
        let now = ProcessInfo.processInfo.systemUptime
        let fresh = now - lastSample > 0.3
        lastSample = now
        let dt = fresh ? 0 : lastTimestamp.map { m.timestamp - $0 } ?? 0
        lastTimestamp = m.timestamp
        if recenter || reference == nil {
            reference = m.attitude.copy() as? CMAttitude
            left = 0
            recenter = false
        }
        guard let attitude = m.attitude.copy() as? CMAttitude, let reference else { return }
        attitude.multiply(byInverseOf: reference)
        // Left/right: add up turns around the real vertical (gravity), like WatchPointer, so it works however
        // the bud is held (in an ear or pinched in a hand). Gyro drifts slowly; re-center fixes it.
        let g = m.gravity, r = m.rotationRate
        let gLength = sqrt(g.x * g.x + g.y * g.y + g.z * g.z)
        if gLength > 0.5, dt > 0, dt < 0.2 {
            left -= (r.x * g.x + r.y * g.y + r.z * g.z) / gLength * dt * 180 / .pi
        }
        // pitch > 0 = tipped up. Flip a sign here if your axis feels inverted.
        let up = attitude.pitch * 180 / .pi

        // Laser-pointer projection onto a flat wall, as in WatchPointer.
        let screen = CGDisplayBounds(CGMainDisplayID())
        let h = min(max(-left, -80), 80) * .pi / 180
        let v = min(max(up, -80), 80) * .pi / 180
        let pixelsPerUnit = screen.width / 2 / tan(reachDegrees * .pi / 180)
        let x = screen.midX + tan(h) * pixelsPerUnit
        let y = screen.midY - tan(v) / cos(h) * pixelsPerUnit

        if fresh {
            filterX.reset(); filterY.reset()
            shown = CGPoint(x: x, y: y)
        }
        target = CGPoint(x: filterX(x, dt: dt), y: filterY(y, dt: dt))
    }

    /// AirPods send ~25 samples/s, so glide at 240 Hz toward the newest one to hide the steps.
    private func startFrameLoop() {
        let frame = 1.0 / 240
        let follow = 1 - exp(-frame / 0.04) // ~40 ms catch-up: one AirPods sample interval
        let timer = DispatchSource.makeTimerSource(flags: .strict, queue: queue)
        timer.schedule(deadline: .now(), repeating: frame, leeway: .microseconds(200))
        timer.setEventHandler { [weak self] in self?.tick(follow: follow) }
        timer.resume()
        frameTimer = timer
    }

    private func tick(follow: Double) {
        let now = ProcessInfo.processInfo.systemUptime
        guard !paused, let target, now - lastSample < 0.3 else { return } // idle: leave the trackpad alone
        let next = CGPoint(x: shown.x + (target.x - shown.x) * follow, y: shown.y + (target.y - shown.y) * follow)
        guard abs(next.x - shown.x) + abs(next.y - shown.y) > 0.05 else { return }
        shown = next
        let screen = CGDisplayBounds(CGMainDisplayID())
        let p = CGPoint(x: min(max(next.x, screen.minX), screen.maxX - 1), y: min(max(next.y, screen.minY), screen.maxY - 1))
        post(.mouseMoved, p)
        if now - lastLog > 0.1 {
            lastLog = now
            print(String(format: "\rpointer %5.0f, %5.0f   ", p.x, p.y), terminator: "")
        }
    }

    private func post(_ type: CGEventType, _ p: CGPoint) {
        CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: p, mouseButton: .left)?.post(tap: .cghidEventTap)
    }

    // MARK: Stem presses

    /// AirPods stem presses arrive as media commands, which go to whichever app is "now playing".
    /// shortcut: claims Now Playing without playing audio; if Music/Spotify is playing, it gets the presses instead.
    private func listenToStem() {
        let info = MPNowPlayingInfoCenter.default()
        info.nowPlayingInfo = [MPMediaItemPropertyTitle: "HeadPointer"]
        info.playbackState = .playing
        let center = MPRemoteCommandCenter.shared()
        let queue = queue
        let handle = { (action: @escaping () -> Void) -> (MPRemoteCommandEvent) -> MPRemoteCommandHandlerStatus in
            { [queue] _ in
                queue.async(execute: action)
                info.playbackState = .playing // stay "now playing" so the next press comes here too
                return .success
            }
        }
        let click = handle { [weak self] in self?.click() }
        center.togglePlayPauseCommand.addTarget(handler: click)
        center.playCommand.addTarget(handler: click)
        center.pauseCommand.addTarget(handler: click)
        center.nextTrackCommand.addTarget(handler: handle { [weak self] in
            self?.recenter = true
            print("\ncentered")
        })
        center.previousTrackCommand.addTarget(handler: handle { [weak self] in
            guard let self else { return }
            paused.toggle()
            if !paused { recenter = true }
            print(paused ? "\npaused" : "\nresumed")
        })
    }

    private func click() {
        guard !paused else { return }
        let p = CGEvent(source: nil)?.location ?? shown
        post(.leftMouseDown, p)
        post(.leftMouseUp, p)
        print("\nclick")
    }
}

let prompt = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
if !AXIsProcessTrustedWithOptions([prompt: true] as CFDictionary) {
    print("Grant Accessibility access to HeadPointer (System Settings › Privacy & Security › Accessibility), then rerun.")
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let pointer = HeadPointer()
app.run()
