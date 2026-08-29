import CoreAudio
import SwiftUI

struct MenuView: View {
    @EnvironmentObject var controller: SwitchController

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            rateDisplay
            deviceSection
            if !controller.history.isEmpty {
                historySection
            }
            footer
        }
        .padding(14)
        .frame(width: 320)
    }

    // MARK: Header

    private var header: some View {
        HStack {
            Label {
                Text("TrueRate").font(.headline)
            } icon: {
                Image(systemName: "waveform.badge.magnifyingglass")
                    .foregroundStyle(.tint)
            }
            Spacer()
            HStack(spacing: 5) {
                Circle()
                    .fill(controller.isListening ? Color.green : Color.red)
                    .frame(width: 7, height: 7)
                Text(controller.isListening ? "Listening" : "Log stream offline")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: Big rate display

    private var rateDisplay: some View {
        HStack(spacing: 0) {
            rateColumn(
                title: "Apple Music",
                rate: controller.detectedRate,
                subtitle: sourceSubtitle
            )
            Image(systemName: controller.isMatched ? "checkmark.circle.fill" : "arrow.right")
                .font(.title3)
                .foregroundStyle(controller.isMatched ? Color.green : Color.orange)
                .frame(width: 36)
            rateColumn(
                title: "Device",
                rate: controller.deviceRate,
                subtitle: controller.activeDeviceName
            )
        }
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.primary.opacity(0.05))
        )
        .overlay(alignment: .bottom) {
            if let track = controller.trackName {
                Text(
                    controller.trackArtist.map { "\(track) — \($0)" } ?? track
                )
                .font(.caption2)
                .lineLimit(1)
                .foregroundStyle(.secondary)
                .padding(.bottom, 4)
                .padding(.horizontal, 8)
            }
        }
    }

    private var sourceSubtitle: String {
        var parts: [String] = []
        if let bits = controller.detectedBits { parts.append("\(bits)-bit") }
        if let codec = controller.detectedCodec {
            parts.append(codec == "alac" || codec == "qlac" ? "Lossless" : codec.uppercased())
        }
        return parts.isEmpty ? "Waiting for playback…" : parts.joined(separator: " · ")
    }

    private func rateColumn(title: String, rate: Double?, subtitle: String) -> some View {
        VStack(spacing: 2) {
            Text(title.uppercased())
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.tertiary)
            Text(rate.map(SwitchController.format(rate:)) ?? "—")
                .font(.system(size: 20, weight: .semibold, design: .rounded))
                .monospacedDigit()
            Text(subtitle)
                .font(.caption2)
                .lineLimit(1)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.bottom, controller.trackName == nil ? 0 : 12)
    }

    // MARK: Device + settings

    private var deviceSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle(isOn: $controller.autoSwitch) {
                Text("Auto-switch sample rate")
            }
            .toggleStyle(.switch)
            .controlSize(.small)

            Picker("Output device", selection: pinnedSelection) {
                Text("System default").tag(AudioDeviceID(0))
                ForEach(controller.devices) { device in
                    Text(device.name).tag(device.id)
                }
            }
            .font(.callout)

            if !controller.supportedRates.isEmpty {
                Text(
                    "Supports: "
                        + controller.supportedRates
                            .map(SwitchController.shortFormat(rate:))
                            .joined(separator: " · ") + " kHz"
                )
                .font(.caption2)
                .foregroundStyle(.tertiary)
            }
        }
    }

    private var pinnedSelection: Binding<AudioDeviceID> {
        Binding(
            get: { controller.pinnedDeviceUID ?? 0 },
            set: { controller.pinnedDeviceUID = $0 == 0 ? nil : $0 }
        )
    }

    // MARK: History

    private var historySection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("RECENT SWITCHES")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.tertiary)
            ForEach(controller.history) { event in
                HStack(spacing: 6) {
                    Image(
                        systemName: event.switched
                            ? "arrow.triangle.2.circlepath" : "exclamationmark.triangle"
                    )
                    .font(.caption2)
                    .foregroundStyle(event.switched ? Color.accentColor : Color.orange)
                    Text(event.track ?? "Unknown track")
                        .font(.caption)
                        .lineLimit(1)
                    Spacer()
                    Text(SwitchController.format(rate: event.deviceRate))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                    Text(event.date, style: .time)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        }
    }

    // MARK: Footer

    private var footer: some View {
        HStack {
            Toggle("Launch at login", isOn: $controller.launchAtLogin)
                .toggleStyle(.checkbox)
                .controlSize(.small)
                .font(.caption)
            Spacer()
            Button("Quit") { NSApp.terminate(nil) }
                .controlSize(.small)
        }
    }
}
