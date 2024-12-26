//
//  PixlessCameraApp.swift
//  Pixless Camera
//
//  References and Sources:
//
//  1) AVFoundation Camera Setup:
//     https://developer.apple.com/documentation/avfoundation/avcapturesession
//  2) SwiftUI Documentation (TabView, Sheets, Layout):
//     https://developer.apple.com/documentation/swiftui
//  3) Floyd-Steinberg Dithering (Algorithm Overview):
//     https://en.wikipedia.org/wiki/Floyd–Steinberg_dithering
//  4) Lospec Palettes & Formats:
//     https://lospec.com/palette-list
//  5) Saving to Photos with SwiftUI (PhotoKit):
//     https://developer.apple.com/documentation/photokit
//  6) DispatchQueue Concurrency in Swift:
//     https://developer.apple.com/documentation/swift/dispatchqueue
//  7) iOS Share Sheet (UIActivityViewController):
//     https://developer.apple.com/documentation/uikit/uiactivityviewcontroller
//  8) File Importers in SwiftUI (iOS 14+):
//     https://developer.apple.com/documentation/swiftui/fileimport
//
//  Note on HEX file format for Lospec:
//  Typically each line is a 3-, 6-, or 8-character hex code (without '#'), e.g., "b7b1ae".
//

import SwiftUI
import AVFoundation
import Photos
import UniformTypeIdentifiers
import UIKit

// MARK: - Custom UTType for ".hex" files
extension UTType {
    static var lospecHex: UTType {
        UTType(importedAs: "com.mydomain.hexpalette")
    }
}

// MARK: - App Entry Point

struct PixlessCameraApp: App {
    var body: some Scene {
        WindowGroup {
            MainView()
        }
    }
}

// MARK: - MainView
/// Main container that uses a TabView for separate Camera and Gallery sections.
struct MainView: View {
    @StateObject private var cameraManager = CameraManager()
    
    // Toggles + Palettes
    @State private var useDithering: Bool = false
    @State private var selectedPalette: [UIColor] = defaultPalette
    @State private var palettes: [[UIColor]] = [defaultPalette, altPalette]  // Built-in palettes
    
    // Gallery
    @State private var galleryImages: [UIImage] = []
    
    // Capture flow
    @State private var processedImage: UIImage? = nil
    
    // File import
    @State private var showFileImporter: Bool = false
    
    // Zoom + Preset
    @State private var currentZoomFactor: CGFloat = 1.0
    @State private var selectedPreset: AVCaptureSession.Preset = .photo
    
    // Available session presets
    let sessionPresets: [AVCaptureSession.Preset] = [
        .photo, .high, .hd1920x1080, .hd1280x720, .vga640x480, .cif352x288
    ]
    
    var body: some View {
        TabView {
            // Camera Tab
            CameraTabView(
                cameraManager: cameraManager,
                useDithering: $useDithering,
                selectedPalette: $selectedPalette,
                palettes: $palettes,
                galleryImages: $galleryImages,
                processedImage: $processedImage,
                showFileImporter: $showFileImporter,
                currentZoomFactor: $currentZoomFactor,
                selectedPreset: $selectedPreset,
                sessionPresets: sessionPresets
            )
            .tabItem {
                Label("Camera", systemImage: "camera")
            }
            
            // Gallery Tab
            GalleryTabView(images: $galleryImages)
                .tabItem {
                    Label("Gallery", systemImage: "photo.on.rectangle")
                }
        }
        // File importer (for palette import)
        .fileImporter(
            isPresented: $showFileImporter,
            allowedContentTypes: [.json, .lospecHex, .plainText],
            allowsMultipleSelection: false
        ) { result in
            handleFileImporter(result: result)
        }
    }
    
    // MARK: - File Import Handling
    func handleFileImporter(result: Result<[URL], Error>) {
        do {
            let selectedFiles = try result.get()
            guard let fileURL = selectedFiles.first else { return }
            
            let ext = fileURL.pathExtension.lowercased()
            switch ext {
            case "json":
                importLospecPaletteJSON(from: fileURL)
            case "hex", "txt":
                importLospecPaletteHEX(from: fileURL)
            default:
                // Attempt to parse as HEX regardless of extension
                importLospecPaletteHEX(from: fileURL)
            }
        } catch {
            print("Error importing file: \(error.localizedDescription)")
        }
    }
    
