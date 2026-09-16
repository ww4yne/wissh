import PencilKit
import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct GhosttyAttachmentImageMarkupEditor: View {
    let imageURL: URL
    let outputFormat: GhosttyAttachmentImageMarkupOutputFormat
    let onCancel: () -> Void
    let onDone: (GhosttyAttachmentImageMarkupResult) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var phase: LoadPhase = .loading
    @State private var drawing = PKDrawing()
    @State private var toolPickerVisibilityRequest = UUID()
    @State private var isRendering = false
    @State private var saveFailureMessage: String?

    var body: some View {
        ZStack(alignment: .top) {
            editorContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.bottom, phase.loadedImage == nil ? 0 : 88)

            editorChromeScrim

            toolbar
        }
        .background(Color.black.ignoresSafeArea())
        .foregroundStyle(.white)
        .task(id: imageURL) {
            await loadImage()
        }
        .alert(
            "Annotation Unavailable",
            isPresented: saveFailureAlertBinding,
            actions: {
                Button("OK", role: .cancel) {}
            },
            message: {
                Text(saveFailureMessage ?? "Annotation could not be saved.")
            }
        )
    }

    private var toolbar: some View {
        toolbarContent
        .padding(.horizontal, 20)
        .padding(.top, 10)
    }

    private var toolbarContent: some View {
        HStack(spacing: 12) {
            Button {
                onCancel()
                dismiss()
            } label: {
                Text("Cancel")
                    .frame(width: 92, height: 44)
            }
            .ghosttyMarkupToolbarButtonStyle(.secondary)
            .disabled(isRendering)
            .accessibilityIdentifier("terminal.attachments.markup.cancel")

            Spacer()

            HStack(spacing: 8) {
                if isRendering {
                    ProgressView()
                        .tint(.white)
                        .controlSize(.small)
                }

                if phase.loadedImage != nil, hasDrawing {
                    Button {
                        clearAnnotation()
                    } label: {
                        Image(systemName: "trash")
                            .frame(width: 44, height: 44)
                    }
                    .ghosttyMarkupToolbarButtonStyle(.destructiveIcon)
                    .disabled(isRendering)
                    .accessibilityLabel("Clear annotation")
                    .accessibilityIdentifier("terminal.attachments.markup.clear")
                }

                Button {
                    finishAnnotation()
                } label: {
                    Text("Done")
                        .frame(width: 82, height: 44)
                }
                .ghosttyMarkupToolbarButtonStyle(.primary)
                .disabled(!canFinish)
                .accessibilityIdentifier("terminal.attachments.markup.done")
            }
        }
    }

    private var editorChromeScrim: some View {
        VStack(spacing: 0) {
            LinearGradient(
                colors: [
                    .black.opacity(0.82),
                    .black.opacity(0.46),
                    .black.opacity(0),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 164)

            Spacer()

            LinearGradient(
                colors: [
                    .black.opacity(0),
                    .black.opacity(0.42),
                    .black.opacity(0.78),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 190)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }

    @ViewBuilder
    private var editorContent: some View {
        switch phase {
        case .loading:
            ProgressView()
                .tint(.white)
                .controlSize(.large)

        case .loaded(let image):
            GhosttyAttachmentMarkupCanvas(
                image: image,
                documentSize: GhosttyAttachmentImageMarkupRenderer.documentSize(for: image.size),
                drawing: $drawing,
                toolPickerVisibilityRequest: toolPickerVisibilityRequest
            )
            .accessibilityLabel("Annotation canvas")
            .accessibilityIdentifier("terminal.attachments.markup.canvas")

        case .failed:
            VStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 28, weight: .semibold))
                Text("Image could not be opened.")
                    .font(.system(size: 15, weight: .semibold))
            }
            .foregroundStyle(.white.opacity(0.82))
        }
    }

    private func clearAnnotation() {
        guard !drawing.bounds.isEmpty else { return }
        drawing = PKDrawing()
    }

    private var hasDrawing: Bool {
        !drawing.bounds.isEmpty
    }

    private var canFinish: Bool {
        guard let image = phase.loadedImage else { return false }
        let documentSize = GhosttyAttachmentImageMarkupRenderer.documentSize(for: image.size)
        return !isRendering && documentSize.width > 0 && documentSize.height > 0
    }

    private var saveFailureAlertBinding: Binding<Bool> {
        Binding {
            saveFailureMessage != nil
        } set: { isPresented in
            if !isPresented {
                saveFailureMessage = nil
            }
        }
    }

    private func loadImage() async {
        phase = .loading
        let data = try? await Task.detached(priority: .utility) {
            try Data(contentsOf: imageURL)
        }.value

        guard let data,
              let image = UIImage(data: data) else {
            phase = .failed
            return
        }

        phase = .loaded(image)
    }

    private func finishAnnotation() {
        guard case .loaded(let image) = phase, canFinish else { return }
        guard !drawing.bounds.isEmpty else {
            onCancel()
            dismiss()
            return
        }

        let documentSize = GhosttyAttachmentImageMarkupRenderer.documentSize(for: image.size)
        isRendering = true

        do {
            let result = try GhosttyAttachmentImageMarkupRenderer.renderData(
                baseImage: image,
                drawing: drawing,
                documentSize: documentSize,
                outputFormat: outputFormat
            )
            onDone(result)
        } catch {
            isRendering = false
            saveFailureMessage = "Annotation could not be saved."
        }
    }
}

