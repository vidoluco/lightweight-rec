// registra-audio — crea e distrugge i dispositivi audio per la registrazione completa.
//
//   registra-audio su    crea "Registra-In" (microfono + BlackHole) e "Registra-Out"
//                        (uscita attuale + BlackHole). L'uscita attuale viene letta al
//                        momento: AirPods in ufficio, casse a casa, senza configurare niente.
//   registra-audio giu   distrugge i due dispositivi e si torna come prima.
//
// Perche' esiste: ffmpeg puo' leggere solo dispositivi di ingresso, e l'audio degli
// altri in call (che esce nelle cuffie) non passa mai per il microfono. BlackHole e'
// un cavo virtuale: "Registra-Out" duplica l'uscita verso le cuffie E verso il cavo,
// "Registra-In" mette insieme microfono e cavo. Risultato: entrambe le voci in un
// solo dispositivo, che ffmpeg registra.
//
// Compilazione (la fa installa.sh):
//   swiftc -O -o ~/bin/registra-audio registra-audio.swift -framework CoreAudio

import CoreAudio
import Foundation

let UID_IN = "it.ludovico.registra.in"
let UID_OUT = "it.ludovico.registra.out"

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

func findByName(_ frammento: String) -> AudioDeviceID? {
    allDevices().first { (stringProp($0, kAudioObjectPropertyName) ?? "").contains(frammento) }
}

func distruggi() {
    for uid in [UID_IN, UID_OUT] {
        if let id = findByUID(uid) {
            AudioHardwareDestroyAggregateDevice(id)
        }
    }
}

func crea(nome: String, uid: String, sotto: [String], master: String, impilato: Bool) -> Bool {
    let lista = sotto.map { su -> [String: Any] in
        [kAudioSubDeviceUIDKey: su,
         // la compensazione di deriva va sui dispositivi NON master: i clock
         // di AirPods e BlackHole non battono insieme, qualcuno deve adattarsi
         kAudioSubDeviceDriftCompensationKey: su == master ? 0 : 1]
    }
    var desc: [String: Any] = [
        kAudioAggregateDeviceNameKey: nome,
        kAudioAggregateDeviceUIDKey: uid,
        kAudioAggregateDeviceSubDeviceListKey: lista,
        kAudioAggregateDeviceMainSubDeviceKey: master,
    ]
    if impilato { desc[kAudioAggregateDeviceIsStackedKey] = 1 }  // "multi-uscita", non aggregato
    var id = AudioDeviceID(0)
    return AudioHardwareCreateAggregateDevice(desc as CFDictionary, &id) == noErr
}

let comando = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : ""

switch comando {
case "su":
    distruggi()  // residui di un avvio precedente non devono accumularsi

    guard let bh = findByName("BlackHole 2ch"),
          let bhUID = stringProp(bh, kAudioDevicePropertyDeviceUID) else {
        FileHandle.standardError.write("BlackHole non installato: brew install blackhole-2ch\n".data(using: .utf8)!)
        exit(2)
    }
    let mic = findByUID("BuiltInMicrophoneDevice") ?? findByName("MacBook Pro Microphone")
    guard let micID = mic, let micUID = stringProp(micID, kAudioDevicePropertyDeviceUID) else {
        FileHandle.standardError.write("Microfono interno non trovato\n".data(using: .utf8)!)
        exit(1)
    }
    guard let out = defaultOutput(),
          let outUID = stringProp(out, kAudioDevicePropertyDeviceUID),
          outUID != UID_OUT else {
        FileHandle.standardError.write("Uscita di sistema non leggibile\n".data(using: .utf8)!)
        exit(1)
    }

    guard crea(nome: "Registra-In", uid: UID_IN, sotto: [micUID, bhUID], master: micUID, impilato: false),
          crea(nome: "Registra-Out", uid: UID_OUT, sotto: [outUID, bhUID], master: outUID, impilato: true) else {
        FileHandle.standardError.write("Creazione dispositivi fallita\n".data(using: .utf8)!)
        distruggi()
        exit(1)
    }
    // il nome dell'uscita di prima: lo stampa perche' lo script lo salvi e lo ripristini
    print(stringProp(out, kAudioObjectPropertyName) ?? "")

case "giu":
    distruggi()

default:
    print("Uso: registra-audio su|giu")
    exit(1)
}
