//
//  CanvasAnnotations.swift
//  Studio Guru
//
//  Canvas annotation and drawing functionality using PencilKit
//

import SwiftUI
import Combine
import PencilKit
#if os(macOS)
import AppKit
#endif

// MARK: - PencilKit Canvas View

/// SwiftUI wrapper for PencilKit's PKCanvasView
#if os(iOS)
struct DrawingCanvasView: UIViewRepresentable {
    @Binding var canvasView: PKCanvasView
    @Binding var isDrawingMode: Bool
    let canvasScale: CGFloat
    let onDrawingChanged: (PKDrawing) -> Void
    
    func makeUIView(context: Context) -> PKCanvasView {
        let canvas = canvasView
        canvas.delegate = context.coordinator
        canvas.drawingPolicy = .anyInput  // Allow finger and Apple Pencil
        canvas.backgroundColor = .clear
        canvas.isOpaque = false
        canvas.tool = PKInkingTool(.pen, color: .black, width: 10)  // Set default tool
        
        // Scale the canvas transform to match the visual zoom level
        // This makes the drawing area match the scaled canvas content
        canvas.transform = CGAffineTransform(scaleX: canvasScale, y: canvasScale)
        
        // Store tool picker in coordinator for reliable access
        context.coordinator.setupToolPicker(for: canvas)
        
        return canvas
    }
    
    func updateUIView(_ uiView: PKCanvasView, context: Context) {
        // Only update transform if scale actually changed to avoid unnecessary updates
        let currentTransform = uiView.transform
        let targetTransform = CGAffineTransform(scaleX: canvasScale, y: canvasScale)
        if currentTransform != targetTransform {
            // Use UIView animation for smoother transform updates during orientation changes
            UIView.animate(withDuration: 0.2, delay: 0, options: [.curveEaseInOut, .allowUserInteraction]) {
                uiView.transform = targetTransform
            }
        }
        
        // Update tool picker visibility based on drawing mode
        context.coordinator.updateToolPickerVisibility(for: uiView, isDrawingMode: isDrawingMode)
        
        // Control interaction
        uiView.isUserInteractionEnabled = isDrawingMode
    }
    
    static func dismantleUIView(_ uiView: PKCanvasView, coordinator: Coordinator) {
        // Ensure tool picker is hidden when view is dismantled
        coordinator.hideToolPicker(for: uiView)
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(onDrawingChanged: onDrawingChanged)
    }
    
    class Coordinator: NSObject, PKCanvasViewDelegate {
        let onDrawingChanged: (PKDrawing) -> Void
        private var toolPicker: PKToolPicker?
        
        init(onDrawingChanged: @escaping (PKDrawing) -> Void) {
            self.onDrawingChanged = onDrawingChanged
        }
        
        func setupToolPicker(for canvasView: PKCanvasView) {
            // Create individual tool picker instance (iOS 14+)
            toolPicker = PKToolPicker()
            toolPicker?.addObserver(canvasView)
        }
        
        func updateToolPickerVisibility(for canvasView: PKCanvasView, isDrawingMode: Bool) {
            guard let toolPicker = toolPicker else {
                // Fallback: create tool picker if not already set
                self.toolPicker = PKToolPicker()
                if self.toolPicker != nil {
                    self.toolPicker?.addObserver(canvasView)
                    self.updateToolPickerVisibility(for: canvasView, isDrawingMode: isDrawingMode)
                }
                return
            }
            
            if isDrawingMode {
                toolPicker.setVisible(true, forFirstResponder: canvasView)
                canvasView.becomeFirstResponder()
            } else {
                toolPicker.setVisible(false, forFirstResponder: canvasView)
                canvasView.resignFirstResponder()
            }
        }
        
        func hideToolPicker(for canvasView: PKCanvasView) {
            toolPicker?.setVisible(false, forFirstResponder: canvasView)
            toolPicker?.removeObserver(canvasView)
            canvasView.resignFirstResponder()
        }
        
        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            onDrawingChanged(canvasView.drawing)
        }
    }
}
#endif // os(iOS)

// MARK: - Annotation Overlay View

/// Main annotation view that overlays the studio canvas
struct CanvasAnnotationOverlay: View {
    let studio: Studio
    @Binding var isDrawingMode: Bool
    var canvasScale: CGFloat = 1.0
    var canvasBounds: CGSize = CGSize(width: 2000, height: 2000)
    @Environment(\.isTouchMode) private var isTouchMode
    