private enum GhosttyAttachmentMarkupToolbarButtonKind {
    case secondary
    case primary
    case destructiveIcon

    var foreground: Color {
        .white
    }

    var fontSize: CGFloat {
        switch self {
        case .destructiveIcon:
            return 17
        case .primary, .secondary:
            return 16
        }
    }
}

private struct GhosttyAttachmentMarkupToolbarButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    let kind: GhosttyAttachmentMarkupToolbarButtonKind

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: kind.fontSize, weight: .semibold))
            .foregroundStyle(kind.foreground.opacity(isEnabled ? 1 : 0.45))
            .ghosttyMarkupToolbarButtonSurface(
                isPressed: configuration.isPressed,
                isEnabled: isEnabled
            )
            .scaleEffect(configuration.isPressed && isEnabled ? 0.975 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
            .animation(.easeOut(duration: 0.12), value: isEnabled)
    }
}

private extension View {
    func ghosttyMarkupToolbarButtonStyle(_ kind: GhosttyAttachmentMarkupToolbarButtonKind) -> some View {
        buttonStyle(GhosttyAttachmentMarkupToolbarButtonStyle(kind: kind))
    }

    @ViewBuilder
    func ghosttyMarkupToolbarButtonSurface(
        isPressed: Bool,
        isEnabled: Bool
    ) -> some View {
        let shape = Capsule(style: .continuous)
        let pressedOverlay = Color.primary.opacity(isPressed && isEnabled ? 0.08 : 0)

        self
            .background(
                isPressed && isEnabled
                    ? GhosttyShortcutSurfacePalette.embeddedPressedFill
                    : GhosttyShortcutSurfacePalette.embeddedFill,
                in: shape
            )
            .overlay {
                shape.fill(pressedOverlay)
            }
            .overlay {
                shape.strokeBorder(GhosttyShortcutSurfacePalette.contentStroke, lineWidth: 1)
            }
            .contentShape(shape)
            .opacity(isEnabled ? 1 : 0.62)
    }
}

enum GhosttyAttachmentImageMarkupOutputFormat: Equatable, Sendable {
    case png
    case jpeg

    static let jpegCompressionQuality: CGFloat = 0.9

    static func preferred(forFilename filename: String) -> Self {
        let fileExtension = URL(fileURLWithPath: filename)
            .pathExtension
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        switch fileExtension {
        case "png":
            return .png
        case "jpg", "jpeg", "heic", "heif":
            return .jpeg
        default:
            guard let contentType = UTType(filenameExtension: fileExtension),
                  contentType.conforms(to: .jpeg) else {
                return .png
            }
            return .jpeg
        }
    }

    var fileExtension: String {
        switch self {
        case .png:
            return "png"
        case .jpeg:
            return "jpeg"
        }
    }

