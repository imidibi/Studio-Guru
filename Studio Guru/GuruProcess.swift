//
//  GuruProcess.swift
//  Studio Guru
//
//  Created by Ian Miller on 2/16/26.   
//  Guru module UI + starter presets
//

import SwiftUI

// MARK: - Guru Module (v1)

private enum GuruProcess: String, CaseIterable, Identifiable {
    case compressor = "Compressor"
    case equalizer = "Equalizer"
    case reverb = "Reverb"
    case delay = "Delay"

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .compressor: return "waveform"
        case .equalizer: return "slider.horizontal.3"
        case .reverb: return "drop"
        case .delay: return "timer"
        }
    }
}

private enum GuruSource: String, CaseIterable, Identifiable {
    case vocalLead = "Vocal (Lead)"
    case bass = "Bass"
    case kick = "Kick"
    case snare = "Snare"
    case piano = "Piano"
    case drumBus = "Drum Bus"
    case mixBus = "Mix Bus"

    var id: String { rawValue }
}

// NOTE: must be NON-private because StudioCanvasView presents it in a sheet.
struct GuruHomeView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    @State private var selectedSource: GuruSource = .vocalLead
    @State private var selectedProcess: GuruProcess = .compressor

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Compact processor selector at top
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(GuruProcess.allCases) { p in
                            Button {
                                selectedProcess = p
                            } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: p.symbol)
                                    Text(p.rawValue)
                                        .fontWeight(selectedProcess == p ? .semibold : .regular)
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 10)
                                .background(
                                    selectedProcess == p ? 
                                        Color.accentColor : 
                                        Color.secondary.opacity(0.15)
                                )
                                .foregroundStyle(
                                    selectedProcess == p ? 
                                        Color.white : 
                                        Color.primary
                                )
                                .cornerRadius(8)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                }
                #if os(iOS)
                .background(Color(UIColor.systemGroupedBackground))
                #else
                .background(Color(NSColor.controlBackgroundColor))
                #endif
                
                Divider()
                
                // Main content area
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        // Source selector
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Source")
                                .font(.headline)
                                .foregroundStyle(.secondary)
                            
                            Picker("Source", selection: $selectedSource) {
                                ForEach(GuruSource.allCases) { s in
                                    Text(s.rawValue).tag(s)
                                }
                            }
                            .pickerStyle(.segmented)
                        }
                        
                        // Plugin settings
                        GuruPluginPanel(source: selectedSource, process: selectedProcess)
                    }
                    .padding(20)
                }
            }
            .navigationTitle("Guru")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }
}

private struct GuruPluginPanel: View {
    let source: GuruSource
    let process: GuruProcess

    var body: some View {
        Group {
            switch process {
            case .compressor:
                CompressorPluginView(source: source)
            case .equalizer:
                EQPluginView(source: source)
            case .reverb:
                ReverbPluginView(source: source)
            case .delay:
                DelayPluginView(source: source)
            }
        }
    }
}

private struct CompressorPreset {
    var ratio: Double
    var attackMs: Double
    var releaseMs: Double
    var knee: Double
    var grDb: Double

    static func forSource(_ s: GuruSource) -> CompressorPreset {
        switch s {
        case .vocalLead:
            return .init(ratio: 3.5, attackMs: 20, releaseMs: 90, knee: 0.2, grDb: 5)
        case .bass:
            return .init(ratio: 4.0, attackMs: 30, releaseMs: 120, knee: 0.35, grDb: 6)
        case .kick:
            return .init(ratio: 5.0, attackMs: 30, releaseMs: 80, knee: 0.5, grDb: 5)
        case .snare:
            return .init(ratio: 5.0, attackMs: 18, releaseMs: 90, knee: 0.5, grDb: 6)
        case .piano:
            return .init(ratio: 2.5, attackMs: 40, releaseMs: 160, knee: 0.25, grDb: 3)
        case .drumBus:
            return .init(ratio: 3.0, attackMs: 30, releaseMs: 100, knee: 0.35, grDb: 3)
        case .mixBus:
            return .init(ratio: 2.0, attackMs: 30, releaseMs: 120, knee: 0.3, grDb: 1.5)
        }
    }
}

private struct CompressorPluginView: View {
    let source: GuruSource
    private var preset: CompressorPreset { .forSource(source) }
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HeaderRow(title: "Compressor", source: source.rawValue)

