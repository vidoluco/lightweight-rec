// record-dot — red recording dot on the display ffmpeg is capturing.
//
//   record-dot screens
//       tab-separated: index, display id, name, WxH, flags (main)
//       index matches ffmpeg "Capture screen N" and CGGetActiveDisplayList.
//
//   record-dot on [--screen N] [--pid-file PATH] [--watch-pid-file PATH]
//       borderless always-on-top red dot, top-right of that display.
//       Does not steal focus or mouse. Stays until SIGTERM, or until the
//       ffmpeg pid in --watch-pid-file dies.
//
// Compile (install.sh does this):
//   swiftc -O -o ~/bin/record-dot record-dot.swift -framework AppKit

import AppKit
import CoreGraphics
import Darwin
import Foundation

struct Display {
    let index: Int
    let id: CGDirectDisplayID
    let name: String
    let width: Int
    let height: Int
    let main: Bool
    let screen: NSScreen?
}

func activeDisplays() -> [Display] {
    var count: UInt32 = 0
    CGGetActiveDisplayList(0, nil, &count)
    var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
    CGGetActiveDisplayList(count, &ids, &count)

    let mainID = CGMainDisplayID()
    var result: [Display] = []
    for (i, id) in ids.enumerated() {
        let screen = NSScreen.screens.first {
            ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value == id
        }
        let bounds = CGDisplayBounds(id)
        result.append(Display(
            index: i,
            id: id,
            name: screen?.localizedName ?? "Display \(i)",
            width: Int(bounds.width.rounded()),
            height: Int(bounds.height.rounded()),
            main: id == mainID,
            screen: screen
        ))
    }
    return result
}

func printScreens() {
    for d in activeDisplays() {
        let flags = d.main ? "main" : ""
        print("\(d.index)\t\(d.id)\t\(d.name)\t\(d.width)x\(d.height)\t\(flags)")
    }
}

func writePid(_ path: String) {
    try? "\(ProcessInfo.processInfo.processIdentifier)\n".write(toFile: path, atomically: true, encoding: .utf8)
}

func pidAlive(_ pid: pid_t) -> Bool {
    pid > 0 && kill(pid, 0) == 0
}

class DotView: NSView {
    private var pulse: CGFloat = 1
    private var rising = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        Timer.scheduledTimer(withTimeInterval: 0.06, repeats: true) { [weak self] _ in
            guard let self else { return }
            if self.rising {
                self.pulse += 0.04
                if self.pulse >= 1 { self.pulse = 1; self.rising = false }
            } else {
                self.pulse -= 0.04
                if self.pulse <= 0.45 { self.pulse = 0.45; self.rising = true }
            }
            self.needsDisplay = true
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.clear.setFill()
        bounds.fill()
        let ring = bounds.insetBy(dx: 1.5, dy: 1.5)
        NSColor.white.withAlphaComponent(0.92).setFill()
        NSBezierPath(ovalIn: ring).fill()
        let core = bounds.insetBy(dx: 4, dy: 4)
        NSColor(calibratedRed: 1, green: 0.18, blue: 0.14, alpha: pulse).setFill()
        NSBezierPath(ovalIn: core).fill()
    }
}

func showDot(screenIndex: Int, pidFile: String?, watchPidFile: String?) {
    let displays = activeDisplays()
    guard let display = displays.first(where: { $0.index == screenIndex }) else {
        fputs("record-dot: no display at index \(screenIndex)\n", stderr)
        exit(1)
    }
    guard let ns = display.screen else {
        fputs("record-dot: display \(screenIndex) has no NSScreen\n", stderr)
        exit(1)
    }

    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)

    let size: CGFloat = 22
    let pad: CGFloat = 12
    let vis = ns.visibleFrame
    let frame = NSRect(
        x: vis.maxX - pad - size,
        y: vis.maxY - pad - size,
        width: size,
        height: size
    )

    let window = NSWindow(
        contentRect: frame,
        styleMask: .borderless,
        backing: .buffered,
        defer: false
    )
    window.isOpaque = false
    window.backgroundColor = .clear
    window.hasShadow = false
    window.level = .statusBar
    window.ignoresMouseEvents = true
    window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle, .transient]
    window.hidesOnDeactivate = false
    window.isReleasedWhenClosed = false
    if #available(macOS 10.13, *) {
        window.sharingType = .none
    }
    window.contentView = DotView(frame: NSRect(origin: .zero, size: frame.size))
    window.orderFrontRegardless()

    if let pidFile { writePid(pidFile) }

    if let watchPidFile {
        Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            guard let raw = try? String(contentsOfFile: watchPidFile, encoding: .utf8) else { return }
            let pid = pid_t(raw.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
            if pid > 0 && !pidAlive(pid) {
                app.terminate(nil)
            }
        }
    }

    signal(SIGTERM) { _ in
        DispatchQueue.main.async { NSApp.terminate(nil) }
    }
    signal(SIGINT) { _ in
        DispatchQueue.main.async { NSApp.terminate(nil) }
    }

    app.run()
}

func parseFlag(_ args: [String], _ name: String) -> String? {
    guard let i = args.firstIndex(of: name), i + 1 < args.count else { return nil }
    return args[i + 1]
}

let args = Array(CommandLine.arguments.dropFirst())
let command = args.first ?? ""

switch command {
case "screens":
    printScreens()
case "on":
    let screen = Int(parseFlag(args, "--screen") ?? "0") ?? 0
    showDot(
        screenIndex: screen,
        pidFile: parseFlag(args, "--pid-file"),
        watchPidFile: parseFlag(args, "--watch-pid-file")
    )
default:
    fputs("Usage: record-dot screens | on [--screen N] [--pid-file PATH] [--watch-pid-file PATH]\n", stderr)
    exit(1)
}