    // MARK: - JSON Parsing
    func importLospecPaletteJSON(from fileURL: URL) {
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let data = try Data(contentsOf: fileURL)
                let decoded = try JSONDecoder().decode(LospecPalette.self, from: data)
                
                let newColors = decoded.colors.compactMap { colorFromHex($0) }
                if !newColors.isEmpty {
                    DispatchQueue.main.async {
                        self.palettes.append(newColors)
                        self.selectedPalette = newColors
                        print("Imported JSON palette with \(newColors.count) colors.")
                    }
                } else {
                    print("No valid colors found in JSON palette.")
                }
            } catch {
                print("Failed to import JSON palette: \(error.localizedDescription)")
            }
        }
    }
    
    // MARK: - HEX Parsing
    func importLospecPaletteHEX(from fileURL: URL) {
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let data = try Data(contentsOf: fileURL)
                guard let contentString = String(data: data, encoding: .utf8) else {
                    print("Invalid string encoding for .hex/.txt file.")
                    return
                }
                
                // Filter out blank/comment lines and parse
                let lines = contentString.components(separatedBy: .newlines)
                let filteredLines = lines
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty && !$0.hasPrefix("//") && !$0.hasPrefix("#") }
                
                let hexColors: [UIColor] = filteredLines.compactMap { line in
                    colorFromHex(line)
                }
                
                if !hexColors.isEmpty {
                    DispatchQueue.main.async {
                        self.palettes.append(hexColors)
                        self.selectedPalette = hexColors
                        print("Imported HEX palette with \(hexColors.count) colors.")
                    }
                } else {
                    print("No valid HEX colors found in file.")
                }
            } catch {
                print("Failed to import HEX palette: \(error.localizedDescription)")
            }
        }
    }
}

// MARK: - CameraTabView
struct CameraTabView: View {
    // Camera + Palettes
    @ObservedObject var cameraManager: CameraManager
    @Binding var useDithering: Bool
    @Binding var selectedPalette: [UIColor]
    @Binding var palettes: [[UIColor]]
    
    // Gallery
    @Binding var galleryImages: [UIImage]
    
    // Processed image
    @Binding var processedImage: UIImage?
    
    // File import
    @Binding var showFileImporter: Bool
    
    // Zoom + session
    @Binding var currentZoomFactor: CGFloat
    @Binding var selectedPreset: AVCaptureSession.Preset
    let sessionPresets: [AVCaptureSession.Preset]
    