            ControlsPanel {
                HStack(spacing: horizontalSizeClass == .compact ? 8 : 14) {
                    GuruKnob(title: "Ratio", value01: ratio01(preset.ratio), valueText: String(format: "%.1f:1", preset.ratio))
                    GuruKnob(title: "Attack", value01: log01(preset.attackMs, min: 0.1, max: 100), valueText: "\(Int(preset.attackMs)) ms")
                    GuruKnob(title: "Release", value01: log01(preset.releaseMs, min: 10, max: 500), valueText: "\(Int(preset.releaseMs)) ms")
                    GuruKnob(title: "Knee", value01: preset.knee, valueText: preset.knee < 0.33 ? "Soft" : (preset.knee < 0.66 ? "Med" : "Hard"))
                    GuruKnob(title: "GR", value01: clamp01(preset.grDb / 12.0), valueText: String(format: "%.1f dB", preset.grDb))
                }
            }

            StartingPointPanel(text: startingPointNote(for: source))
        }
    }

    private func startingPointNote(for s: GuruSource) -> String {
        switch s {
        case .vocalLead:
            return "Aim for 3–6 dB gain reduction on peaks; adjust threshold to taste. Slightly slower attack keeps articulation intact."
        case .bass:
            return "Target 4–8 dB gain reduction for even sustain. If transients feel dull, slow the attack a touch."
        case .kick:
            return "Keep attack slow enough to preserve punch. Shorter release tightens the low end."
        case .snare:
            return "Shorter release increases snap; longer release smooths. Keep an eye on pumping."
        case .piano:
            return "Use light control (2–4 dB). Longer attack keeps dynamics natural."
        case .drumBus:
            return "Glue rather than slam: 2–4 dB is usually enough."
        case .mixBus:
            return "Very subtle: 1–2 dB gain reduction. If the mix narrows, back off."
        }
    }

    private func clamp01(_ v: Double) -> Double { min(max(v, 0), 1) }

    private func ratio01(_ ratio: Double) -> Double {
        clamp01((ratio - 1.0) / 9.0)
    }

    private func log01(_ value: Double, min minValue: Double, max maxValue: Double) -> Double {
        let v = Swift.max(minValue, Swift.min(value, maxValue))
        let a = log(minValue)
        let b = log(maxValue)
        let x = log(v)
        return clamp01((x - a) / (b - a))
    }
}

// MARK: - Shared Layout Helpers

private struct HeaderRow: View {
    let title: String
    let source: String

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.title2)
                .bold()
            Spacer()
            Text(source)
                .foregroundStyle(.secondary)
        }
    }
}

private struct ControlsPanel<Content: View>: View {
    @ViewBuilder var content: () -> Content
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    var body: some View {
        RoundedRectangle(cornerRadius: 16)
            .fill(.ultraThickMaterial)
            .overlay(
                VStack(alignment: .leading, spacing: 12) {
                    content()
                }
                .padding(horizontalSizeClass == .compact ? 12 : 14)
            )
            // Fixed height so knobs never jump - smaller on compact devices
            .frame(height: horizontalSizeClass == .compact ? 280 : 320)
    }
}

private struct StartingPointPanel: View {
    let text: String

    var body: some View {
        GroupBox("Starting point") {
            ScrollView {
                Text(text)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 6)
            }
            .frame(minHeight: 90, idealHeight: 120, maxHeight: 160)
        }
    }
}

// MARK: - Equalizer

private struct EQPreset {
    var hpfOn: Bool
    var hpfHz: Double
    var lowShelfDb: Double
    var mudCutDb: Double
    var presenceDb: Double
    var airDb: Double

    static func forSource(_ s: GuruSource) -> EQPreset {
        switch s {
        case .vocalLead:
            return .init(hpfOn: true, hpfHz: 90, lowShelfDb: 0, mudCutDb: -2, presenceDb: 2.5, airDb: 2)
        case .bass:
            return .init(hpfOn: true, hpfHz: 35, lowShelfDb: 1.5, mudCutDb: -1, presenceDb: 0.5, airDb: 0)
        case .kick:
            return .init(hpfOn: false, hpfHz: 25, lowShelfDb: 2, mudCutDb: -2, presenceDb: 1, airDb: 0)
        case .snare:
            return .init(hpfOn: true, hpfHz: 80, lowShelfDb: 0, mudCutDb: -2, presenceDb: 2, airDb: 1)
        case .piano:
            return .init(hpfOn: true, hpfHz: 60, lowShelfDb: 0, mudCutDb: -1, presenceDb: 1, airDb: 1.5)
        case .drumBus:
            return .init(hpfOn: true, hpfHz: 30, lowShelfDb: 0.5, mudCutDb: -1, presenceDb: 0.5, airDb: 0.5)
        case .mixBus:
            return .init(hpfOn: false, hpfHz: 25, lowShelfDb: 0, mudCutDb: 0, presenceDb: 0.5, airDb: 0.5)
        }
    }
}