    var traceLabel: String {
        switch self {
        case .png:
            return "png"
        case .jpeg:
            return "jpeg"
        }
    }
}

struct GhosttyAttachmentImageMarkupResult {
    let data: Data
    let outputFormat: GhosttyAttachmentImageMarkupOutputFormat
    let renderStartedAt: UInt64
    let renderCompletedAt: UInt64
}

enum GhosttyAttachmentImageMarkupRenderer {
    static let maxDocumentLongSide: CGFloat = 1_024
    static let maxExportLongSide: CGFloat = 2_048

    enum RenderError: Error, Equatable {
        case invalidDocumentSize
        case invalidImageSize
        case encodingFailed
    }

    static func outputFilename(
        for sourceFilename: String,
        outputFormat: GhosttyAttachmentImageMarkupOutputFormat
    ) -> String {
        let component = sourceFilename
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split { character in
                character == "/" || character == "\\"
            }
            .last
            .map(String.init) ?? "image"
        let stem = URL(fileURLWithPath: component)
            .deletingPathExtension()
            .lastPathComponent
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return "\(stem.isEmpty ? "image" : stem)-annotated.\(outputFormat.fileExtension)"
    }

    static func aspectFitRect(imageSize: CGSize, containerSize: CGSize) -> CGRect {
        guard imageSize.width > 0,
              imageSize.height > 0,
              containerSize.width > 0,
              containerSize.height > 0 else {
            return .zero
        }

        let scale = min(
            containerSize.width / imageSize.width,
            containerSize.height / imageSize.height
        )
        let size = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
        return CGRect(
            x: (containerSize.width - size.width) / 2,
            y: (containerSize.height - size.height) / 2,
            width: size.width,
            height: size.height
        )
    }

    static func documentSize(for imageSize: CGSize) -> CGSize {
        guard imageSize.width > 0, imageSize.height > 0 else {
            return .zero
        }

        let longSide = max(imageSize.width, imageSize.height)
        let scale = min(1, maxDocumentLongSide / longSide)
        return CGSize(
            width: max(1, (imageSize.width * scale).rounded()),
            height: max(1, (imageSize.height * scale).rounded())
        )
    }

    static func exportSize(for imageSize: CGSize) -> CGSize {
        guard imageSize.width > 0, imageSize.height > 0 else {
            return .zero
        }

        let longSide = max(imageSize.width, imageSize.height)
        let scale = min(1, maxExportLongSide / longSide)
        return CGSize(
            width: max(1, (imageSize.width * scale).rounded()),
            height: max(1, (imageSize.height * scale).rounded())
        )
    }

