//
//  CanvasAnnotations.swift
//  Studio Guru
//
//  Canvas annotation and drawing functionality using PencilKit
//

import SwiftUI
#if canImport(PencilKit)
import PencilKit
#endif
import Combine

// MARK: - PencilKit Canvas View

#if canImport(PencilKit)

/// SwiftUI wrapper for PencilKit's PKCanvasView
#if os(iOS)
struct DrawingCanvasView: UIViewRepresentable {
    @Binding var canvasView: PKCanvasView
    @Binding var isDrawingMode: Bool
    let onDrawingChanged: (PKDrawing) -> Void
    
    func makeUIView(context: Context) -> PKCanvasView {
        let canvas = canvasView
        canvas.delegate = context.coordinator
        canvas.drawingPolicy = .anyInput  // Allow finger and Apple Pencil
        canvas.backgroundColor = .clear
        canvas.isOpaque = false
        canvas.tool = PKInkingTool(.pen, color: .black, width: 10)  // Set default tool
        
        // Store tool picker in coordinator for reliable access
        context.coordinator.setupToolPicker(for: canvas)
        
        return canvas
    }
    
    func updateUIView(_ uiView: PKCanvasView, context: Context) {
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
#else
// macOS placeholder - PencilKit not fully supported yet
class PKCanvasViewPlaceholder {
    var drawing = PKDrawing()
}
#endif

#endif // canImport(PencilKit)

// MARK: - Annotation Overlay View

#if canImport(PencilKit)

/// Main annotation view that overlays the studio canvas
struct CanvasAnnotationOverlay: View {
    let studio: Studio
    @Binding var isDrawingMode: Bool
    
    var body: some View {
        #if os(iOS)
        // Create a new view model for each studio
        CanvasAnnotationContent(studio: studio, isDrawingMode: $isDrawingMode)
            .id(studio.id)  // Force complete recreation when studio changes
        #elseif os(macOS)
        // macOS: Display-only mode - show annotations as static image
        CanvasAnnotationMacView(studio: studio)
            .id(studio.id)
        #endif
    }
}

#if os(iOS)
/// Internal view that manages the canvas with its own ViewModel
private struct CanvasAnnotationContent: View {
    let studio: Studio
    @Binding var isDrawingMode: Bool
    @StateObject private var viewModel: AnnotationViewModel
    
    init(studio: Studio, isDrawingMode: Binding<Bool>) {
        self.studio = studio
        self._isDrawingMode = isDrawingMode
        self._viewModel = StateObject(wrappedValue: AnnotationViewModel(studio: studio))
    }
    
    var body: some View {
        DrawingCanvasView(
            canvasView: $viewModel.canvasView,
            isDrawingMode: $isDrawingMode,
            onDrawingChanged: { drawing in
                viewModel.saveDrawing(drawing, to: studio)
            }
        )
        .allowsHitTesting(isDrawingMode)
        .onChange(of: studio.canvasDrawingData) { _, _ in
            // Reload drawing when data changes (e.g., from iCloud sync)
            viewModel.loadDrawing(from: studio)
        }
    }
}
#endif

#if os(macOS)
/// macOS read-only view that displays annotations as an image
private struct CanvasAnnotationMacView: View {
    let studio: Studio
    @State private var drawingImage: NSImage?
    
    var body: some View {
        Group {
            if let image = drawingImage {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .allowsHitTesting(false)
            } else {
                Color.clear
                    .allowsHitTesting(false)
            }
        }
        .onAppear {
            loadDrawing()
        }
        .onChange(of: studio.canvasDrawingData) { _, _ in
            loadDrawing()
        }
    }
    
    private func loadDrawing() {
        guard let drawingData = studio.canvasDrawingData else {
            drawingImage = nil
            return
        }
        
        do {
            let drawing = try PKDrawing(data: drawingData)
            drawingImage = drawing.image(from: drawing.bounds, scale: 1.0)
        } catch {
            print("Failed to load drawing on Mac: \(error)")
            drawingImage = nil
        }
    }
}
#endif

// MARK: - View Model

@MainActor
class AnnotationViewModel: ObservableObject {
    #if os(iOS)
    @Published var canvasView = PKCanvasView()
    #else
    @Published var canvasView = PKCanvasViewPlaceholder()
    #endif
    
    init(studio: Studio) {
        loadDrawing(from: studio)
    }
    
    func loadDrawing(from studio: Studio) {
        if let drawingData = studio.canvasDrawingData {
            do {
                let drawing = try PKDrawing(data: drawingData)
                canvasView.drawing = drawing
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
        do {
            let data = drawing.dataRepresentation()
            // Only save if data has changed to avoid unnecessary updates
            if studio.canvasDrawingData != data {
                studio.canvasDrawingData = data
                studio.markAsModified()
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
#endif // canImport(PencilKit)