    var body: some View {
        #if os(iOS)
        // Create a new view model for each studio
        CanvasAnnotationContent(studio: studio, isDrawingMode: $isDrawingMode, canvasScale: canvasScale)
            .id(studio.id)  // Force complete recreation when studio changes
        #elseif os(macOS)
        if isTouchMode {
            // Touch-enabled Mac: finger drawing, like iPad
            CanvasAnnotationMacEditor(
                studio: studio,
                isDrawingMode: isDrawingMode,
                canvasBounds: canvasBounds,
                canvasScale: canvasScale
            )
            .id(studio.id)
        } else {
            // macOS without touch: Display-only mode - show annotations as static image
            CanvasAnnotationMacView(studio: studio, canvasBounds: canvasBounds, canvasScale: canvasScale)
                .id("\(studio.id)-\(studio.modifiedAt.timeIntervalSince1970)")
        }
        #endif
    }
}

#if os(iOS)
/// Internal view that manages the canvas with its own ViewModel
private struct CanvasAnnotationContent: View {
    let studio: Studio
    @Binding var isDrawingMode: Bool
    let canvasScale: CGFloat
    @StateObject private var viewModel: AnnotationViewModel
    
    init(studio: Studio, isDrawingMode: Binding<Bool>, canvasScale: CGFloat) {
        self.studio = studio
        self._isDrawingMode = isDrawingMode
        self.canvasScale = canvasScale
        self._viewModel = StateObject(wrappedValue: AnnotationViewModel(studio: studio))
    }
    
    var body: some View {
        DrawingCanvasView(
            canvasView: $viewModel.canvasView,
            isDrawingMode: $isDrawingMode,
            canvasScale: canvasScale,
            onDrawingChanged: { drawing in
                viewModel.saveDrawing(drawing, to: studio)
            }
        )
        .allowsHitTesting(isDrawingMode)
        .onChange(of: studio.canvasDrawingData) { _, _ in
            // Reload drawing when data changes (e.g., from iCloud sync)
            viewModel.loadDrawing(from: studio)
        }
        .onChange(of: studio.modifiedAt) { _, _ in
            // Also check on modifiedAt changes (catches iCloud sync events)
            viewModel.loadDrawing(from: studio)
        }
        .onAppear {
            // Ensure drawing is loaded when view appears
            viewModel.loadDrawing(from: studio)
        }
    }
}
#endif

#if os(macOS)
/// macOS display-only view for annotations (no interactive editing on Mac)
private struct CanvasAnnotationMacView: View {
    let studio: Studio
    let canvasBounds: CGSize
    let canvasScale: CGFloat
    
    var body: some View {
        // Display annotations as a static image on Mac
        if let drawingData = studio.canvasDrawingData,
           let drawing = try? PKDrawing(data: drawingData) {
            // Render the drawing at the full canvas size (not just drawing.bounds)
            // This ensures the annotation appears at the correct size and position
            let renderRect = CGRect(x: 0, y: 0, width: canvasBounds.width, height: canvasBounds.height)
            let image = drawing.image(from: renderRect, scale: canvasScale)
            Image(nsImage: image)
                .resizable()
                .frame(width: canvasBounds.width * canvasScale, height: canvasBounds.height * canvasScale)
                .allowsHitTesting(false)
        }
    }
}
#endif


#if os(macOS)
// MARK: - macOS Touch Drawing

/// Drawing tool state shared between the palette and the drawing surface (touch-enabled Macs).
@Observable
final class MacAnnotationTools {
    enum Tool { case pen, eraser }

    var tool: Tool = .pen
    var color: Color = .black
    /// Pen width in canvas points (matches the iPad default of 10)
    var width: CGFloat = 10
    /// Incremented by the palette to ask the drawing surface to undo
    var undoRequest = 0
    var canUndo = false
}

/// Finger drawing surface for touch-enabled Macs. Reads and writes the same `PKDrawing`
/// data as the iPad PencilKit canvas, so annotations stay compatible across devices.
private struct CanvasAnnotationMacEditor: View {
    let studio: Studio
    let isDrawingMode: Bool
    let canvasBounds: CGSize
    let canvasScale: CGFloat

    @Environment(MacAnnotationTools.self) private var tools