    @MainActor
    static func renderData(
        baseImage: UIImage,
        drawing: PKDrawing,
        documentSize: CGSize,
        outputFormat: GhosttyAttachmentImageMarkupOutputFormat
    ) throws -> GhosttyAttachmentImageMarkupResult {
        let totalStartedAt = GhosttyRuntimeTrace.nowNanos()
        guard documentSize.width > 0, documentSize.height > 0 else {
            throw RenderError.invalidDocumentSize
        }

        let sourceImageSize = baseImage.size
        guard sourceImageSize.width > 0, sourceImageSize.height > 0 else {
            throw RenderError.invalidImageSize
        }
        let outputImageSize = exportSize(for: sourceImageSize)
        guard outputImageSize.width > 0, outputImageSize.height > 0 else {
            throw RenderError.invalidImageSize
        }

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = outputFormat == .jpeg

        let renderer = UIGraphicsImageRenderer(size: outputImageSize, format: format)
        let compositeStartedAt = GhosttyRuntimeTrace.nowNanos()
        let renderedImage = renderer.image { _ in
            baseImage.draw(in: CGRect(origin: .zero, size: outputImageSize))

            let drawingScale = min(
                outputImageSize.width / documentSize.width,
                outputImageSize.height / documentSize.height
            )
            var drawingImage: UIImage?
            UITraitCollection(userInterfaceStyle: .light).performAsCurrent {
                drawingImage = drawing.image(
                    from: CGRect(origin: .zero, size: documentSize),
                    scale: drawingScale
                )
            }
            drawingImage?.draw(in: CGRect(origin: .zero, size: outputImageSize))
        }
        let compositeCompletedAt = GhosttyRuntimeTrace.nowNanos()

        let encodeStartedAt = GhosttyRuntimeTrace.nowNanos()
        let data: Data?
        switch outputFormat {
        case .png:
            data = renderedImage.pngData()
        case .jpeg:
            data = renderedImage.jpegData(
                compressionQuality: GhosttyAttachmentImageMarkupOutputFormat.jpegCompressionQuality
            )
        }
        let encodeCompletedAt = GhosttyRuntimeTrace.nowNanos()

        guard let data, !data.isEmpty else {
            throw RenderError.encodingFailed
        }

        GhosttyRuntimeTrace.perf(
            "attachment.markup.render format=\(outputFormat.traceLabel) bytes=\(data.count) source_px=\(Int(sourceImageSize.width))x\(Int(sourceImageSize.height)) output_px=\(Int(outputImageSize.width))x\(Int(outputImageSize.height)) document_px=\(Int(documentSize.width))x\(Int(documentSize.height)) composite_ms=\(GhosttyRuntimeTrace.elapsedMilliseconds(from: compositeStartedAt, to: compositeCompletedAt)) encode_ms=\(GhosttyRuntimeTrace.elapsedMilliseconds(from: encodeStartedAt, to: encodeCompletedAt)) total_ms=\(GhosttyRuntimeTrace.elapsedMilliseconds(from: totalStartedAt, to: encodeCompletedAt))"
        )

        return GhosttyAttachmentImageMarkupResult(
            data: data,
            outputFormat: outputFormat,
            renderStartedAt: totalStartedAt,
            renderCompletedAt: encodeCompletedAt
        )
    }
}

private struct GhosttyAttachmentMarkupCanvas: UIViewRepresentable {
    let image: UIImage
    let documentSize: CGSize
    @Binding var drawing: PKDrawing
    let toolPickerVisibilityRequest: UUID

    func makeCoordinator() -> Coordinator {
        Coordinator(
            drawing: $drawing,
            documentSize: documentSize
        )
    }

    func makeUIView(context: Context) -> GhosttyAttachmentMarkupSurfaceView {
        let surfaceView = GhosttyAttachmentMarkupSurfaceView()
        context.coordinator.attach(to: surfaceView)
        surfaceView.configure(image: image, documentSize: documentSize)
        surfaceView.onWindowAttachmentChanged = { [weak coordinator = context.coordinator] canvasView in
            coordinator?.canvasWindowAttachmentDidChange(canvasView)
        }
        context.coordinator.attachToolPicker(
            to: surfaceView.canvasView,
            visibilityRequest: toolPickerVisibilityRequest
        )
        return surfaceView
    }

    func updateUIView(_ surfaceView: GhosttyAttachmentMarkupSurfaceView, context: Context) {
        surfaceView.configure(image: image, documentSize: documentSize)
        if surfaceView.canvasView.drawing != drawing {
            surfaceView.canvasView.drawing = drawing
        }
        context.coordinator.updateToolPicker(
            for: surfaceView.canvasView,
            visibilityRequest: toolPickerVisibilityRequest
        )
    }

    static func dismantleUIView(_ uiView: GhosttyAttachmentMarkupSurfaceView, coordinator: Coordinator) {
        uiView.onWindowAttachmentChanged = nil
        coordinator.detachToolPicker(from: uiView.canvasView)
        coordinator.detach(from: uiView)
    }

    final class Coordinator: NSObject, PKCanvasViewDelegate {
        @Binding private var drawing: PKDrawing
        private let toolPicker: PKToolPicker
        private var requestedVisibilityRequest: UUID?
        private weak var surfaceView: GhosttyAttachmentMarkupSurfaceView?

        init(drawing: Binding<PKDrawing>, documentSize: CGSize) {
            _drawing = drawing
            toolPicker = Self.makeToolPicker(documentSize: documentSize)
        }

        func attach(to surfaceView: GhosttyAttachmentMarkupSurfaceView) {
            self.surfaceView = surfaceView
            surfaceView.scrollView.delegate = self
            surfaceView.canvasView.delegate = self
        }

