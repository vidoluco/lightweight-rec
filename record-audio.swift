// record-audio: the system audio side of a recording, captured natively.
//
//   record-audio capture FIFO [--ready FILE]
//                       stream what the Mac is playing into FIFO as raw PCM
//                       (float32 little endian, 48 kHz, 2 channels) until the
//                       reader goes away. `record` hands that FIFO to ffmpeg
//                       as a second input and mixes it with the microphone.
//                       With --ready, FILE is created the moment the capture
//                       is up, before the FIFO is opened: the caller waits on
//                       that file, and a helper that dies first never reaches
//                       it, so a start can tell "ready" from "failed" without
//                       guessing at a timeout.
//   record-audio down [PREVIOUS OUTPUT]
//                       remove the Record-In and Record-Out aggregate devices
//                       that versions up to 0.2 created around BlackHole, and
//                       select PREVIOUS OUTPUT as the system output if given.
//                       Harmless when there is nothing to remove.
//
// How the capture works: ScreenCaptureKit taps the audio the system is about
// to play, before it reaches the output device. Nothing is routed anywhere,
// no driver is installed, the output device is not switched, and the volume
// keys keep working. Headphones, speakers, AirPods: all the same to it. The
// audio arrives continuously, silence included, 50 buffers a second, so the
// FIFO never starves ffmpeg's mixer; a watchdog pads silence for any gap,
// which can happen while the output device changes.
//
// Why a FIFO and not a device: ffmpeg can only read audio from something that
// looks like an input, and the old way to make system audio look like an input
// was a loopback driver (BlackHole) plus two CoreAudio aggregates, which is
// what took the volume keys away. A raw stream on a named pipe needs none of
// that.
//
// Permissions: the same Screen Recording grant ffmpeg's screen capture already
// needs, attributed to the process that launched us (skhd for Option+R, the
// terminal for `record start`). No new dialog.
//
// Requires macOS 13: that is where ScreenCaptureKit learned to capture audio.
//
// Compile (install.sh does this):
//   swiftc -O -o ~/bin/record-audio record-audio.swift \
//     -framework ScreenCaptureKit -framework CoreMedia -framework CoreAudio

import CoreAudio
import CoreMedia
import Foundation
import ScreenCaptureKit

let SAMPLE_RATE: Double = 48000
let CHANNELS = 2

// Every device the 0.2 helper created carried this prefix. Recognising them by
// UID and not by display name survives a rename in Audio MIDI Setup.
let LEGACY_UID_IN = "app.lightweight-rec.in"
let LEGACY_UID_OUT = "app.lightweight-rec.out"

func log(_ message: String) {
    FileHandle.standardError.write("record-audio: \(message)\n".data(using: .utf8)!)
}

// ------------------------------------------------------------------ CoreAudio
// Only what `down` needs: enumerate devices, read a name or UID, pick the
// default output. Kept small on purpose; the capture path uses none of it.

func stringProp(_ id: AudioObjectID, _ selector: AudioObjectPropertySelector) -> String? {
    var addr = AudioObjectPropertyAddress(
        mSelector: selector,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain)
    var value: CFString = "" as CFString
    var size = UInt32(MemoryLayout<CFString>.size)
    let err = withUnsafeMutablePointer(to: &value) {
        AudioObjectGetPropertyData(id, &addr, 0, nil, &size, $0)
    }
    return err == noErr ? value as String : nil
}

func allDevices() -> [AudioDeviceID] {
    var addr = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDevices,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain)
    var size: UInt32 = 0
    guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size) == noErr else { return [] }
    var ids = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
    guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &ids) == noErr else { return [] }
    return ids
}

func outputChannels(_ id: AudioDeviceID) -> Int {
    var addr = AudioObjectPropertyAddress(
        mSelector: kAudioDevicePropertyStreamConfiguration,
        mScope: kAudioDevicePropertyScopeOutput,
        mElement: kAudioObjectPropertyElementMain)
    var size: UInt32 = 0
    guard AudioObjectGetPropertyDataSize(id, &addr, 0, nil, &size) == noErr, size > 0 else { return 0 }
    let raw = UnsafeMutableRawPointer.allocate(
        byteCount: Int(size),
        alignment: MemoryLayout<AudioBufferList>.alignment)
    defer { raw.deallocate() }
    guard AudioObjectGetPropertyData(id, &addr, 0, nil, &size, raw) == noErr else { return 0 }
    let list = UnsafeMutableAudioBufferListPointer(raw.assumingMemoryBound(to: AudioBufferList.self))
    return list.reduce(0) { $0 + Int($1.mNumberChannels) }
}

