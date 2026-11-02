import Flutter
import SwiftUI
import UIKit

/// Capability probing exists on every supported iOS version. The platform view
/// is registered only where native Liquid Glass is available.
final class HomeCaptureControlsRegistration {
    static func register(with registry: FlutterPluginRegistry, messenger: FlutterBinaryMessenger) {
        RecordingDetailSheetRegistration.register(messenger: messenger)
        let channel = FlutterMethodChannel(name: "com.omi/home_capture_controls", binaryMessenger: messenger)
        channel.setMethodCallHandler { call, reply in
            guard call.method == "isSupported" else { reply(FlutterMethodNotImplemented); return }
            #if compiler(>=6.2)
            if #available(iOS 26.0, *) { reply(true); return }
            #endif
            reply(false)
        }
        #if compiler(>=6.2)
        if #available(iOS 26.0, *), let registrar = registry.registrar(forPlugin: "HomeCaptureControls") {
            registrar.register(HomeCaptureControlsFactory(messenger: messenger), withId: "omi/home_capture_controls")
            registrar.register(HomeHeaderGlassFactory(messenger: messenger), withId: "omi/home_header_glass")
        }
        #endif
    }
}

#if compiler(>=6.2)
@available(iOS 26.0, *)
private final class HomeCaptureControlsFactory: NSObject, FlutterPlatformViewFactory {
    let messenger: FlutterBinaryMessenger
    init(messenger: FlutterBinaryMessenger) { self.messenger = messenger }
    func createArgsCodec() -> FlutterMessageCodec & NSObjectProtocol { FlutterStandardMessageCodec.sharedInstance() }
    func create(withFrame frame: CGRect, viewIdentifier viewId: Int64, arguments args: Any?) -> FlutterPlatformView {
        HomeCapturePlatformView(frame: frame, id: viewId, messenger: messenger, state: args as? [String: Any] ?? [:])
    }
}

@available(iOS 26.0, *)
private final class HomeCapturePlatformView: NSObject, FlutterPlatformView {
    let channel: FlutterMethodChannel
    let container: HomeGlassContainer<HomeCaptureControls>

    init(frame: CGRect, id: Int64, messenger: FlutterBinaryMessenger, state: [String: Any]) {
        channel = FlutterMethodChannel(name: "com.omi/home_capture_controls/\(id)", binaryMessenger: messenger)
        let model = HomeCaptureModel(state: state)
        container = HomeGlassContainer(frame: frame, root: HomeCaptureControls(model: model))
        super.init()
        model.send = { [weak self] method, args, completion in
            self?.channel.invokeMethod(method, arguments: args, result: completion)
        }
        channel.setMethodCallHandler { [weak model, weak container] call, reply in
            if call.method == "snapshot" {
                reply(container?.snapshotPixels())
                return
            }
            guard call.method == "update", let state = call.arguments as? [String: Any] else {
                reply(FlutterMethodNotImplemented); return
            }
            model?.state = state
            if let model { model.send?("height", ["height": model.height, "recordButtonExtent": model.recordButtonExtent], nil) }
            reply(nil)
        }
    }

    func view() -> UIView { container }
    deinit { channel.setMethodCallHandler(nil) }
}