    var body: some View {
        NavigationView {
            ZStack {
                // Camera Preview
                ZStack(alignment: .top) {
                    CameraPreviewView(session: cameraManager.session)
                        .onAppear {
                            cameraManager.configureSession(preset: selectedPreset)
                            currentZoomFactor = cameraManager.initialZoomFactor
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color.black)
                        // Pinch-to-zoom gesture
                        .gesture(
                            MagnificationGesture()
                                .onChanged { value in
                                    let newZoom = currentZoomFactor * value
                                    cameraManager.setZoomFactor(newZoom)
                                }
                                .onEnded { value in
                                    currentZoomFactor *= value
                                }
                        )
                    
                    // Top Overlays
                    HStack {
                        // Aspect Ratio Menu
                        Menu {
                            ForEach(sessionPresets, id: \.self) { preset in
                                Button(preset.rawValue) {
                                    selectedPreset = preset
                                    cameraManager.configureSession(preset: preset)
                                    currentZoomFactor = 1.0
                                    cameraManager.setZoomFactor(currentZoomFactor)
                                }
                            }
                        } label: {
                            Label("Preset", systemImage: "rectangle.split.3x1")
                                .padding(8)
                                .background(Color.black.opacity(0.5))
                                .foregroundColor(.white)
                                .cornerRadius(8)
                        }
                        
                        Spacer()
                        
                        // Dithering Toggle
                        Toggle("Dither?", isOn: $useDithering)
                            .toggleStyle(SwitchToggleStyle(tint: .green))
                            .padding(8)
                            .background(Color.black.opacity(0.5))
                            .foregroundColor(.white)
                            .cornerRadius(8)
                    }
                    .padding(.horizontal, 12)
                    .padding(.top, 12)
                }
                
                // Small Captured Preview
                if let finalImage = processedImage {
                    VStack {
                        Spacer()
                        HStack {
                            Spacer()
                            
                            // Preview container
                            VStack(spacing: 8) {
                                Image(uiImage: finalImage)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 100, height: 100)
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                                    .transition(.scale.combined(with: .opacity))
                                
                                HStack(spacing: 16) {
                                    Button(action: {
                                        savePNGToPhotoLibrary(image: finalImage)
                                    }) {
                                        Image(systemName: "square.and.arrow.down")
                                            .foregroundColor(.green)
                                            .padding(8)
                                            .background(Color.black.opacity(0.5))
                                            .clipShape(Circle())
                                    }
                                    
                                    Button(action: {
                                        shareImage(finalImage)
                                    }) {
                                        Image(systemName: "square.and.arrow.up")
                                            .foregroundColor(.blue)
                                            .padding(8)
                                            .background(Color.black.opacity(0.5))
                                            .clipShape(Circle())
                                    }
                                }
                            }
                            .padding()
                            .animation(.easeInOut, value: finalImage)
                        }
                    }
                }
                
                // Camera controls overlay at bottom
                VStack {
                    Spacer()
                    CameraControlsView(
                        cameraManager: cameraManager,
                        useDithering: useDithering,
                        selectedPalette: selectedPalette,
                        galleryImages: $galleryImages,
                        processedImage: $processedImage
                    )
                    .padding(.bottom, 20)
                }
            }
            .navigationBarTitle("Pixless Camera", displayMode: .inline)
            .navigationBarHidden(false)
            .toolbar {
                // Zoom slider + palette import in toolbar
                ToolbarItem(placement: .bottomBar) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Zoom: \(String(format: "%.1fx", currentZoomFactor))")
                            .font(.footnote)
                            .foregroundColor(.primary)
                        
                        Slider(
                            value: $currentZoomFactor,
                            in: 1.0...cameraManager.maxZoomFactor,
                            step: 0.1,
                            onEditingChanged: { _ in
                                cameraManager.setZoomFactor(currentZoomFactor)
                            }
                        )
                        .frame(width: 200)
                    }
                }
                
                ToolbarItem(placement: .bottomBar) {
                    Menu("Palettes") {
                        // Built-in + imported
                        ForEach(palettes.indices, id: \.self) { idx in
                            Button("Palette \(idx + 1)") {
                                selectedPalette = palettes[idx]
                            }
                        }
                        Divider()
                        Button("Import .hex/.json") {
                            showFileImporter = true
                        }
                    }
                }
            }
        }
    }
}

// MARK: - CameraControlsView
struct CameraControlsView: View {
    @ObservedObject var cameraManager: CameraManager
    let useDithering: Bool
    let selectedPalette: [UIColor]
    
    @Binding var galleryImages: [UIImage]
    @Binding var processedImage: UIImage?
    
    var body: some View {
        HStack(spacing: 50) {
            // Capture
            Button(action: captureAction) {
                ZStack {
                    Circle().fill(Color.red).frame(width: 60, height: 60)
                    Circle().stroke(Color.white, lineWidth: 3).frame(width: 70, height: 70)
                }
            }
            .shadow(radius: 3)
        }
    }
    
    func captureAction() {
        cameraManager.capturePhoto { capturedImage in
            // Offload image processing to a background thread
            DispatchQueue.global(qos: .userInitiated).async {
                let pixelWidth = 128
                let pixelHeight = 128
                
                if let lowRes = downsampleImage(image: capturedImage,
                                                toWidth: pixelWidth,
                                                toHeight: pixelHeight) {
                    let paletteApplied: UIImage
                    if useDithering {
                        paletteApplied = applyDitheringAndPalette(image: lowRes,
                                                                  palette: selectedPalette)
                    } else {
                        paletteApplied = applyPalette(image: lowRes,
                                                      palette: selectedPalette)
                    }
                    let finalImage = upscaleImage(image: paletteApplied, scale: 8)
                    
                    // Back to main thread for UI updates
                    DispatchQueue.main.async {
                        self.processedImage = finalImage
                        withAnimation {
                            if let finalImage = finalImage {
                                self.galleryImages.insert(finalImage, at: 0)
                            }
                        }
                    }
                }
            }
        }
    }
}

// MARK: - GalleryTabView
struct GalleryTabView: View {
    @Binding var images: [UIImage]
    