private struct EQPluginView: View {
    let source: GuruSource
    private var preset: EQPreset { .forSource(source) }
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HeaderRow(title: "Equalizer", source: source.rawValue)

            ControlsPanel {
                HStack(spacing: 12) {
                    Toggle("HPF", isOn: .constant(preset.hpfOn))
                        .toggleStyle(.switch)
                    Text("HPF Freq")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                }

                HStack(spacing: horizontalSizeClass == .compact ? 8 : 14) {
                    GuruKnob(title: "HPF", value01: hz01(preset.hpfHz, min: 20, max: 250), valueText: "\(Int(preset.hpfHz)) Hz")
                    GuruKnob(title: "Low", value01: db01(preset.lowShelfDb, min: -6, max: 6), valueText: fmtDb(preset.lowShelfDb))
                    GuruKnob(title: "Mud", value01: db01(preset.mudCutDb, min: -6, max: 6), valueText: fmtDb(preset.mudCutDb))
                    GuruKnob(title: "Presence", value01: db01(preset.presenceDb, min: -6, max: 6), valueText: fmtDb(preset.presenceDb))
                    GuruKnob(title: "Air", value01: db01(preset.airDb, min: -6, max: 6), valueText: fmtDb(preset.airDb))
                }
            }

            StartingPointPanel(text: eqNote(for: source))
        }
    }

    private func eqNote(for s: GuruSource) -> String {
        switch s {
        case .vocalLead:
            return "Start with a gentle high‑pass (around 80–120 Hz) to clear rumble. Cut a little ‘mud’ (200–400 Hz) if needed, then add presence (3–5 kHz) and a touch of air (10–14 kHz)."
        case .bass:
            return "HPF only if needed to remove sub‑rumble. Add a little low shelf for weight, and keep top-end boosts minimal."
        case .kick:
            return "Be cautious with HPF. A small low shelf can add thump; a small presence lift can add click."
        case .snare:
            return "HPF to remove lows, trim boxiness (300–600 Hz), then add crack (2–5 kHz) and a hint of air if desired."
        case .piano:
            return "HPF to clear low buildup. Small presence/air boosts can help it sit without getting harsh."
        case .drumBus:
            return "Very gentle moves. Small low shelf + tiny air can add polish."
        case .mixBus:
            return "If you EQ the mix bus, keep it subtle (±0.5 to 1 dB)."
        }
    }

    private func clamp01(_ v: Double) -> Double { min(max(v, 0), 1) }

    private func hz01(_ hz: Double, min minHz: Double, max maxHz: Double) -> Double {
        let v = Swift.max(minHz, Swift.min(hz, maxHz))
        let a = log(minHz)
        let b = log(maxHz)
        let x = log(v)
        return clamp01((x - a) / (b - a))
    }

    private func db01(_ db: Double, min minDb: Double, max maxDb: Double) -> Double {
        let v = Swift.max(minDb, Swift.min(db, maxDb))
        return clamp01((v - minDb) / (maxDb - minDb))
    }

    private func fmtDb(_ v: Double) -> String {
        if v > 0 { return String(format: "+%.1f dB", v) }
        if v < 0 { return String(format: "%.1f dB", v) }
        return "0 dB"
    }
}

// MARK: - Reverb

private enum ReverbType: String, CaseIterable, Identifiable {
    case plate = "Plate"
    case hall = "Hall"
    case room = "Room"
    case chamber = "Chamber"
    case spring = "Spring"

    var id: String { rawValue }
}

private struct ReverbPreset {
    var type: ReverbType
    var mixPct: Double
    var decayS: Double
    var preDelayMs: Double
    var hpfHz: Double
    var lpfHz: Double