    @State private var drawing = PKDrawing()
    @State private var lastLoadedData: Data?
    @State private var undoStack: [PKDrawing] = []
    /// In-progress pen stroke, in view coordinates
    @State private var livePoints: [CGPoint] = []
    @State private var strokeStart: Date?
    @State private var didSnapshotForErase = false

    private var viewSize: CGSize {
        CGSize(width: canvasBounds.width * canvasScale, height: canvasBounds.height * canvasScale)
    }

    var body: some View {
        ZStack {
            // Committed annotations
            Image(nsImage: drawing.image(
                from: CGRect(origin: .zero, size: canvasBounds),
                scale: canvasScale
            ))
            .resizable()
            .frame(width: viewSize.width, height: viewSize.height)
            .allowsHitTesting(false)

            // Stroke being drawn right now
            if livePoints.count > 1 {
                Path { path in
                    path.addLines(livePoints)
                }
                .stroke(
                    tools.color,
                    style: StrokeStyle(lineWidth: tools.width * canvasScale, lineCap: .round, lineJoin: .round)
                )
                .allowsHitTesting(false)
            }

            // Touch surface
            Color.clear
                .contentShape(Rectangle())
                .gesture(drawGesture)
                .allowsHitTesting(isDrawingMode)
        }
        .frame(width: viewSize.width, height: viewSize.height)
        .onAppear { loadDrawing() }
        .onChange(of: studio.canvasDrawingData) { _, _ in loadDrawing() }
        .onChange(of: tools.undoRequest) { _, _ in undo() }
    }

    // MARK: Gesture

    private var drawGesture: some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .onChanged { value in
                switch tools.tool {
                case .pen:
                    if livePoints.isEmpty { strokeStart = Date() }
                    livePoints.append(value.location)
                case .eraser:
                    if !didSnapshotForErase {
                        pushUndo()
                        didSnapshotForErase = true
                    }
                    erase(at: CGPoint(x: value.location.x / canvasScale, y: value.location.y / canvasScale))
                }
            }
            .onEnded { _ in
                switch tools.tool {
                case .pen:
                    commitLiveStroke()
                case .eraser:
                    didSnapshotForErase = false
                    save()
                }
            }
    }

    // MARK: Drawing operations

    private func commitLiveStroke() {
        defer {
            livePoints = []
            strokeStart = nil
        }
        guard !livePoints.isEmpty else { return }

        let start = strokeStart ?? Date()
        let size = CGSize(width: tools.width, height: tools.width)
        // A tap leaves a single point; give it a second so it renders as a dot
        let points = livePoints.count == 1 ? livePoints + livePoints : livePoints
        let controlPoints = points.enumerated().map { index, point in
            PKStrokePoint(
                location: CGPoint(x: point.x / canvasScale, y: point.y / canvasScale),
                timeOffset: TimeInterval(index) * 0.01,
                size: size,
                opacity: 1,
                force: 1,
                azimuth: 0,
                altitude: .pi / 2
            )
        }
        let path = PKStrokePath(controlPoints: controlPoints, creationDate: start)
        let ink = PKInk(.pen, color: NSColor(tools.color))

        pushUndo()
        drawing.strokes.append(PKStroke(ink: ink, path: path))
        save()
    }

    /// Removes any stroke passing within a fingertip of `point` (canvas coordinates).
    private func erase(at point: CGPoint) {
        let reach = 14 / canvasScale  // constant on-screen size regardless of zoom
        let remaining = drawing.strokes.filter { stroke in
            let hit = stroke.path.interpolatedPoints(by: .distance(6)).contains { strokePoint in
                let location = strokePoint.location.applying(stroke.transform)
                let tolerance = reach + strokePoint.size.width / 2
                return hypot(location.x - point.x, location.y - point.y) <= tolerance
            }
            return !hit
        }
        if remaining.count != drawing.strokes.count {
            drawing.strokes = remaining
        }
    }

    private func pushUndo() {
        undoStack.append(drawing)
        if undoStack.count > 30 { undoStack.removeFirst() }
        tools.canUndo = true
    }

    private func undo() {
        guard let previous = undoStack.popLast() else { return }
        drawing = previous
        tools.canUndo = !undoStack.isEmpty
        save()
    }

    // MARK: Persistence

    private func loadDrawing() {
        let data = studio.canvasDrawingData
        // Ignore the echo of our own save
        guard data != lastLoadedData else { return }
        lastLoadedData = data

        if let data, let loaded = try? PKDrawing(data: data) {
            drawing = loaded
        } else {
            drawing = PKDrawing()
        }
        undoStack = []
        tools.canUndo = false
    }

    private func save() {
        let data = drawing.dataRepresentation()
        guard studio.canvasDrawingData != data else { return }
        lastLoadedData = data
        studio.canvasDrawingData = data
        studio.markAsModified()
    }
}