    @State private var isGridView: Bool = true
    @State private var reverseOrder: Bool = false
    
    var body: some View {
        NavigationView {
            VStack {
                // QOL: Toggle layout style (grid vs. list) + Sort
                HStack(spacing: 16) {
                    Toggle(isOn: $isGridView.animation(.easeInOut)) {
                        Text("Grid View")
                    }
                    .toggleStyle(SwitchToggleStyle(tint: .blue))
                    .padding(.leading)
                    
                    Toggle(isOn: $reverseOrder.animation(.easeInOut)) {
                        Text("Reverse")
                    }
                    .toggleStyle(SwitchToggleStyle(tint: .red))
                    
                    Spacer()
                }
                .padding(.vertical, 8)
                
                if images.isEmpty {
                    Text("No images in gallery yet.")
                        .foregroundColor(.gray)
                        .padding()
                } else {
                    // We apply the “reverseOrder” by using reversed() on the array
                    let displayedImages = reverseOrder ? images.reversed() : images
                    ScrollView {
                        if isGridView {
                            // Animated Grid
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 100))], spacing: 8) {
                                ForEach(Array(displayedImages.enumerated()), id: \.element) { index, img in
                                    imageCell(img: img, index: index)
                                }
                            }
                            .padding()
                            .transition(.opacity)
                        } else {
                            // Animated List
                            VStack(spacing: 10) {
                                ForEach(Array(displayedImages.enumerated()), id: \.element) { index, img in
                                    imageCell(img: img, index: index)
                                        .frame(height: 120)
                                        .transition(.slide.combined(with: .opacity))
                                }
                            }
                            .padding()
                        }
                    }
                }
                Spacer()
            }
            .navigationBarTitle("Gallery", displayMode: .inline)
        }
    }
    
    @ViewBuilder
    private func imageCell(img: UIImage, index: Int) -> some View {
        Image(uiImage: img)
            .resizable()
            .scaledToFill()
            .cornerRadius(8)
            .clipped()
            .shadow(radius: 2)
            .contextMenu {
                // Context Menu: share, delete
                Button(action: {
                    shareImage(img)
                }) {
                    Label("Share", systemImage: "square.and.arrow.up")
                }
                Button(role: .destructive, action: {
                    // Animate removal
                    withAnimation {
                        images.removeAll(where: { $0 == img })
                    }
                }) {
                    Label("Delete", systemImage: "trash")
                }
            }
            .onTapGesture {
                // Optional: do something on tap
            }
    }
}

// MARK: - CameraPreviewView
struct CameraPreviewView: UIViewRepresentable {
    let session: AVCaptureSession
    
    func makeUIView(context: Context) -> PreviewUIView {
        let view = PreviewUIView()
        view.session = session
        return view
    }
    
    func updateUIView(_ uiView: PreviewUIView, context: Context) {}
}

class PreviewUIView: UIView {
    var session: AVCaptureSession? {
        didSet {
            previewLayer.session = session
        }
    }
    
    private var previewLayer: AVCaptureVideoPreviewLayer!
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        setupPreviewLayer()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupPreviewLayer()
    }
    
    private func setupPreviewLayer() {
        previewLayer = AVCaptureVideoPreviewLayer()
        previewLayer.videoGravity = .resizeAspectFill
        layer.addSublayer(previewLayer)
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        previewLayer.frame = bounds
    }
}

// MARK: - CameraManager
class CameraManager: NSObject, ObservableObject, AVCapturePhotoCaptureDelegate {
    let session = AVCaptureSession()
    private let photoOutput = AVCapturePhotoOutput()
    private var captureCompletion: ((UIImage) -> Void)?
    
    // Zoom handling
    var initialZoomFactor: CGFloat = 1.0
    var maxZoomFactor: CGFloat = 5.0
    
    private var currentDevice: AVCaptureDevice? {
        return session.inputs
            .compactMap { $0 as? AVCaptureDeviceInput }
            .first?.device
    }
    
    override init() {
        super.init()
    }
    