    static func forSource(_ s: GuruSource) -> ReverbPreset {
        switch s {
        case .vocalLead:
            return .init(type: .plate, mixPct: 14, decayS: 1.8, preDelayMs: 22, hpfHz: 140, lpfHz: 9000)
        case .bass:
            return .init(type: .room, mixPct: 6, decayS: 0.9, preDelayMs: 8, hpfHz: 200, lpfHz: 6000)
        case .kick:
            return .init(type: .room, mixPct: 5, decayS: 0.7, preDelayMs: 6, hpfHz: 250, lpfHz: 5000)
        case .snare:
            return .init(type: .plate, mixPct: 10, decayS: 1.3, preDelayMs: 12, hpfHz: 180, lpfHz: 8000)
        case .piano:
            return .init(type: .hall, mixPct: 12, decayS: 2.2, preDelayMs: 18, hpfHz: 120, lpfHz: 10000)
        case .drumBus:
            return .init(type: .room, mixPct: 8, decayS: 1.0, preDelayMs: 10, hpfHz: 200, lpfHz: 7000)
        case .mixBus:
            return .init(type: .room, mixPct: 6, decayS: 1.1, preDelayMs: 10, hpfHz: 200, lpfHz: 8000)
        }
    }
}

private struct ReverbPluginView: View {
    let source: GuruSource
    @State private var type: ReverbType = .plate
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    private var preset: ReverbPreset { .forSource(source) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HeaderRow(title: "Reverb", source: source.rawValue)

            ControlsPanel {
                HStack {
                    Text("Type")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Picker("Type", selection: $type) {
                        ForEach(ReverbType.allCases) { t in
                            Text(t.rawValue).tag(t)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                HStack(spacing: horizontalSizeClass == .compact ? 8 : 14) {
                    GuruKnob(title: "Mix", value01: clamp01(preset.mixPct / 40.0), valueText: "\(Int(preset.mixPct))%")
                    GuruKnob(title: "Decay", value01: clamp01((preset.decayS - 0.3) / 4.7), valueText: String(format: "%.1f s", preset.decayS))
                    GuruKnob(title: "PreDelay", value01: log01(preset.preDelayMs, min: 0.0 + 1.0, max: 120), valueText: "\(Int(preset.preDelayMs)) ms")
                    GuruKnob(title: "HPF", value01: hz01(preset.hpfHz, min: 20, max: 400), valueText: "\(Int(preset.hpfHz)) Hz")
                    GuruKnob(title: "LPF", value01: hz01(preset.lpfHz, min: 2000, max: 18000), valueText: "\(Int(preset.lpfHz)) Hz")
                }
            }

            StartingPointPanel(text: reverbNote(for: source))
        }
        .onAppear { type = preset.type }
        .onChange(of: source) { _, _ in
            type = preset.type
        }
    }

    private func reverbNote(for s: GuruSource) -> String {
        switch s {
        case .vocalLead:
            return "Plate is a solid starting point: keep the mix modest, add a little pre‑delay for clarity, and roll off lows/highs so the verb doesn’t cloud the vocal."
        case .snare:
            return "Plate or chamber often works: keep the decay controlled and filter the return so it stays punchy."
        case .piano:
            return "Hall can add size: watch buildup in the low mids and keep the mix lower than you think."
        default:
            return "Start with a room for cohesion. Filter the return and keep the mix conservative so you don’t wash out the source."
        }
    }

    private func clamp01(_ v: Double) -> Double { min(max(v, 0), 1) }

    private func log01(_ value: Double, min minValue: Double, max maxValue: Double) -> Double {
        let v = Swift.max(minValue, Swift.min(value, maxValue))
        let a = log(minValue)
        let b = log(maxValue)
        let x = log(v)
        return clamp01((x - a) / (b - a))
    }

    private func hz01(_ hz: Double, min minHz: Double, max maxHz: Double) -> Double {
        let v = Swift.max(minHz, Swift.min(hz, maxHz))
        let a = log(minHz)
        let b = log(maxHz)
        let x = log(v)
        return clamp01((x - a) / (b - a))
    }
}

// MARK: - Delay

private enum DelayMode: String, CaseIterable, Identifiable {
    case slap = "Slap"
    case eighth = "1/8"
    case quarter = "1/4"
    case dottedEighth = "Dotted 1/8"
    case pingPong = "Ping‑Pong"

    var id: String { rawValue }
}

private struct DelayPreset {
    var mode: DelayMode
    var timeMs: Double
    var feedbackPct: Double
    var mixPct: Double
    var hpfHz: Double
    var lpfHz: Double

    static func forSource(_ s: GuruSource) -> DelayPreset {
        switch s {
        case .vocalLead:
            return .init(mode: .dottedEighth, timeMs: 320, feedbackPct: 28, mixPct: 10, hpfHz: 160, lpfHz: 8000)
        case .snare:
            return .init(mode: .slap, timeMs: 90, feedbackPct: 18, mixPct: 8, hpfHz: 220, lpfHz: 6000)
        case .piano:
            return .init(mode: .quarter, timeMs: 420, feedbackPct: 22, mixPct: 10, hpfHz: 140, lpfHz: 9000)
        default:
            return .init(mode: .eighth, timeMs: 250, feedbackPct: 20, mixPct: 8, hpfHz: 180, lpfHz: 7500)
        }
    }
}

private struct DelayPluginView: View {
    let source: GuruSource

    @State private var mode: DelayMode = .eighth
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    private var preset: DelayPreset { .forSource(source) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HeaderRow(title: "Delay", source: source.rawValue)

            ControlsPanel {
                HStack {
                    Text("Time")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Picker("Mode", selection: $mode) {
                        ForEach(DelayMode.allCases) { m in
                            Text(m.rawValue).tag(m)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                HStack(spacing: horizontalSizeClass == .compact ? 8 : 14) {
                    GuruKnob(title: "Time", value01: log01(preset.timeMs, min: 40, max: 900), valueText: "\(Int(preset.timeMs)) ms")
                    GuruKnob(title: "Feedback", value01: clamp01(preset.feedbackPct / 95.0), valueText: "\(Int(preset.feedbackPct))%")
                    GuruKnob(title: "Mix", value01: clamp01(preset.mixPct / 50.0), valueText: "\(Int(preset.mixPct))%")
                    GuruKnob(title: "HPF", value01: hz01(preset.hpfHz, min: 20, max: 500), valueText: "\(Int(preset.hpfHz)) Hz")
                    GuruKnob(title: "LPF", value01: hz01(preset.lpfHz, min: 2000, max: 18000), valueText: "\(Int(preset.lpfHz)) Hz")
                }
            }

            StartingPointPanel(text: delayNote(for: source))
        }
        .onAppear { mode = preset.mode }
        .onChange(of: source) { _, _ in
            mode = preset.mode
        }
    }

    private func delayNote(for s: GuruSource) -> String {
        switch s {
        case .vocalLead:
            return "A dotted‑eighth or quarter delay is a classic starting point. Filter the repeats, keep the mix low, and let feedback set the ‘tail’ length."
        case .snare:
            return "Slap or short timed delays add depth without washing out the transient."
        default:
            return "Start subtle. Filter the repeats and keep feedback moderate so the delay supports rather than distracts."
        }
    }

    private func clamp01(_ v: Double) -> Double { min(max(v, 0), 1) }

    private func log01(_ value: Double, min minValue: Double, max maxValue: Double) -> Double {
        let v = Swift.max(minValue, Swift.min(value, maxValue))
        let a = log(minValue)
        let b = log(maxValue)
        let x = log(v)
        return clamp01((x - a) / (b - a))
    }

    private func hz01(_ hz: Double, min minHz: Double, max maxHz: Double) -> Double {
        let v = Swift.max(minHz, Swift.min(hz, maxHz))
        let a = log(minHz)
        let b = log(maxHz)
        let x = log(v)
        return clamp01((x - a) / (b - a))
    }
}

private struct GuruKnob: View {
    let title: String
    let value01: Double
    let valueText: String

    private var angle: Double {
        (-135.0) + (270.0 * min(max(value01, 0), 1))
    }

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                Circle().fill(.thinMaterial)
                Circle().strokeBorder(.secondary.opacity(0.25), lineWidth: 6)

                Circle()
                    .trim(from: 0.0, to: CGFloat(min(max(value01, 0), 1)))
                    .stroke(style: StrokeStyle(lineWidth: 6, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .foregroundStyle(.primary)

                Rectangle()
                    .fill(.primary)
                    .frame(width: 2, height: 18)
                    .offset(y: -18)
                    .rotationEffect(.degrees(angle))
            }
            .frame(width: 74, height: 74)

            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)

            Text(valueText)
                .font(.caption2)
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
        .frame(width: 92)
    }
}
