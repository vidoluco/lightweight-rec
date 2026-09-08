// record-audio: create and tear down the aggregate devices for full-call audio.
//
//   record-audio up     create "Record-In" (mic + BlackHole) and "Record-Out"
//                       (current output + BlackHole). Current output is read now:
//                       AirPods at the office, speakers at home, nothing to configure.
//   record-audio down   destroy both devices and return to the previous output.
//   record-audio which  print the input device "up" would record from, and touch
//                       nothing. Read only: it creates and destroys no device, so
//                       it is safe to run while a recording is going, and it is
//                       how you check what this tool thinks your microphone is.
//
// Why it exists: ffmpeg can only read input devices, and the other people on a
// call (coming out of the headphones) never pass through the microphone.
// BlackHole is a virtual cable: "Record-Out" duplicates output to the
// headphones AND to the cable, "Record-In" mixes mic and cable. Result:
// both voices in one device, which ffmpeg records.
//
// stdout is a contract the caller depends on:
//   up     exactly one line, the name of the output device that was selected
//          before the switch. `record` writes that line to .previous-output and
//          hands it back to switchaudiosource on stop, so a second line here
//          would corrupt the restore and leave the Mac on the wrong output.
//          The resolved input device is reported on stderr instead, and on
//          stdout by `which`.
//   which  exactly one line, the name of the resolved input device.
//   down   nothing.
//
// Compile (install.sh does this):
//   swiftc -O -o ~/bin/record-audio record-audio.swift -framework CoreAudio

import CoreAudio
import Foundation

let UID_IN = "app.lightweight-rec.in"
let UID_OUT = "app.lightweight-rec.out"
// Every device this tool creates carries this prefix. Recognising our own work
// by prefix, not by display name, survives a user renaming the device in Audio
// MIDI Setup.
let UID_PREFIX = "app.lightweight-rec."

// Names that never carry a voice: loopback cables, meeting-app shims and
// aggregates. Same list record-lib.sh screens the ffmpeg device list with, so
// the two halves of the tool agree on what a microphone is.
let VIRTUAL_TOKENS = [
    "blackhole", "soundflower", "loopback", "record-in", "record-out",
    "aggregate", "multi-output", "zoomaudiodevice", "teams audio",
    "vb-cable", "krisp",
]

// Continuity devices: a nearby iPhone offers itself as a microphone and macOS
// is happy to make it the default input. Recording a meeting through a phone
// on the far side of the desk is not what anyone meant.
let CONTINUITY_TOKENS = ["iphone", "ipad", "apple watch"]

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

func defaultDevice(_ selector: AudioObjectPropertySelector) -> AudioDeviceID? {
    var addr = AudioObjectPropertyAddress(
        mSelector: selector,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain)
    var dev = AudioDeviceID(0)
    var size = UInt32(MemoryLayout<AudioDeviceID>.size)
    guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &dev) == noErr else { return nil }
    return dev == AudioObjectID(kAudioObjectUnknown) ? nil : dev
}

func defaultOutput() -> AudioDeviceID? {
    defaultDevice(kAudioHardwarePropertyDefaultOutputDevice)
}

// The device the Mac itself records from. This is the whole portability fix:
// the built-in microphone is named after the model ("Mac mini Microphone",
// "MacBook Air Microphone"), a desktop Mac may have no built-in microphone at
// all, and someone with an audio interface wants the interface. Asking
// CoreAudio which input is selected answers all three at once, and on a Mac
// whose default input is the built-in microphone it returns exactly the device
// the old hardcoded UID did.
func defaultInput() -> AudioDeviceID? {
    defaultDevice(kAudioHardwarePropertyDefaultInputDevice)
}

func deviceName(_ id: AudioDeviceID) -> String {
    stringProp(id, kAudioObjectPropertyName) ?? ""
}