    func configureSession(preset: AVCaptureSession.Preset) {
        session.beginConfiguration()
        session.sessionPreset = preset
        
        // Remove existing inputs
        for input in session.inputs {
            session.removeInput(input)
        }
        
        // Add camera input
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera,
                                                   for: .video,
                                                   position: .back),
              let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input) else {
            session.commitConfiguration()
            print("Failed to add camera input.")
            return
        }
        session.addInput(input)
        
        // Add photo output
        if session.canAddOutput(photoOutput) {
            session.addOutput(photoOutput)
            photoOutput.isHighResolutionCaptureEnabled = true
        } else {
            session.commitConfiguration()
            print("Failed to add photo output.")
            return
        }
        
        // Update zoom factors based on device capabilities
        do {
            try device.lockForConfiguration()
            maxZoomFactor = min(device.maxAvailableVideoZoomFactor, 10.0)
            device.unlockForConfiguration()
        } catch {
            print("Failed to configure zoom factor: \(error.localizedDescription)")
        }
        
        session.commitConfiguration()
        session.startRunning()
    }
    
    func setZoomFactor(_ zoom: CGFloat) {
        guard let device = currentDevice else { return }
        let newZoom = max(1.0, min(zoom, maxZoomFactor))
        do {
            try device.lockForConfiguration()
            device.videoZoomFactor = newZoom
            device.unlockForConfiguration()
        } catch {
            print("Error setting zoom factor: \(error.localizedDescription)")
        }
    }
    
    func capturePhoto(completion: @escaping (UIImage) -> Void) {
        self.captureCompletion = completion
        
        let settings = AVCapturePhotoSettings()
        settings.isHighResolutionPhotoEnabled = true
        photoOutput.capturePhoto(with: settings, delegate: self)
    }
    
    // MARK: AVCapturePhotoCaptureDelegate
    func photoOutput(_ output: AVCapturePhotoOutput,
                     didFinishProcessingPhoto photo: AVCapturePhoto,
                     error: Error?) {
        guard error == nil else {
            print("Error capturing photo: \(error!.localizedDescription)")
            return
        }
        guard let data = photo.fileDataRepresentation(),
              let uiImage = UIImage(data: data) else {
            print("Failed to convert photo data to UIImage.")
            return
        }
        captureCompletion?(uiImage)
    }
}

// MARK: - Image Processing Helpers
func downsampleImage(image: UIImage, toWidth: Int, toHeight: Int) -> UIImage? {
    let size = CGSize(width: toWidth, height: toHeight)
    UIGraphicsBeginImageContextWithOptions(size, false, 1.0)
    image.draw(in: CGRect(origin: .zero, size: size))
    let newImage = UIGraphicsGetImageFromCurrentImageContext()
    UIGraphicsEndImageContext()
    return newImage
}

func upscaleImage(image: UIImage, scale: Int) -> UIImage? {
    let newWidth = Int(image.size.width) * scale
    let newHeight = Int(image.size.height) * scale
    let size = CGSize(width: newWidth, height: newHeight)
    
    UIGraphicsBeginImageContextWithOptions(size, false, 1.0)
    guard let context = UIGraphicsGetCurrentContext() else { return nil }
    
    // Enlarge without smoothing for pixelated effect
    context.interpolationQuality = .none
    image.draw(in: CGRect(origin: .zero, size: size))
    let scaledImage = UIGraphicsGetImageFromCurrentImageContext()
    UIGraphicsEndImageContext()
    
    return scaledImage
}