func setDefaultOutput(_ id: AudioDeviceID) -> Bool {
    var addr = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDefaultOutputDevice,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain)
    var dev = id
    let size = UInt32(MemoryLayout<AudioDeviceID>.size)
    return AudioObjectSetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, size, &dev) == noErr
}

// Tear down what an older version left behind. Returns how many devices went.
func destroyLegacyAggregates() -> Int {
    var removed = 0
    for id in allDevices() {
        let uid = stringProp(id, kAudioDevicePropertyDeviceUID) ?? ""
        if uid == LEGACY_UID_IN || uid == LEGACY_UID_OUT {
            if AudioHardwareDestroyAggregateDevice(id) == noErr { removed += 1 }
        }
    }
    return removed
}

// ------------------------------------------------------------------- capture

@available(macOS 13.0, *)
final class SystemAudioWriter: NSObject, SCStreamOutput, SCStreamDelegate {
    private let queue = DispatchQueue(label: "app.lightweight-rec.audio")
    private var fd: Int32 = -1
    private var scratch = [Float](repeating: 0, count: 4096 * CHANNELS)
    private var lastWrite = Date()
    private var formatChecked = false
    private var buffers = 0
    private var padded = 0
    private var watchdog: DispatchSourceTimer?

    var handlerQueue: DispatchQueue { queue }

    // Called once the reader is connected. From here on every buffer is written.
    func attach(fd: Int32) {
        queue.sync {
            self.fd = fd
            self.lastWrite = Date()
            let timer = DispatchSource.makeTimerSource(queue: queue)
            timer.schedule(deadline: .now() + 0.25, repeating: 0.25)
            timer.setEventHandler { [weak self] in self?.padGapIfAny() }
            timer.resume()
            self.watchdog = timer
        }
    }

    // ScreenCaptureKit delivers a buffer every 20 ms, silence included. If it
    // stops, the mixer on the other side of the FIFO would wait forever for
    // this input, so any gap longer than half a second is filled with silence
    // of the same length. That keeps the mix moving and keeps the timeline
    // honest: the microphone track is not shifted against the video.
    private func padGapIfAny() {
        guard fd >= 0 else { return }
        let gap = Date().timeIntervalSince(lastWrite)
        guard gap > 0.5 else { return }
        let frames = Int(gap * SAMPLE_RATE)
        let zeros = [Float](repeating: 0, count: frames * CHANNELS)
        if padded == 0 {
            log("no system audio for \(String(format: "%.1f", gap))s, padding with silence (output device changing?)")
        }
        padded += 1
        writeAll(zeros)
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sb: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .audio, fd >= 0 else { return }
        if !formatChecked {
            formatChecked = true
            if let asbd = sb.formatDescription?.audioStreamBasicDescription {
                let isFloat = (asbd.mFormatFlags & kAudioFormatFlagIsFloat) != 0
                if asbd.mSampleRate != SAMPLE_RATE || Int(asbd.mChannelsPerFrame) != CHANNELS || !isFloat || asbd.mBitsPerChannel != 32 {
                    // ffmpeg was told 48 kHz stereo float on the other end of the
                    // pipe, so anything else would play at the wrong speed. Fail
                    // out loud; the caller records the microphone alone.
                    log("unexpected audio format from ScreenCaptureKit: \(asbd.mSampleRate) Hz, \(asbd.mChannelsPerFrame) ch, \(asbd.mBitsPerChannel) bit, float=\(isFloat)")
                    exit(2)
                }
            }
        }
        do {
            try sb.withAudioBufferList(flags: []) { abl, _ in
                let frames = Int(sb.numSamples)
                guard frames > 0 else { return }
                let needed = frames * CHANNELS
                if scratch.count < needed { scratch = [Float](repeating: 0, count: needed) }
                if abl.count >= CHANNELS {
                    // Non-interleaved, one buffer per channel: interleave into
                    // L R L R, which is what f32le with -ac 2 means to ffmpeg.
                    for ch in 0..<CHANNELS {
                        guard let src = abl[ch].mData?.assumingMemoryBound(to: Float.self) else { continue }
                        let avail = min(frames, Int(abl[ch].mDataByteSize) / MemoryLayout<Float>.size)
                        for i in 0..<avail { scratch[i * CHANNELS + ch] = src[i] }
                    }
                } else if let src = abl[0].mData?.assumingMemoryBound(to: Float.self) {
                    // Already interleaved: copy through.
                    let avail = min(needed, Int(abl[0].mDataByteSize) / MemoryLayout<Float>.size)
                    for i in 0..<avail { scratch[i] = src[i] }
                }
                writeAll(Array(scratch[0..<needed]))
            }
        } catch {
            log("could not read an audio buffer: \(error)")
        }
        buffers += 1
    }

