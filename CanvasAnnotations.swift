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
            // Get or create the shared tool picker
            if let window = canvasView.window {
                toolPicker = PKToolPicker.shared(for: window)
            } else {
                toolPicker = PKToolPicker()
            }
            
            toolPicker?.addObserver(canvasView)
        }
        
        func updateToolPickerVisibility(for canvasView: PKCanvasView, isDrawingMode: Bool) {
            guard let toolPicker = toolPicker else {
                // Fallback: try to get tool picker if not already set
                if let window = canvasView.window {
                    self.toolPicker = PKToolPicker.shared(for: window)
                    self.toolPicker?.addObserver(canvasView)
                }
                guard let toolPicker = self.toolPicker else { return }
                self.updateToolPickerVisibility(for: canvasView, isDrawingMode: isDrawingMode)
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
    
    var body: some View {
        #if os(iOS)
        // Create a new view model for each studio
        CanvasAnnotationContent(studio: studio, isDrawingMode: $isDrawingMode, canvasScale: canvasScale)
            .id(studio.id)  // Force complete recreation when studio changes
        #elseif os(macOS)
        // macOS: Display-only mode - show annotations as static image
        CanvasAnnotationMacView(studio: studio, canvasBounds: canvasBounds, canvasScale: canvasScale)
            .id("\(studio.id)-\(studio.modifiedAt.timeIntervalSince1970)")
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
        
        do {
            let data = drawing.dataRepresentation()
            // Only save if data has changed to avoid unnecessary updates
            if studio.canvasDrawingData != data {
                studio.canvasDrawingData = data
                studio.markAsModified()
                lastLoadedData = data
                print("💾 Saved drawing to SwiftData")
            }
        } catch {
            print("Failed to save drawing: \(error)")
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