func applyPalette(image: UIImage, palette: [UIColor]) -> UIImage {
    guard let cgImage = image.cgImage else { return image }
    
    let width = cgImage.width
    let height = cgImage.height
    
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let bytesPerPixel = 4
    let bitsPerComponent = 8
    let bytesPerRow = bytesPerPixel * width
    
    guard let context = CGContext(
        data: nil,
        width: width,
        height: height,
        bitsPerComponent: bitsPerComponent,
        bytesPerRow: bytesPerRow,
        space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else {
        return image
    }
    context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
    guard let buffer = context.data else { return image }
    
    let pixelCount = width * height
    for i in 0..<pixelCount {
        let offset = i * 4
        let r = buffer.load(fromByteOffset: offset, as: UInt8.self)
        let g = buffer.load(fromByteOffset: offset + 1, as: UInt8.self)
        let b = buffer.load(fromByteOffset: offset + 2, as: UInt8.self)
        
        let nearest = findNearestPaletteColor(r: r, g: g, b: b, palette: palette)
        buffer.storeBytes(of: nearest.0, toByteOffset: offset, as: UInt8.self)
        buffer.storeBytes(of: nearest.1, toByteOffset: offset + 1, as: UInt8.self)
        buffer.storeBytes(of: nearest.2, toByteOffset: offset + 2, as: UInt8.self)
    }
    
    guard let newCGImage = context.makeImage() else { return image }
    return UIImage(cgImage: newCGImage)
}

func applyDitheringAndPalette(image: UIImage, palette: [UIColor]) -> UIImage {
    guard let cgImage = image.cgImage else { return image }
    
    let width = cgImage.width
    let height = cgImage.height
    
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let bytesPerPixel = 4
    let bitsPerComponent = 8
    let bytesPerRow = bytesPerPixel * width
    
    guard let context = CGContext(
        data: nil,
        width: width,
        height: height,
        bitsPerComponent: bitsPerComponent,
        bytesPerRow: bytesPerRow,
        space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else {
        return image
    }
    context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
    guard let buffer = context.data else { return image }
    
    func pixelIndex(_ x: Int, _ y: Int) -> Int {
        (y * width + x) * 4
    }
    
    for y in 0..<height {
        for x in 0..<width {
            let idx = pixelIndex(x, y)
            
            let oldR = buffer.load(fromByteOffset: idx, as: UInt8.self)
            let oldG = buffer.load(fromByteOffset: idx + 1, as: UInt8.self)
            let oldB = buffer.load(fromByteOffset: idx + 2, as: UInt8.self)
            
            let (newR, newG, newB) = findNearestPaletteColor(r: oldR, g: oldG, b: oldB, palette: palette)
            
            buffer.storeBytes(of: newR, toByteOffset: idx, as: UInt8.self)
            buffer.storeBytes(of: newG, toByteOffset: idx + 1, as: UInt8.self)
            buffer.storeBytes(of: newB, toByteOffset: idx + 2, as: UInt8.self)
            
            let errR = Int(oldR) - Int(newR)
            let errG = Int(oldG) - Int(newG)
            let errB = Int(oldB) - Int(newB)
            
            func distributeError(toX: Int, toY: Int, factor: Float) {
                if toX < 0 || toX >= width || toY < 0 || toY >= height { return }
                let dstIdx = pixelIndex(toX, toY)
                
                let dr = buffer.load(fromByteOffset: dstIdx, as: UInt8.self)
                let dg = buffer.load(fromByteOffset: dstIdx + 1, as: UInt8.self)
                let db = buffer.load(fromByteOffset: dstIdx + 2, as: UInt8.self)
                
                let nr = clampColorValue(Int(Float(dr) + factor * Float(errR)))
                let ng = clampColorValue(Int(Float(dg) + factor * Float(errG)))
                let nb = clampColorValue(Int(Float(db) + factor * Float(errB)))
                
                buffer.storeBytes(of: UInt8(nr), toByteOffset: dstIdx, as: UInt8.self)
                buffer.storeBytes(of: UInt8(ng), toByteOffset: dstIdx + 1, as: UInt8.self)
                buffer.storeBytes(of: UInt8(nb), toByteOffset: dstIdx + 2, as: UInt8.self)
            }
            
            // Floyd–Steinberg error diffusion
            distributeError(toX: x+1, toY: y,   factor: 7.0/16.0)
            distributeError(toX: x-1, toY: y+1, factor: 3.0/16.0)
            distributeError(toX: x,   toY: y+1, factor: 5.0/16.0)
            distributeError(toX: x+1, toY: y+1, factor: 1.0/16.0)
        }
    }
    
    guard let newCGImage = context.makeImage() else { return image }
    return UIImage(cgImage: newCGImage)
}

// MARK: - LospecPalette
struct LospecPalette: Codable {
    var title: String?
    var colors: [String]
}

// MARK: - Color Utilities
func colorFromHex(_ hex: String) -> UIColor? {
    let cleanHex = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        .trimmingCharacters(in: CharacterSet(charactersIn: "#"))
    
    var hexValue: UInt64 = 0
    guard Scanner(string: cleanHex).scanHexInt64(&hexValue) else {
        return nil
    }
    
    switch cleanHex.count {
    case 3:
        // e.g., "F0A" -> "FF00AA"
        let r = (hexValue & 0xF00) >> 8
        let g = (hexValue & 0x0F0) >> 4
        let b = (hexValue & 0x00F)
        return UIColor(
            red: CGFloat(r) / 15.0,
            green: CGFloat(g) / 15.0,
            blue: CGFloat(b) / 15.0,
            alpha: 1.0
        )
    case 6:
        // e.g., "FF00AA"
        let r = (hexValue & 0xFF0000) >> 16
        let g = (hexValue & 0x00FF00) >> 8
        let b = (hexValue & 0x0000FF)
        return UIColor(
            red: CGFloat(r) / 255.0,
            green: CGFloat(g) / 255.0,
            blue: CGFloat(b) / 255.0,
            alpha: 1.0
        )
    case 8:
        // e.g., "AABBCCDD"
        let a = (hexValue & 0xFF000000) >> 24
        let r = (hexValue & 0x00FF0000) >> 16
        let g = (hexValue & 0x0000FF00) >> 8
        let b = (hexValue & 0x000000FF)
        return UIColor(
            red: CGFloat(r) / 255.0,
            green: CGFloat(g) / 255.0,
            blue: CGFloat(b) / 255.0,
            alpha: CGFloat(a) / 255.0
        )
    default:
        return nil
    }
}

/// Find the nearest color in the palette based on Euclidean distance in RGB space.
func findNearestPaletteColor(r: UInt8, g: UInt8, b: UInt8, palette: [UIColor]) -> (UInt8, UInt8, UInt8) {
    var bestDistance = Int.max
    var bestColor: (UInt8, UInt8, UInt8) = (r, g, b)
    
    for color in palette {
        guard let components = color.cgColor.components, components.count >= 3 else { continue }
        
        let rr = UInt8(clampColorValue(Int(components[0] * 255.0)))
        let gg = UInt8(clampColorValue(Int(components[1] * 255.0)))
        let bb = UInt8(clampColorValue(Int(components[2] * 255.0)))
        
        let distance = (Int(rr) - Int(r)) * (Int(rr) - Int(r))
                     + (Int(gg) - Int(g)) * (Int(gg) - Int(g))
                     + (Int(bb) - Int(b)) * (Int(bb) - Int(b))
        
        if distance < bestDistance {
            bestDistance = distance
            bestColor = (rr, gg, bb)
        }
    }
    
    return bestColor
}

/// Clamp color values between 0 and 255.
func clampColorValue(_ value: Int) -> Int {
    return min(max(value, 0), 255)
}

// MARK: - Predefined Palettes
let defaultPalette: [UIColor] = [
    UIColor(red: 0,   green: 0,   blue: 0,   alpha: 1),
    UIColor(red: 1,   green: 1,   blue: 1,   alpha: 1),
    UIColor(red: 1,   green: 0,   blue: 0,   alpha: 1),
    UIColor(red: 0,   green: 1,   blue: 0,   alpha: 1),
    UIColor(red: 0,   green: 0,   blue: 1,   alpha: 1),
]

let altPalette: [UIColor] = [
    UIColor(red: 0.25, green: 0.25, blue: 0.25, alpha: 1),
    UIColor(red: 0.75, green: 0.75, blue: 0.75, alpha: 1),
    UIColor(red: 1.0,  green: 0.5,  blue: 0,    alpha: 1),
    UIColor(red: 0.5,  green: 0,    blue: 1.0,  alpha: 1),
    UIColor(red: 1.0,  green: 1.0,  blue: 0.0,  alpha: 1),
]

// MARK: - Saving to Photos
func savePNGToPhotoLibrary(image: UIImage) {
    PHPhotoLibrary.requestAuthorization { status in
        guard status == .authorized || status == .limited else {
            print("Photo library access not granted.")
            return
        }
        PHPhotoLibrary.shared().performChanges {
            PHAssetChangeRequest.creationRequestForAsset(from: image)
        } completionHandler: { success, error in
            if success {
                print("Saved PNG to photo library.")
            } else {
                print("Error saving PNG: \(String(describing: error))")
            }
        }
    }
}

// MARK: - Sharing
func shareImage(_ image: UIImage) {
    guard let windowScene = UIApplication.shared
            .connectedScenes
            .first as? UIWindowScene,
          let rootVC = windowScene.windows.first?.rootViewController else {
        return
    }
    let activityVC = UIActivityViewController(activityItems: [image], applicationActivities: nil)
    rootVC.present(activityVC, animated: true)
}