    private func writeAll(_ samples: [Float]) {
        samples.withUnsafeBytes { raw in
            var offset = 0
            let total = raw.count
            while offset < total {
                let n = write(fd, raw.baseAddress! + offset, total - offset)
                if n < 0 {
                    if errno == EINTR { continue }
                    // EPIPE: ffmpeg closed its end, which is how every stop
                    // looks from here. Anything else is worth a line.
                    if errno != EPIPE { log("write failed: \(String(cString: strerror(errno)))") }
                    finish(code: 0)
                }
                offset += n
            }
        }
        lastWrite = Date()
    }

    func finish(code: Int32) -> Never {
        if fd >= 0 { close(fd) }
        log("stopped after \(buffers) buffers\(padded > 0 ? ", \(padded) silence pads" : "")")
        exit(code)
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        // Screen Recording revoked mid-take, or the display went away. ffmpeg
        // sees end of stream on this input and carries on with the microphone.
        log("capture stopped by the system: \(error.localizedDescription)")
        finish(code: 2)
    }
}

@available(macOS 13.0, *)
func capture(fifo: String, ready: String?) -> Never {
    // The reader may vanish at any moment; a dead pipe must be an error we
    // handle, not a signal that kills us before the log line is written.
    signal(SIGPIPE, SIG_IGN)
    signal(SIGTERM) { _ in exit(0) }
    signal(SIGINT) { _ in exit(0) }

    let writer = SystemAudioWriter()
    let started = DispatchSemaphore(value: 0)
    var failure: String?
    var stream: SCStream?

    Task {
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
            guard let display = content.displays.first else {
                failure = "no display to attach the audio capture to"
                started.signal()
                return
            }
            // Audio only. The stream still needs a display to exist on, so it
            // gets one at 2x2 pixels and one frame a second, and no video
            // output is ever added to it: the screen is ffmpeg's job.
            let filter = SCContentFilter(display: display, excludingWindows: [])
            let cfg = SCStreamConfiguration()
            cfg.capturesAudio = true
            cfg.sampleRate = Int(SAMPLE_RATE)
            cfg.channelCount = CHANNELS
            cfg.excludesCurrentProcessAudio = true
            cfg.width = 2
            cfg.height = 2
            cfg.minimumFrameInterval = CMTime(value: 1, timescale: 1)
            cfg.showsCursor = false
            let s = SCStream(filter: filter, configuration: cfg, delegate: writer)
            try s.addStreamOutput(writer, type: .audio, sampleHandlerQueue: writer.handlerQueue)
            try await s.startCapture()
            stream = s
        } catch {
            failure = error.localizedDescription
        }
        started.signal()
    }
    started.wait()
    if let why = failure {
        log("could not start the system audio capture: \(why)")
        log("if this is a permission problem: System Settings > Privacy and Security > Screen Recording")
        exit(1)
    }
    _ = stream

    if let ready = ready {
        FileManager.default.createFile(atPath: ready, contents: nil)
    }
    log("capturing system audio, waiting for the reader on \(fifo)")

    // Blocks until ffmpeg opens the other end. Buffers that arrive meanwhile
    // are dropped on purpose: the recording starts when the reader does.
    let fd = open(fifo, O_WRONLY)
    if fd < 0 {
        log("cannot open \(fifo) for writing: \(String(cString: strerror(errno)))")
        exit(1)
    }
    writer.attach(fd: fd)
    log("reader connected, streaming")
    dispatchMain()
}

// ------------------------------------------------------------------- main

let args = CommandLine.arguments
let command = args.count > 1 ? args[1] : ""

switch command {
case "capture":
    guard args.count > 2 else {
        log("usage: record-audio capture FIFO [--ready FILE]")
        exit(1)
    }
    let fifo = args[2]
    var ready: String?
    var i = 3
    while i < args.count {
        if args[i] == "--ready", i + 1 < args.count {
            ready = args[i + 1]
            i += 2
        } else {
            log("unknown argument: \(args[i])")
            exit(1)
        }
    }
    if #available(macOS 13.0, *) {
        capture(fifo: fifo, ready: ready)
    } else {
        log("system audio capture needs macOS 13 or newer")
        exit(3)
    }

case "down":
    let removed = destroyLegacyAggregates()
    if removed > 0 { log("removed \(removed) legacy aggregate device(s)") }
    if args.count > 2 {
        let wanted = args[2]
        if let id = allDevices().first(where: { stringProp($0, kAudioObjectPropertyName) == wanted && outputChannels($0) > 0 }) {
            if !setDefaultOutput(id) { log("could not select \"\(wanted)\" as the output") }
        } else {
            log("no output device named \"\(wanted)\"; pick one in Sound settings")
        }
    }

default:
    print("Usage: record-audio capture FIFO [--ready FILE] | down [PREVIOUS OUTPUT]")
    exit(1)
}