/// Proper view-controller containment gives SwiftUI native accessibility,
/// Dynamic Type and trait updates when Flutter attaches/detaches the view.
@available(iOS 26.0, *)
private final class HomeGlassContainer<Content: View>: UIView {
    let host: UIHostingController<Content>
    let passthrough: Bool
    init(frame: CGRect, root: Content, passthrough: Bool = false) {
        self.passthrough = passthrough
        host = UIHostingController(rootView: root)
        super.init(frame: frame)
        backgroundColor = .clear
        host.view.backgroundColor = .clear
        host.view.translatesAutoresizingMaskIntoConstraints = false
        addSubview(host.view)
        NSLayoutConstraint.activate([
            host.view.leadingAnchor.constraint(equalTo: leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: trailingAnchor),
            host.view.topAnchor.constraint(equalTo: topAnchor),
            host.view.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        !passthrough && super.point(inside: point, with: event)
    }
    func snapshotPixels() -> FlutterStandardTypedData? {
        guard bounds.width > 0, bounds.height > 0, let window else { return nil }
        layoutIfNeeded()
        let format = UIGraphicsImageRendererFormat()
        format.opaque = true
        format.scale = window.screen.scale
        // Visual effects require the complete window; return only this group's pixels.
        let image = UIGraphicsImageRenderer(bounds: window.bounds, format: format).image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: false)
        }
        let region = convert(bounds, to: window)
        let pixels = CGRect(x: region.minX * format.scale, y: region.minY * format.scale,
                            width: region.width * format.scale, height: region.height * format.scale)
        guard let cropped = image.cgImage?.cropping(to: pixels.integral),
              let png = UIImage(cgImage: cropped, scale: format.scale, orientation: .up).pngData() else { return nil }
        return FlutterStandardTypedData(bytes: png)
    }
    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window == nil {
            host.willMove(toParent: nil)
            host.removeFromParent()
        } else if host.parent == nil {
            var responder: UIResponder? = next
            while let current = responder {
                if let parent = current as? UIViewController {
                    parent.addChild(host)
                    host.didMove(toParent: parent)
                    break
                }
                responder = current.next
            }
        }
    }
}

@available(iOS 26.0, *)
private final class HomeHeaderGlassFactory: NSObject, FlutterPlatformViewFactory {
    let messenger: FlutterBinaryMessenger
    init(messenger: FlutterBinaryMessenger) { self.messenger = messenger }
    func createArgsCodec() -> FlutterMessageCodec & NSObjectProtocol { FlutterStandardMessageCodec.sharedInstance() }
    func create(withFrame frame: CGRect, viewIdentifier viewId: Int64, arguments args: Any?) -> FlutterPlatformView {
        HomeHeaderGlassPlatformView(frame: frame, id: viewId, messenger: messenger, state: args as? [String: Any] ?? [:])
    }
}

@available(iOS 26.0, *)
private final class HomeHeaderGlassPlatformView: NSObject, FlutterPlatformView {
    let channel: FlutterMethodChannel
    let container: HomeGlassContainer<HomeHeaderGlassControls>
    init(frame: CGRect, id: Int64, messenger: FlutterBinaryMessenger, state: [String: Any]) {
        channel = FlutterMethodChannel(name: "com.omi/home_header_glass/\(id)", binaryMessenger: messenger)
        let model = HomeHeaderGlassModel(state: state)
        container = HomeGlassContainer(frame: frame, root: HomeHeaderGlassControls(model: model), passthrough: true)
        super.init()
        container.accessibilityElementsHidden = true
        channel.setMethodCallHandler { [weak model, weak container] call, reply in
            if call.method == "snapshot" { reply(container?.snapshotPixels()); return }
            guard call.method == "update", let state = call.arguments as? [String: Any] else {
                reply(FlutterMethodNotImplemented); return
            }
            model?.state = state
            reply(nil)
        }
    }
    func view() -> UIView { container }
    deinit { channel.setMethodCallHandler(nil) }
}

@available(iOS 26.0, *)
private final class HomeHeaderGlassModel: ObservableObject {
    @Published var state: [String: Any]
    init(state: [String: Any]) { self.state = state }
    var dark: Bool { state["dark"] as? Bool == true }
    var shapes: [HomeHeaderGlassShape] {
        (state["rects"] as? [[String: Any]] ?? []).compactMap { value in
            guard let id = value["id"] as? String,
                  let x = value["x"] as? Double, let y = value["y"] as? Double,
                  let width = value["width"] as? Double, let height = value["height"] as? Double,
                  x.isFinite, y.isFinite, width.isFinite, height.isFinite, width > 0, height > 0 else { return nil }
            return HomeHeaderGlassShape(id: id, rect: CGRect(x: x, y: y, width: width, height: height))
        }
    }
}

