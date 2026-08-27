// record-audio — create and tear down the aggregate devices for full-call audio.
//
//   record-audio up    create "Record-In" (mic + BlackHole) and "Record-Out"
//                      (current output + BlackHole). Current output is read now:
//                      AirPods at the office, speakers at home, nothing to configure.
//   record-audio down  destroy both devices and return to the previous output.
//
// Why it exists: ffmpeg can only read input devices, and the other people on a
// call (coming out of the headphones) never pass through the microphone.
// BlackHole is a virtual cable: "Record-Out" duplicates output to the
// headphones AND to the cable, "Record-In" mixes mic and cable. Result:
// both voices in one device, which ffmpeg records.
//
// Compile (install.sh does this):
//   swiftc -O -o ~/bin/record-audio record-audio.swift -framework CoreAudio

import CoreAudio
import Foundation

let UID_IN = "app.lightweight-rec.in"
let UID_OUT = "app.lightweight-rec.out"

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

func defaultOutput() -> AudioDeviceID? {
    var addr = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDefaultOutputDevice,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain)
    var dev = AudioDeviceID(0)
    var size = UInt32(MemoryLayout<AudioDeviceID>.size)
    guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &dev) == noErr else { return nil }
    return dev
}

func findByUID(_ uid: String) -> AudioDeviceID? {
    allDevices().first { stringProp($0, kAudioDevicePropertyDeviceUID) == uid }
}

func findByName(_ fragment: String) -> AudioDeviceID? {
    allDevices().first { (stringProp($0, kAudioObjectPropertyName) ?? "").contains(fragment) }
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
        FileHandle.standardError.write("BlackHole not installed: brew install blackhole-2ch\n".data(using: .utf8)!)
        exit(2)
    }
    let mic = findByUID("BuiltInMicrophoneDevice") ?? findByName("MacBook Pro Microphone")
    guard let micID = mic, let micUID = stringProp(micID, kAudioDevicePropertyDeviceUID) else {
        FileHandle.standardError.write("Built-in microphone not found\n".data(using: .utf8)!)
        exit(1)
    }
    guard let out = defaultOutput(),
          let outUID = stringProp(out, kAudioDevicePropertyDeviceUID),
          outUID != UID_OUT else {
        FileHandle.standardError.write("System output is not readable\n".data(using: .utf8)!)
        exit(1)
    }

    guard create(name: "Record-In", uid: UID_IN, subs: [micUID, bhUID], master: micUID, stacked: false),
          create(name: "Record-Out", uid: UID_OUT, subs: [outUID, bhUID], master: outUID, stacked: true) else {
        FileHandle.standardError.write("Failed to create aggregate devices\n".data(using: .utf8)!)
        destroy()
        exit(1)
    }
    // name of the previous output: printed so the script can save and restore it
    print(stringProp(out, kAudioObjectPropertyName) ?? "")

case "down":
    destroy()

default:
    print("Usage: record-audio up|down")
    exit(1)
}