/// Floating tool palette for touch drawing on the Mac. Shown while annotating.
struct MacAnnotationPalette: View {
    @Bindable var tools: MacAnnotationTools
    let onDone: () -> Void

    private let swatches: [Color] = [.black, .red, .blue, .green, .orange]
    private let widths: [(label: String, value: CGFloat)] = [("Thin", 4), ("Medium", 10), ("Thick", 20)]

    var body: some View {
        HStack(spacing: 16) {
            Picker("Tool", selection: $tools.tool) {
                Image(systemName: "pencil.tip").tag(MacAnnotationTools.Tool.pen)
                Image(systemName: "eraser").tag(MacAnnotationTools.Tool.eraser)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 110)

            if tools.tool == .pen {
                HStack(spacing: 10) {
                    ForEach(swatches, id: \.self) { color in
                        Button {
                            tools.color = color
                        } label: {
                            Circle()
                                .fill(color)
                                .frame(width: 28, height: 28)
                                .overlay(
                                    Circle().strokeBorder(.white, lineWidth: tools.color == color ? 3 : 0)
                                )
                                .overlay(Circle().strokeBorder(.secondary.opacity(0.4), lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                    }
                }

                Picker("Width", selection: $tools.width) {
                    ForEach(widths, id: \.value) { Text($0.label).tag($0.value) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 180)
            }

            Button {
                tools.undoRequest += 1
            } label: {
                Label("Undo", systemImage: "arrow.uturn.backward")
                    .labelStyle(.iconOnly)
            }
            .disabled(!tools.canUndo)

            Button("Done", action: onDone)
                .buttonStyle(.borderedProminent)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.regularMaterial, in: Capsule())
        .shadow(radius: 6)
        .padding(.top, 12)
    }
}
#endif

// MARK: - View Model

#if os(iOS)
@MainActor
class AnnotationViewModel: ObservableObject {
    @Published var canvasView = PKCanvasView()
    
    private var lastLoadedData: Data?
    private var isSaving = false
    
    init(studio: Studio) {
        loadDrawing(from: studio)
    }
    
    func loadDrawing(from studio: Studio) {
        // Don't reload if we're currently saving (prevents overwriting user's changes)
        guard !isSaving else { return }
        
        let newData = studio.canvasDrawingData
        
        // Only reload if the data actually changed
        guard newData != lastLoadedData else { return }
        
        lastLoadedData = newData
        
        if let drawingData = newData {
            do {
                let drawing = try PKDrawing(data: drawingData)
                canvasView.drawing = drawing
                print("✅ Loaded drawing from iCloud sync")
            } catch {
                print("Failed to load drawing: \(error)")
                canvasView.drawing = PKDrawing()  // Clear on error
            }
        } else {
            // No drawing data - clear the canvas
            canvasView.drawing = PKDrawing()
        }
    }
    
    func saveDrawing(_ drawing: PKDrawing, to studio: Studio) {
        isSaving = true
        defer { isSaving = false }
        
        let data = drawing.dataRepresentation()
        // Only save if data has changed to avoid unnecessary updates
        if studio.canvasDrawingData != data {
            studio.canvasDrawingData = data
            studio.markAsModified()
            lastLoadedData = data
            print("💾 Saved drawing to SwiftData")
        }
    }
    
    func clearDrawing(for studio: Studio) {
        canvasView.drawing = PKDrawing()
        studio.canvasDrawingData = nil
        studio.markAsModified()
    }
}
#endif // os(iOS)

// MARK: - Toolbar Button

/// Toolbar button for toggling annotation mode
struct AnnotationModeButton: View {
    @Binding var isDrawingMode: Bool
    
    var body: some View {
        Button {
            isDrawingMode.toggle()
        } label: {
            Label(
                isDrawingMode ? "Done Drawing" : "Annotate",
                systemImage: isDrawingMode ? "checkmark.circle.fill" : "pencil.tip.crop.circle"
            )
        }
        .keyboardShortcut("d", modifiers: [.command])
    }
}