@available(iOS 26.0, *)
private struct HomeHeaderGlassShape: Identifiable {
    let id: String
    let rect: CGRect
}

@available(iOS 26.0, *)
private struct HomeHeaderGlassControls: View {
    @ObservedObject var model: HomeHeaderGlassModel
    @Namespace private var glassNamespace
    var body: some View {
        GlassEffectContainer(spacing: 8) {
            ZStack(alignment: .topLeading) {
                ForEach(model.shapes) { shape in
                    Capsule()
                        .fill(.clear)
                        .frame(width: shape.rect.width, height: shape.rect.height)
                        .glassEffect(.regular, in: .capsule)
                        .glassEffectID(shape.id, in: glassNamespace)
                        .position(x: shape.rect.midX, y: shape.rect.midY)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .environment(\.colorScheme, model.dark ? .dark : .light)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

@available(iOS 26.0, *)
private final class HomeCaptureModel: ObservableObject {
    @Published var state: [String: Any]
    @Published var pending = false
    var send: ((String, [String: Any], FlutterResult?) -> Void)?
    var height: CGFloat = 64
    var recordButtonExtent: CGFloat = 64
    init(state: [String: Any]) { self.state = state }
    func flag(_ key: String) -> Bool { state[key] as? Bool == true }
    func label(_ key: String) -> String { (state["labels"] as? [String: String])?[key] ?? "" }
    var active: Bool { flag("active") && state["source"] as? String == "phone" }
    var userPaused: Bool { state["status"] as? String == "paused" }
    var clockPaused: Bool { flag("paused") }
    var busy: Bool { pending || flag("busy") }
    func elapsed(at date: Date) -> TimeInterval {
        guard active else { return 0 }
        if clockPaused {
            let seconds = (state["elapsed"] as? NSNumber)?.doubleValue ?? 0
            return seconds.isFinite ? max(0, seconds) : 0
        }
        guard let anchor = (state["startedAt"] as? NSNumber)?.doubleValue, anchor.isFinite, anchor > 0 else { return 0 }
        return max(0, date.timeIntervalSince1970 - anchor)
    }
    func act(_ action: String) {
        guard action == "ask" || !busy else { return }
        let isCaptureAction = action != "ask" && action != "options" && action != "details"
        if isCaptureAction { pending = true }
        send?("action", [
            "action": action,
            "recordingId": state["recordingId"] ?? "",
            "conversationRevision": state["conversationRevision"] ?? 0,
        ]) { [weak self] _ in
            guard let self else { return }
            // Dart publishes canonical state on every completion. Never apply an
            // older method result over a newer capture/ownership notification.
            if isCaptureAction { self.pending = false }
        }
    }
}

@available(iOS 26.0, *)
private struct HomeCaptureControls: View {
    @ObservedObject var model: HomeCaptureModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize
    @Namespace private var glassNamespace
    @State private var isExpanded = false
    @State private var askLabelOpacity = 1.0
    @State private var recordGlyphOpacity = 1.0
    @State private var recordingOpacity = 0.0
    @State private var askLabelWidth: CGFloat = 0
    @State private var availableWidth: CGFloat = 0
    @State private var endLabelWidth: CGFloat = 76
    @ScaledMetric(relativeTo: .body) private var accessibleRowHeight: CGFloat = 64
    private let controlHeight: CGFloat = 64
    private let gap: CGFloat = 12
    private let askLabelGap: CGFloat = 8
    private var usesStackedLayout: Bool {
        let wideWidth = availableWidth - controlHeight - gap
        return typeSize >= .xxLarge || (availableWidth > 0 &&
            (askLabelWidth + 68 > wideWidth || endLabelWidth + 112 > wideWidth))
    }
    private var rowHeight: CGFloat { usesStackedLayout ? accessibleRowHeight : controlHeight }
    private var recorderHeight: CGFloat { usesStackedLayout && isExpanded ? rowHeight * 2 + gap : rowHeight }
    private var barHeight: CGFloat { usesStackedLayout ? rowHeight + gap + recorderHeight : rowHeight }
    private var recordingCornerRadius: CGFloat { usesStackedLayout && isExpanded ? 32 : rowHeight / 2 }
    private var transition: Animation? { reduceMotion ? nil : .spring(duration: 0.25, bounce: 0) }
    private var fadeOut: Animation {
        reduceMotion ? .easeOut(duration: 0.15) : .timingCurve(0.23, 1, 0.32, 1, duration: 0.125)
    }
    private var fadeIn: Animation {
        reduceMotion ? .easeOut(duration: 0.15) : .timingCurve(0.23, 1, 0.32, 1, duration: 0.2).delay(0.05)
    }

    var body: some View {
        GeometryReader { geometry in
            controls(availableWidth: geometry.size.width)
                .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { availableWidth = $0 }
                .frame(maxHeight: .infinity, alignment: .bottom)
        }
        .environment(\.colorScheme, model.flag("dark") ? .dark : .light)
        .onAppear { synchronize(animated: false); reportHeight() }
        .onChange(of: model.active) { _, _ in synchronize(animated: true) }
        .onChange(of: barHeight) { _, _ in reportHeight() }
    }

    private func reportHeight() {
        model.height = barHeight
        model.recordButtonExtent = rowHeight
        model.send?("height", ["height": barHeight, "recordButtonExtent": rowHeight], nil)
    }

    private func synchronize(animated: Bool) {
        let active = model.active
        withAnimation(animated ? transition : nil) { isExpanded = active }
        withAnimation(animated ? fadeOut : nil) {
            if active { askLabelOpacity = 0; recordGlyphOpacity = 0 }
            else { recordingOpacity = 0 }
        }
        withAnimation(animated ? fadeIn : nil) {
            if active { recordingOpacity = 1 }
            else { askLabelOpacity = 1; recordGlyphOpacity = 1 }
        }
    }

    private func controls(availableWidth: CGFloat) -> some View {
        let wideWidth = max(rowHeight, availableWidth - rowHeight - gap)
        return GlassEffectContainer(spacing: gap) {
            if usesStackedLayout {
                VStack(spacing: gap) {
                    glassShell(width: availableWidth, height: rowHeight, id: "ask")
                    glassShell(width: isExpanded ? availableWidth : rowHeight,
                               height: recorderHeight, id: "recording")
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
            } else {
                HStack(spacing: gap) {
                    glassShell(width: isExpanded ? rowHeight : wideWidth, height: rowHeight, id: "ask")
                    glassShell(width: isExpanded ? wideWidth : rowHeight, height: rowHeight, id: "recording")
                }
                .frame(width: availableWidth)
            }
        }
        .overlay {
            // Foreground is outside the glass rendering group so it stays sharp.
            if usesStackedLayout {
                // Large text gets space, rather than shrinking type to fit the compact row.
                VStack(spacing: gap) {
                    askButton(width: availableWidth, compact: false)
                    recordingSurface(width: isExpanded ? availableWidth : rowHeight,
                                     contentWidth: availableWidth)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
            } else {
                HStack(spacing: gap) {
                    askButton(width: isExpanded ? rowHeight : wideWidth, compact: isExpanded)
                    recordingSurface(width: isExpanded ? wideWidth : rowHeight,
                                     contentWidth: wideWidth)
                }
                .frame(width: availableWidth, alignment: .leading)
            }
        }
    }

    private func glassShell(width: CGFloat, height: CGFloat, id: String) -> some View {
        let radius = id == "recording" ? recordingCornerRadius : rowHeight / 2
        return RoundedRectangle(cornerRadius: radius, style: .continuous)
            .fill(.clear)
            .frame(width: width, height: height)
            .glassEffect(.regular.interactive(), in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .glassEffectID(id, in: glassNamespace)
    }

    private func recordingSurface(width: CGFloat, contentWidth: CGFloat) -> some View {
        // Only the shell changes size. Foreground controls retain their natural dimensions.
        Color.clear
            .frame(width: width, height: recorderHeight)
            .overlay {
                if isExpanded && model.flag("canOpenDetails") {
                    // A sibling behind the controls catches the capsule's padding and gaps.
                    // Pause and End keep their own gestures; the timer owns detail semantics.
                    Button { model.act("details") } label: {
                        Color.clear
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .contentShape(RoundedRectangle(cornerRadius: recordingCornerRadius, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .disabled(model.busy)
                    .accessibilityHidden(true)
                }
            }
            .overlay(alignment: .trailing) {
                activeControls
                    .frame(width: contentWidth, height: usesStackedLayout ? rowHeight * 2 + gap : rowHeight)
                    .opacity(recordingOpacity)
                    .allowsHitTesting(isExpanded)
            }
            .overlay(alignment: .trailing) {
                Button { model.act("record") } label: {
                    Group {
                        // Flutter overlays the existing OmiSpinner while busy.
                        if model.busy { Color.clear }
                        else {
                            Image(systemName: "circle.fill")
                                .font(.system(.title3, weight: .regular))
                                .foregroundStyle(Color(uiColor: .systemRed))
                        }
                    }
                        .frame(width: rowHeight, height: rowHeight)
                        .contentShape(Circle())
                }
                .buttonStyle(ControlPressStyle(reduceMotion: reduceMotion))
                .accessibilityLabel(model.label("record"))
                .accessibilityIdentifier("recordButton")
                .opacity(recordGlyphOpacity)
                .disabled(model.busy)
                .highPriorityGesture(model.flag("canShowOptions")
                    ? LongPressGesture(minimumDuration: 0.5).onEnded { _ in model.act("options") }
                    : nil)
                .accessibilityActions {
                    if model.flag("canShowOptions") {
                        Button(model.label("options")) { model.act("options") }
                    }
                }
                .allowsHitTesting(!isExpanded)
                .accessibilityHidden(isExpanded)
            }
            .clipShape(RoundedRectangle(cornerRadius: recordingCornerRadius, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: recordingCornerRadius, style: .continuous))
    }

    private func askButton(width: CGFloat, compact: Bool) -> some View {
        Button {
            model.act("ask")
        } label: {
            Color.clear
                .frame(width: width, height: rowHeight)
                .overlay {
                    if usesStackedLayout {
                        Label(model.label("ask"), systemImage: "bubble.left")
                            .font(.system(.body, weight: .medium))
                            .lineLimit(2)
                            .padding(.horizontal, 20)
                    } else {
                        HStack(spacing: askLabelGap) {
                            Image(systemName: "bubble.left")
                                .font(.system(.title3, weight: .medium))
                            Text(model.label("ask"))
                                .font(.system(.body, weight: .medium))
                                .fixedSize()
                                .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { askLabelWidth = $0 }
                                .opacity(askLabelOpacity)
                        }
                        .fixedSize()
                        // Translate the intact row so the persistent bubble centers on collapse.
                        // The fading label exits through the capsule's trailing clipping boundary.
                        .offset(x: compact ? (askLabelWidth + askLabelGap) / 2 : 0)
                    }
                }
                .clipShape(Capsule())
                .contentShape(Capsule())
        }
        .buttonStyle(ControlPressStyle(reduceMotion: reduceMotion))
        .accessibilityLabel(model.label("ask"))
        .accessibilityIdentifier("askButton")
    }

    @ViewBuilder
    private var activeControls: some View {
        if usesStackedLayout {
            VStack(spacing: gap) {
                captureTime
                    .frame(height: rowHeight)
                HStack {
                    pauseButton
                    Spacer(minLength: 12)
                    endButton
                }
                .padding(.horizontal, 4)
                .frame(height: rowHeight)
            }
        } else {
            HStack(spacing: 4) {
                pauseButton
                captureTime
                endButton
            }
            .padding(.leading, 8)
            .padding(.trailing, 4)
        }
    }

    private var captureTime: some View {
        TimelineView(.periodic(from: .now, by: 1)) { timeline in
            let value = Self.elapsed(model.elapsed(at: timeline.date))
            if model.flag("canOpenDetails") {
                Button { model.act("details") } label: {
                    timeLabel(value)
                        .frame(maxWidth: .infinity, minHeight: 44, maxHeight: .infinity)
                        .contentShape(Rectangle())
                }
                .buttonStyle(ControlPressStyle(reduceMotion: reduceMotion))
                .accessibilityLabel(model.label("details"))
                .accessibilityHint(model.label("detailsHint"))
                .accessibilityValue(value)
                .accessibilityIdentifier("recordingDetailsButton")
                .disabled(model.busy)
                .accessibilityHidden(!isExpanded)
            } else {
                timeLabel(value)
                    .frame(maxWidth: .infinity, minHeight: 44, maxHeight: .infinity)
                    .accessibilityLabel(model.label(model.userPaused ? "paused" : "recording"))
                    .accessibilityValue(value)
                    .accessibilityIdentifier("captureTime")
                    .accessibilityHidden(!isExpanded)
            }
        }
    }

    private func timeLabel(_ value: String) -> some View {
        Text(value)
            .font(.system(.title3, design: .rounded, weight: .medium))
            .monospacedDigit()
            .lineLimit(1)
            .foregroundStyle(model.clockPaused ? .secondary : .primary)
    }

    private var pauseButton: some View {
        Button { model.act(model.userPaused ? "resume" : "pause") } label: {
            Image(systemName: model.userPaused ? "play.fill" : "pause.fill")
                .font(.system(.title3, weight: .semibold))
                .contentTransition(.symbolEffect(.replace))
                .animation(reduceMotion ? nil : .easeInOut(duration: 0.16), value: model.userPaused)
                .padding(12)
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Circle())
        }
        .buttonStyle(ControlPressStyle(reduceMotion: reduceMotion))
        .accessibilityLabel(model.label(model.userPaused ? "resume" : "pause"))
        .disabled(model.busy || !model.flag("canPause"))
        .accessibilityIdentifier("pauseButton")
        .accessibilityHidden(!isExpanded)
    }

    private var endButton: some View {
        Button { model.act("finish") } label: {
            Text(model.label("end"))
                .font(.system(.body, weight: .semibold))
                .fixedSize(horizontal: true, vertical: false)
                .foregroundStyle(Color(uiColor: .systemBackground))
                .padding(.horizontal, 20)
                .frame(minWidth: 76, minHeight: rowHeight - 8)
                .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { endLabelWidth = $0 }
                .background(Color(uiColor: .label), in: .capsule)
                .contentShape(Capsule())
        }
        .buttonStyle(ControlPressStyle(reduceMotion: reduceMotion))
        .accessibilityLabel(model.label("endAccessibility"))
        .disabled(model.busy || !model.flag("canFinish"))
        .accessibilityIdentifier("endButton")
        .accessibilityHidden(!isExpanded)
    }

    private static func elapsed(_ duration: TimeInterval) -> String {
        let formatter = DateComponentsFormatter()
        formatter.unitsStyle = .positional
        formatter.zeroFormattingBehavior = .pad
        formatter.allowedUnits = duration >= 3600 ? [.hour, .minute, .second] : [.minute, .second]
        return formatter.string(from: max(0, duration)) ?? ""
    }
}

private struct ControlPressStyle: ButtonStyle {
    var reduceMotion: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.75 : 1)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.97 : 1)
            .animation(.timingCurve(0.23, 1, 0.32, 1, duration: 0.16), value: configuration.isPressed)
    }
}

#endif
