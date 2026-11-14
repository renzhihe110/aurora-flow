import SwiftUI

/// 设置面板只在点击菜单栏图标后出现，与全屏 Overlay 完全独立。
struct MenuContentView: View {
    @ObservedObject var controller: AuroraController

    var body: some View {
        VStack(alignment: .leading, spacing: 17) {
            HStack(spacing: 10) {
                Image(systemName: "sparkles")
                    .font(.system(size: 24, weight: .medium))
                    .foregroundStyle(LinearGradient(colors: [.cyan, .purple], startPoint: .topLeading, endPoint: .bottomTrailing))
                VStack(alignment: .leading, spacing: 3) {
                    Text("Aurora Flow").font(.system(size: 18, weight: .semibold))
                    Text("让任务状态，安静流过屏幕边缘").font(.system(size: 11)).foregroundStyle(.secondary)
                }
                Spacer()
                Text(controller.state.rawValue)
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(stateColor.opacity(0.12), in: Capsule())
                    .foregroundStyle(stateColor)
            }
            Divider()
            HStack(spacing: 8) {
                actionButton("Start", icon: "play.fill", color: .cyan, action: AuroraBorder.start)
                actionButton("Stop", icon: "stop.fill", color: .secondary, action: AuroraBorder.stop)
            }
            HStack(spacing: 8) {
                actionButton("Success", icon: "checkmark", color: .mint, action: AuroraBorder.success)
                actionButton("Error", icon: "exclamationmark", color: .orange, action: AuroraBorder.error)
                actionButton("Cancel", icon: "xmark", color: .secondary, action: AuroraBorder.cancel)
            }
            Divider()
            settingSlider("光晕亮度", value: binding(\.brightness), range: 0...1, valueText: "\(Int(controller.config.brightness * 100))%")
            settingSlider("核心光线", value: binding(\.borderWidth), range: 1...8, valueText: String(format: "%.1f px", controller.config.borderWidth))
            settingSlider("流动周期", value: binding(\.animationDuration), range: 2...30, valueText: String(format: "%.1f s", controller.config.animationDuration))
            Toggle("顺时针流动", isOn: Binding(get: { controller.config.clockwise }, set: { value in
                var config = controller.config
                config.clockwise = value
                controller.update(config: config)
            }))
            .font(.system(size: 12))
            .toggleStyle(.switch)
            Divider()
            Picker("显示器", selection: displayBinding) {
                Text("所有显示器").tag("all")
                Text("系统主显示器").tag("primary")
                ForEach(controller.displays) { display in
                    Text("\(display.name) · \(Int(display.frame.width * display.scale))×\(Int(display.frame.height * display.scale))").tag(display.id)
                }
                if case .screen(let id) = controller.config.displayMode, !controller.displays.contains(where: { $0.id == id }) {
                    Text("已断开，等待重连").tag(id)
                }
            }
            .font(.system(size: 12))
            Text("透明 · 鼠标穿透 · 不抢焦点\n光线尺寸采用物理像素，设置即时生效。")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .lineSpacing(3)
            if let error = controller.lastError {
                Text(error).font(.system(size: 11)).foregroundStyle(.red).textSelection(.enabled)
            }
            HStack {
                Text("Metal / Native macOS").font(.system(size: 10, design: .monospaced)).foregroundStyle(.tertiary)
                Spacer()
                Button("Quit") {
                    NSApp.terminate(nil)
                }
                .buttonStyle(.plain)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            }
        }
        .padding(20)
        .frame(width: 370)
    }

    private var stateColor: Color {
        switch controller.state {
        case .running:
            return .cyan
        case .success:
            return .mint
        case .error:
            return .orange
        case .idle, .cancelled, .stopping:
            return .secondary
        }
    }

    private var displayBinding: Binding<String> {
        return Binding(get: {
            switch controller.config.displayMode {
            case .allScreens:
                return "all"
            case .primaryScreen:
                return "primary"
            case .screen(let id):
                return id
            }
        }, set: { value in
            var config = controller.config
            if value == "all" {
                config.displayMode = .allScreens
            } else if value == "primary" {
                config.displayMode = .primaryScreen
            } else {
                config.displayMode = .screen(value)
            }
            controller.update(config: config)
        })
    }

    private func binding(_ keyPath: WritableKeyPath<AuroraConfig, Double>) -> Binding<Double> {
        return Binding(get: { controller.config[keyPath: keyPath] }, set: { value in
            var config = controller.config
            config[keyPath: keyPath] = value
            controller.update(config: config)
        })
    }

    private func settingSlider(_ title: String, value: Binding<Double>, range: ClosedRange<Double>, valueText: String) -> some View {
        return VStack(spacing: 5) {
            HStack {
                Text(title).font(.system(size: 12))
                Spacer()
                Text(valueText).font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary)
            }
            Slider(value: value, in: range)
                .controlSize(.small)
                .tint(.cyan)
                .accessibilityLabel(title)
        }
    }

    private func actionButton(_ title: String, icon: String, color: Color, action: @escaping () -> Void) -> some View {
        return Button(action: action) {
            Label(title, systemImage: icon)
                .font(.system(size: 12, weight: .medium))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 7)
                .foregroundStyle(color)
                .background(color.opacity(0.09), in: RoundedRectangle(cornerRadius: 7))
        }
        .buttonStyle(.plain)
    }
}