// Channels a device offers on the input scope. Zero means it cannot be
// recorded from, whatever it is called: speakers and displays are devices too.
func inputChannels(_ id: AudioDeviceID) -> Int {
    var addr = AudioObjectPropertyAddress(
        mSelector: kAudioDevicePropertyStreamConfiguration,
        mScope: kAudioDevicePropertyScopeInput,
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

func transportType(_ id: AudioDeviceID) -> UInt32 {
    var addr = AudioObjectPropertyAddress(
        mSelector: kAudioDevicePropertyTransportType,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain)
    var value = UInt32(0)
    var size = UInt32(MemoryLayout<UInt32>.size)
    guard AudioObjectGetPropertyData(id, &addr, 0, nil, &size, &value) == noErr else { return 0 }
    return value
}

func findByUID(_ uid: String) -> AudioDeviceID? {
    allDevices().first { stringProp($0, kAudioDevicePropertyDeviceUID) == uid }
}

func findByName(_ fragment: String) -> AudioDeviceID? {
    allDevices().first { deviceName($0).contains(fragment) }
}

// Refused as the ingress no matter what the config says. BlackHole is the far
// end of the call, not a voice: putting it on both sides of Record-In records
// the room twice and the speaker never. Our own aggregates would nest into
// themselves.
func forbiddenIngress(_ id: AudioDeviceID) -> String? {
    let uid = stringProp(id, kAudioDevicePropertyDeviceUID) ?? ""
    if uid == UID_IN || uid == UID_OUT || uid.hasPrefix(UID_PREFIX) {
        return "it is an aggregate this tool created"
    }
    if deviceName(id).lowercased().contains("blackhole") {
        return "it is the BlackHole loopback, which carries the other side of the call, not your voice"
    }
    return nil
}

// Additionally skipped when nothing was asked for by name. A user who names one
// of these explicitly gets it: a noise-suppression shim in front of a real
// microphone is a legitimate choice, guessing your way into one is not.
func autoSkip(_ id: AudioDeviceID) -> Bool {
    if forbiddenIngress(id) != nil { return true }
    if transportType(id) == kAudioDeviceTransportTypeAggregate { return true }
    let name = deviceName(id).lowercased()
    return VIRTUAL_TOKENS.contains { name.contains($0) }
}

enum Resolved {
    case device(AudioDeviceID, String)
    case failure(String)
}

// Order of preference, once RECORD_MIC has had its say:
//   1. the input the Mac is set to record from (kAudioHardwarePropertyDefaultInputDevice)
//   2. a built-in microphone, whatever this model calls it
//   3. any other real microphone, an interface or a USB one
//   4. the first remaining input
func resolveInput() -> Resolved {
    let inputs = allDevices().filter { inputChannels($0) > 0 }
    if inputs.isEmpty {
        return .failure("no audio input device on this Mac: nothing can be recorded from.")
    }

    let requested = (ProcessInfo.processInfo.environment["RECORD_MIC"] ?? "")
        .trimmingCharacters(in: .whitespacesAndNewlines)
    if !requested.isEmpty {
        let wanted = requested.lowercased()
        let exact = inputs.first { deviceName($0).lowercased() == wanted }
        let partial = inputs.first { deviceName($0).lowercased().contains(wanted) }
        guard let id = exact ?? partial else {
            // A device of that name may well exist and simply have no input:
            // saying "not found" about the speakers sitting right there sends
            // the reader looking for a typo that is not the problem.
            let outputOnly = allDevices().first { deviceName($0).lowercased().contains(wanted) }
            if let other = outputOnly {
                return .failure("RECORD_MIC is \"\(requested)\" and \"\(deviceName(other))\" is an output "
                    + "device: it has no input channels, so nothing can be recorded from it.")
            }
            return .failure("RECORD_MIC is \"\(requested)\" and no audio input on this Mac carries that name. "
                + "List them with: ffmpeg -f avfoundation -list_devices true -i \"\"")
        }
        if let why = forbiddenIngress(id) {
            return .failure("RECORD_MIC picks \"\(deviceName(id))\" and \(why). "
                + "Set it to the microphone you talk into.")
        }
        return .device(id, deviceName(id))
    }

    if let id = defaultInput(), inputs.contains(id), !autoSkip(id) {
        return .device(id, deviceName(id))
    }
    if let id = inputs.first(where: { transportType($0) == kAudioDeviceTransportTypeBuiltIn && !autoSkip($0) }) {
        return .device(id, deviceName(id))
    }
    if let id = inputs.first(where: {
        let name = deviceName($0).lowercased()
        return name.contains("microphone")
            && !CONTINUITY_TOKENS.contains(where: { name.contains($0) })
            && !autoSkip($0)
    }) {
        return .device(id, deviceName(id))
    }
    if let id = inputs.first(where: { !autoSkip($0) }) {
        return .device(id, deviceName(id))
    }
    return .failure("every audio input on this Mac is a loopback or an aggregate, and none of them "
        + "carries a voice. Set RECORD_MIC to the microphone you talk into.")
}

func fail(_ message: String) {
    FileHandle.standardError.write("record-audio: \(message)\n".data(using: .utf8)!)
}

func destroy() {
    for uid in [UID_IN, UID_OUT] {
        if let id = findByUID(uid) {
            AudioHardwareDestroyAggregateDevice(id)
        }
    }
}

func create(name: String, uid: String, subs: [String], master: String, stacked: Bool) -> Bool {
    let list = subs.map { sub -> [String: Any] in
        [kAudioSubDeviceUIDKey: sub,
         // drift compensation goes on the non-master devices: AirPods and
         // BlackHole clocks do not tick together, someone has to adapt
         kAudioSubDeviceDriftCompensationKey: sub == master ? 0 : 1]
    }
    var desc: [String: Any] = [
        kAudioAggregateDeviceNameKey: name,
        kAudioAggregateDeviceUIDKey: uid,
        kAudioAggregateDeviceSubDeviceListKey: list,
        kAudioAggregateDeviceMainSubDeviceKey: master,
    ]
    if stacked { desc[kAudioAggregateDeviceIsStackedKey] = 1 }  // multi-output, not aggregate
    var id = AudioDeviceID(0)
    return AudioHardwareCreateAggregateDevice(desc as CFDictionary, &id) == noErr
}

let command = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : ""

switch command {
case "up":
    destroy()  // leftovers from a previous start must not accumulate

    guard let bh = findByName("BlackHole 2ch"),
          let bhUID = stringProp(bh, kAudioDevicePropertyDeviceUID) else {
        fail("BlackHole not installed: brew install --cask blackhole-2ch")
        exit(2)
    }
    // resolved after destroy(): a crashed run can leave Record-In behind as the
    // default input, and it must not be picked as the microphone that feeds the
    // Record-In we are about to build.
    let micID: AudioDeviceID
    let micName: String
    switch resolveInput() {
    case .device(let id, let name):
        micID = id
        micName = name
    case .failure(let why):
        fail(why)
        exit(1)
    }
    guard let micUID = stringProp(micID, kAudioDevicePropertyDeviceUID) else {
        fail("\"\(micName)\" has no CoreAudio UID, so it cannot go into an aggregate.")
        exit(1)
    }
    guard let out = defaultOutput(),
          let outUID = stringProp(out, kAudioDevicePropertyDeviceUID),
          outUID != UID_OUT else {
        fail("system output is not readable")
        exit(1)
    }

    guard create(name: "Record-In", uid: UID_IN, subs: [micUID, bhUID], master: micUID, stacked: false),
          create(name: "Record-Out", uid: UID_OUT, subs: [outUID, bhUID], master: outUID, stacked: true) else {
        fail("failed to create the aggregate devices")
        destroy()
        exit(1)
    }
    // stderr, not stdout: stdout below belongs to the previous output name.
    fail("microphone side of Record-In is \"\(micName)\"")
    // name of the previous output: printed so the script can save and restore it
    print(stringProp(out, kAudioObjectPropertyName) ?? "")

case "down":
    destroy()

case "which":
    // Read only on purpose: nothing here creates, destroys or selects a device.
    switch resolveInput() {
    case .device(_, let name):
        print(name)
    case .failure(let why):
        fail(why)
        exit(1)
    }

default:
    print("Usage: record-audio up|down|which")
    exit(1)
}