        func detach(from surfaceView: GhosttyAttachmentMarkupSurfaceView) {
            if surfaceView.scrollView.delegate === self {
                surfaceView.scrollView.delegate = nil
            }
            if surfaceView.canvasView.delegate === self {
                surfaceView.canvasView.delegate = nil
            }
            if self.surfaceView === surfaceView {
                self.surfaceView = nil
            }
        }

        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            drawing = canvasView.drawing
        }

        func viewForZooming(in scrollView: UIScrollView) -> UIView? {
            guard scrollView === surfaceView?.scrollView else { return nil }
            return surfaceView?.contentView
        }

        func scrollViewDidZoom(_ scrollView: UIScrollView) {
            guard scrollView === surfaceView?.scrollView else { return }
            surfaceView?.centerDocument()
        }

        func attachToolPicker(
            to canvasView: PKCanvasView,
            visibilityRequest: UUID
        ) {
            toolPicker.addObserver(canvasView)
            requestToolPickerVisibility(for: canvasView, visibilityRequest: visibilityRequest)
        }

        func updateToolPicker(
            for canvasView: PKCanvasView,
            visibilityRequest: UUID
        ) {
            requestToolPickerVisibility(for: canvasView, visibilityRequest: visibilityRequest)
        }

        func canvasWindowAttachmentDidChange(_ canvasView: PKCanvasView) {
            guard canvasView.window != nil else { return }
            showToolPickerIfReady(for: canvasView)
        }

        func detachToolPicker(from canvasView: PKCanvasView) {
            toolPicker.setVisible(false, forFirstResponder: canvasView)
            toolPicker.removeObserver(canvasView)
        }

        private func requestToolPickerVisibility(
            for canvasView: PKCanvasView,
            visibilityRequest: UUID
        ) {
            let isNewRequest = requestedVisibilityRequest != visibilityRequest
            requestedVisibilityRequest = visibilityRequest

            guard isNewRequest || !canvasView.isFirstResponder else {
                return
            }

            showToolPickerIfReady(for: canvasView)
        }

        private func showToolPickerIfReady(for canvasView: PKCanvasView) {
            guard requestedVisibilityRequest != nil,
                  canvasView.window != nil else {
                return
            }

            canvasView.becomeFirstResponder()
            toolPicker.setVisible(true, forFirstResponder: canvasView)
        }

        private static func makeToolPicker(documentSize: CGSize) -> PKToolPicker {
            let widths = toolWidths(documentSize: documentSize)
            let pen = PKToolPickerInkingItem(
                type: .pen,
                color: .systemBlue,
                width: widths.pen,
                identifier: "remux.markup.pen"
            )
            pen.allowsColorSelection = true

            let marker = PKToolPickerInkingItem(
                type: .marker,
                color: .systemYellow,
                width: widths.marker,
                identifier: "remux.markup.marker"
            )
            marker.allowsColorSelection = true

            let monoline = PKToolPickerInkingItem(
                type: .monoline,
                color: .white,
                width: widths.monoline,
                identifier: "remux.markup.monoline"
            )
            monoline.allowsColorSelection = true

            let eraser = PKToolPickerEraserItem(type: .bitmap)
            let lasso = PKToolPickerLassoItem()
            let ruler = PKToolPickerRulerItem()
            let picker = PKToolPicker(
                toolItems: [
                    pen,
                    marker,
                    monoline,
                    eraser,
                    lasso,
                    ruler,
                ]
            )
            picker.selectedToolItem = pen
            picker.showsDrawingPolicyControls = false
            picker.colorUserInterfaceStyle = .light
            picker.stateAutosaveName = "dev.remux.markup.tool-picker"
            return picker
        }

        private static func toolWidths(documentSize: CGSize) -> (pen: CGFloat, marker: CGFloat, monoline: CGFloat) {
            let longSide = max(documentSize.width, documentSize.height)
            guard longSide > 0 else {
                return (pen: 5, marker: 16, monoline: 7)
            }

            let documentScale = min(1, longSide / GhosttyAttachmentImageMarkupRenderer.maxDocumentLongSide)
            return (
                pen: max(5, 12 * documentScale),
                marker: max(16, 32 * documentScale),
                monoline: max(7, 18 * documentScale)
            )
        }
    }
}

