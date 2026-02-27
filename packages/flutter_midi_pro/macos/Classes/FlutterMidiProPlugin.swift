import FlutterMacOS
import CoreMIDI
import AVFAudio
import AVFoundation
import CoreAudio

public class FlutterMidiProPlugin: NSObject, FlutterPlugin {
  let audioEngine = AVAudioEngine()
  var soundfontIndex = 1
  var soundfontSamplers: [Int: [AVAudioUnitSampler]] = [:]
  var soundfontURLs: [Int: URL] = [:]
  var samplerToBus: [AVAudioUnitSampler: Int] = [:]
  var nextBus = 0
  
  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(name: "flutter_midi_pro", binaryMessenger: registrar.messenger)
    let instance = FlutterMidiProPlugin()
    registrar.addMethodCallDelegate(instance, channel: channel)
  }

  private func ensureEngineStarted() throws {
    if !audioEngine.isRunning {
        try audioEngine.start()
    }
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "loadSoundfont":
        let args = call.arguments as! [String: Any]
        let path = args["path"] as! String
        let bank = args["bank"] as! Int
        let program = args["program"] as! Int
        let url = URL(fileURLWithPath: path)
        var chSamplers: [AVAudioUnitSampler] = []
        
        print("macOS MIDI: Attempting to load soundfont at \(path)")
        let fileManager = FileManager.default
        if !fileManager.fileExists(atPath: path) {
            print("macOS MIDI ERROR: File does not exist at path: \(path)")
            result(FlutterError(code: "SOUND_FONT_NOT_FOUND", message: "File not found at native path", details: path))
            return
        }

        for i in 0...15 {
            let sampler = AVAudioUnitSampler()
            audioEngine.attach(sampler)
            
            // Connect to a unique input bus on the mainMixerNode
            let bus = nextBus
            nextBus += 1
            audioEngine.connect(sampler, to: audioEngine.mainMixerNode, fromBus: 0, toBus: bus, format: nil)
            samplerToBus[sampler] = bus
            
            do {
                try sampler.loadSoundBankInstrument(at: url, program: UInt8(program), bankMSB: UInt8(kAUSampler_DefaultMelodicBankMSB), bankLSB: UInt8(bank))
            } catch let error as NSError {
                print("macOS MIDI ERROR: Failed to load sampler \(i): \(error.localizedDescription)")
                result(FlutterError(code: "SOUND_FONT_LOAD_FAILED", message: "Failed to load soundfont instrument: \(error.localizedDescription)", details: "Path: \(path), Error: \(error.code)"))
                return
            }
            chSamplers.append(sampler)
        }
        
        do {
            try ensureEngineStarted()
        } catch {
            result(FlutterError(code: "AUDIO_ENGINE_START_FAILED", message: "Failed to start shared audio engine", details: nil))
            return
        }

        soundfontSamplers[soundfontIndex] = chSamplers
        soundfontURLs[soundfontIndex] = url
        soundfontIndex += 1
        result(soundfontIndex-1)
    case "selectInstrument":
        let args = call.arguments as! [String: Any]
        let sfId = args["sfId"] as! Int
        let channel = args["channel"] as! Int
        let bank = args["bank"] as! Int
        let program = args["program"] as! Int
        guard let samplers = soundfontSamplers[sfId], channel < samplers.count else {
            result(FlutterError(code: "INVALID_ARGUMENT", message: "Invalid sfId or channel", details: "sfId: \(sfId), channel: \(channel)"))
            return
        }
        let soundfontSampler = samplers[channel]
        let soundfontUrl = soundfontURLs[sfId]!
        print("macOS MIDI: selectInstrument program \(program) bank \(bank) on chan \(channel)")
        do {
            try soundfontSampler.loadSoundBankInstrument(at: soundfontUrl, program: UInt8(program), bankMSB: UInt8(kAUSampler_DefaultMelodicBankMSB), bankLSB: UInt8(bank))
        } catch let error as NSError {
            print("macOS MIDI ERROR: selectInstrument failed: \(error.localizedDescription)")
            result(FlutterError(code: "SOUND_FONT_LOAD_FAILED", message: "Failed to load soundfont instrument: \(error.localizedDescription)", details: "sfId: \(sfId), Error: \(error.code)"))
            return
        }
        soundfontSampler.sendProgramChange(UInt8(program), bankMSB: UInt8(kAUSampler_DefaultMelodicBankMSB), bankLSB: UInt8(bank), onChannel: UInt8(channel))
        result(nil)
    case "playNote":
        let args = call.arguments as! [String: Any]
        let channel = args["channel"] as! Int
        let note = args["key"] as! Int
        let velocity = args["velocity"] as! Int
        let sfId = args["sfId"] as! Int
        guard let samplers = soundfontSamplers[sfId], channel < samplers.count else {
            return
        }
        let soundfontSampler = samplers[channel]
        print("macOS MIDI: playNote \(note) vel \(velocity) chan \(channel) sfId \(sfId)")
        soundfontSampler.startNote(UInt8(note), withVelocity: UInt8(velocity), onChannel: UInt8(channel))
        result(nil)
    case "stopNote":
        let args = call.arguments as! [String: Any]
        let channel = args["channel"] as! Int
        let note = args["key"] as! Int
        let sfId = args["sfId"] as! Int
        guard let samplers = soundfontSamplers[sfId], channel < samplers.count else {
            result(nil)
            return
        }
        let soundfontSampler = samplers[channel]
        soundfontSampler.stopNote(UInt8(note), onChannel: UInt8(channel))
        result(nil)
    case "stopAllNotes":
        let args = call.arguments as! [String: Any]
        let sfId = args["sfId"] as! Int
        guard let samplers = soundfontSamplers[sfId] else {
            result(FlutterError(code: "SOUND_FONT_NOT_FOUND", message: "Soundfont not found", details: nil))
            return
        }
        samplers.forEach { (sampler) in
            for channel in 0...15 {
                sampler.sendController(64, withValue: 0, onChannel: UInt8(channel))
                sampler.sendController(120, withValue: 0, onChannel: UInt8(channel))
            }
        }
        result(nil)
    case "controlChange":
        let args = call.arguments as! [String: Any]
        let sfId = args["sfId"] as! Int
        let channel = args["channel"] as! Int
        let controller = args["controller"] as! Int
        let value = args["value"] as! Int
        guard let sampler = soundfontSamplers[sfId]?[channel] else {
            result(FlutterError(code: "SOUND_FONT_NOT_FOUND", message: "Soundfont/channel not found", details: nil))
            return
        }
        sampler.sendController(UInt8(controller), withValue: UInt8(value), onChannel: UInt8(channel))
        result(nil)
    case "pitchBend":
        let args = call.arguments as! [String: Any]
        let sfId = args["sfId"] as! Int
        let channel = args["channel"] as! Int
        let value = args["value"] as! Int
        guard let sampler = soundfontSamplers[sfId]?[channel] else {
            result(FlutterError(code: "SOUND_FONT_NOT_FOUND", message: "Soundfont/channel not found", details: nil))
            return
        }
        sampler.sendPitchBend(UInt16(value), onChannel: UInt8(channel))
        result(nil)
    case "unloadSoundfont":
        let args = call.arguments as! [String:Any]
        let sfId = args["sfId"] as! Int
        guard let samplers = soundfontSamplers[sfId] else {
            result(FlutterError(code: "SOUND_FONT_NOT_FOUND", message: "Soundfont not found", details: nil))
            return
        }
        samplers.forEach { (sampler) in
            audioEngine.detach(sampler)
            samplerToBus.removeValue(forKey: sampler)
        }
        soundfontSamplers.removeValue(forKey: sfId)
        soundfontURLs.removeValue(forKey: sfId)
        result(nil)
    case "dispose":
        soundfontSamplers.values.forEach { samplers in
            samplers.forEach { sampler in
                audioEngine.detach(sampler)
                samplerToBus.removeValue(forKey: sampler)
            }
        }
        audioEngine.stop()
        soundfontSamplers = [:]
        soundfontURLs = [:]
        samplerToBus = [:]
        nextBus = 0
        result(nil)
    default:
      result(FlutterMethodNotImplemented)
        break
    }
  }
}
