//
//  CanvasAnnotations.swift
//  Studio Guru
//
//  Canvas annotation and drawing functionality using PencilKit
//

import SwiftUI
import PencilKit
import Combine

// MARK: - PencilKit Canvas View

/// SwiftUI wrapper for PencilKit's PKCanvasView
#if os(iOS)
struct DrawingCanvasView: UIViewRepresentable {
    @Binding var canvasView: PKCanvasView
    @Binding var isDrawingMode: Bool
    let onDrawingChanged: (PKDrawing) -> Void
    
    func makeUIView(context: Context) -> PKCanvasView {
        canvasView.delegate = context.coordinator
        canvasView.drawingPolicy = .anyInput  // Allow finger and Apple Pencil
        canvasView.backgroundColor = .clear
        canvasView.isOpaque = false
        
        let toolPicker = PKToolPicker()
        toolPicker.setVisible(isDrawingMode, forFirstResponder: canvasView)
        toolPicker.addObserver(canvasView)
        canvasView.becomeFirstResponder()
        
        return canvasView
    }
    
    func updateUIView(_ uiView: PKCanvasView, context: Context) {
        let toolPicker = PKToolPicker()
        if isDrawingMode {
            toolPicker.setVisible(true, forFirstResponder: uiView)
            uiView.becomeFirstResponder()
        } else {
            toolPicker.setVisible(false, forFirstResponder: uiView)
            uiView.resignFirstResponder()
        }
        
        uiView.isUserInteractionEnabled = isDrawingMode
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(onDrawingChanged: onDrawingChanged)
    }
    
    class Coordinator: NSObject, PKCanvasViewDelegate {
        let onDrawingChanged: (PKDrawing) -> Void
        
        init(onDrawingChanged: @escaping (PKDrawing) -> Void) {
            self.onDrawingChanged = onDrawingChanged
        }
        
        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            onDrawingChanged(canvasView.drawing)
        }
    }
}
#elseif os(macOS)
import AppKit

struct DrawingCanvasView: NSViewRepresentable {
    @Binding var canvasView: PKCanvasView
    @Binding var isDrawingMode: Bool
    let onDrawingChanged: (PKDrawing) -> Void
    
    func makeNSView(context: Context) -> PKCanvasView {
        canvasView.delegate = context.coordinator
        canvasView.drawingPolicy = .anyInput  // Allow mouse and trackpad
        canvasView.backgroundColor = .clear
        
        // Show tool picker on Mac
        let toolPicker = PKToolPicker()
        toolPicker.setVisible(isDrawingMode, forFirstResponder: canvasView)
        toolPicker.addObserver(canvasView)
        
        return canvasView
    }
    
    func updateNSView(_ nsView: PKCanvasView, context: Context) {
        let toolPicker = PKToolPicker()
        if isDrawingMode {
            toolPicker.setVisible(true, forFirstResponder: nsView)
            nsView.window?.makeFirstResponder(nsView)
        } else {
            toolPicker.setVisible(false, forFirstResponder: nsView)
        }
        
        nsView.isUserInteractionEnabled = isDrawingMode
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(onDrawingChanged: onDrawingChanged)
    }
    
    class Coordinator: NSObject, PKCanvasViewDelegate {
        let onDrawingChanged: (PKDrawing) -> Void
        
        init(onDrawingChanged: @escaping (PKDrawing) -> Void) {
            self.onDrawingChanged = onDrawingChanged
        }
        
        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            onDrawingChanged(canvasView.drawing)
        }
    }
}
#endif

// MARK: - Annotation Overlay View

/// Main annotation view that overlays the studio canvas
struct CanvasAnnotationOverlay: View {
    let studio: Studio
    @Binding var isDrawingMode: Bool
    @StateObject private var viewModel: AnnotationViewModel
    
    init(studio: Studio, isDrawingMode: Binding<Bool>) {
        self.studio = studio
        self._isDrawingMode = isDrawingMode
        self._viewModel = StateObject(wrappedValue: AnnotationViewModel(studio: studio))
    }
    
    var body: some View {
        ZStack {
            if isDrawingMode {
                // PencilKit drawing canvas
                DrawingCanvasView(
                    canvasView: $viewModel.canvasView,
                    isDrawingMode: $isDrawingMode,
                    onDrawingChanged: { drawing in
                        viewModel.saveDrawing(drawing, to: studio)
                    }
                )
                .allowsHitTesting(isDrawingMode)
            } else {
                // Show saved drawing (read-only)
                if !viewModel.canvasView.drawing.strokes.isEmpty {
                    #if os(iOS)
                    Image(uiImage: viewModel.canvasView.drawing.image(
                        from: viewModel.canvasView.drawing.bounds,
                        scale: UIScreen.main.scale
                    ))
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .allowsHitTesting(false)
                    #elseif os(macOS)
                    Image(nsImage: viewModel.canvasView.drawing.image(
                        from: viewModel.canvasView.drawing.bounds,
                        scale: NSScreen.main?.backingScaleFactor ?? 2.0
                    ))
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .allowsHitTesting(false)
                    #endif
                }
            }
        }
    }
}

// MARK: - View Model

@MainActor
class AnnotationViewModel: ObservableObject {
    @Published var canvasView = PKCanvasView()
    
    init(studio: Studio) {
        loadDrawing(from: studio)
    }
    
    func loadDrawing(from studio: Studio) {
        guard let drawingData = studio.canvasDrawingData else { return }
        
        do {
            let drawing = try PKDrawing(data: drawingData)
            canvasView.drawing = drawing
        } catch {
            print("Failed to load drawing: \(error)")
        }
    }
    
    func saveDrawing(_ drawing: PKDrawing, to studio: Studio) {
        do {
            let data = drawing.dataRepresentation()
            studio.canvasDrawingData = data
        } catch {
            print("Failed to save drawing: \(error)")
        }
    }
    
    func clearDrawing(for studio: Studio) {
        canvasView.drawing = PKDrawing()
        studio.canvasDrawingData = nil
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