private final class GhosttyAttachmentMarkupSurfaceView: UIView {
    let scrollView = UIScrollView()
    let contentView = UIView()
    let canvasView = GhosttyAttachmentMarkupCanvasView()
    var onWindowAttachmentChanged: ((PKCanvasView) -> Void)?

    private let imageView = UIImageView()
    private var displayedImage: UIImage?
    private var documentSize: CGSize = .zero
    private var needsInitialZoom = true

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(image: UIImage, documentSize: CGSize) {
        guard documentSize.width > 0, documentSize.height > 0 else { return }
        let imageChanged = displayedImage !== image || self.documentSize != documentSize
        guard imageChanged else { return }

        displayedImage = image
        self.documentSize = documentSize
        needsInitialZoom = true

        imageView.image = image
        contentView.bounds = CGRect(origin: .zero, size: documentSize)
        contentView.frame = CGRect(origin: .zero, size: documentSize)
        imageView.frame = contentView.bounds
        canvasView.frame = contentView.bounds
        canvasView.contentSize = documentSize
        scrollView.contentSize = documentSize
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        scrollView.frame = bounds
        updateZoomScales()
        centerDocument()
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        onWindowAttachmentChanged?(canvasView)
    }

    func centerDocument() {
        let horizontalInset = max(0, (scrollView.bounds.width - scrollView.contentSize.width) / 2)
        let verticalInset = max(0, (scrollView.bounds.height - scrollView.contentSize.height) / 2)
        let inset = UIEdgeInsets(
            top: verticalInset,
            left: horizontalInset,
            bottom: verticalInset,
            right: horizontalInset
        )
        if scrollView.contentInset != inset {
            scrollView.contentInset = inset
            scrollView.scrollIndicatorInsets = inset
        }
    }

    private func setup() {
        backgroundColor = .black

        scrollView.backgroundColor = .black
        scrollView.bouncesZoom = true
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.showsVerticalScrollIndicator = false
        scrollView.decelerationRate = .fast
        scrollView.contentInsetAdjustmentBehavior = .never
        scrollView.panGestureRecognizer.minimumNumberOfTouches = 2
        addSubview(scrollView)

        contentView.backgroundColor = .clear
        scrollView.addSubview(contentView)

        imageView.contentMode = .scaleAspectFit
        imageView.backgroundColor = .black
        contentView.addSubview(imageView)

        canvasView.backgroundColor = .clear
        canvasView.isOpaque = false
        canvasView.drawingPolicy = .anyInput
        canvasView.overrideUserInterfaceStyle = .light
        canvasView.isScrollEnabled = false
        canvasView.showsHorizontalScrollIndicator = false
        canvasView.showsVerticalScrollIndicator = false
        contentView.addSubview(canvasView)
    }

    private func updateZoomScales() {
        guard documentSize.width > 0,
              documentSize.height > 0,
              bounds.width > 0,
              bounds.height > 0 else {
            return
        }

        let fitZoom = min(bounds.width / documentSize.width, bounds.height / documentSize.height)
        let maximumZoom = max(fitZoom * 8, 4)
        let previousZoom = scrollView.zoomScale

        scrollView.minimumZoomScale = fitZoom
        scrollView.maximumZoomScale = maximumZoom

        if needsInitialZoom || previousZoom <= 0 {
            scrollView.setZoomScale(fitZoom, animated: false)
            needsInitialZoom = false
            return
        }

        let clampedZoom = min(max(previousZoom, fitZoom), maximumZoom)
        if abs(clampedZoom - previousZoom) > 0.001 {
            scrollView.setZoomScale(clampedZoom, animated: false)
        }
    }
}

private final class GhosttyAttachmentMarkupCanvasView: PKCanvasView {
    override var canBecomeFirstResponder: Bool {
        true
    }
}

private enum LoadPhase {
    case loading
    case loaded(UIImage)
    case failed

    var loadedImage: UIImage? {
        guard case .loaded(let image) = self else { return nil }
        return image
    }
}
