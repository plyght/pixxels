//
//  PixlessCameraApp.swift
//  Pixless Camera
//
//  Created by ChatGPT on 2024-12-25
//
//  References and Sources:
//  - AVFoundation Camera Setup:
//      https://developer.apple.com/documentation/avfoundation/avcapturesession
//  - SwiftUI Documentation:
//      https://developer.apple.com/documentation/swiftui
//  - Floyd-Steinberg Dithering (Algorithm Overview):
//      https://en.wikipedia.org/wiki/Floyd–Steinberg_dithering
//  - Lospec Palettes & Formats:
//      https://lospec.com/palette-list
//  - Saving to Photos with SwiftUI (PhotoKit):
//      https://developer.apple.com/documentation/photokit
//  - DispatchQueue Concurrency in Swift:
//      https://developer.apple.com/documentation/swift/dispatchqueue
//  - iOS Share Sheet (UIActivityViewController):
//      https://developer.apple.com/documentation/uikit/uiactivityviewcontroller
//  - File Importers in SwiftUI (iOS 14+):
//      https://developer.apple.com/documentation/swiftui/fileimport
//
//  Note on HEX file format for Lospec:
//  Typically each line is a 3-, 6-, or 8-character hex code (without '#'), e.g., "b7b1ae".

import SwiftUI
import AVFoundation
import Photos
import UniformTypeIdentifiers
import UIKit

// MARK: - Custom UTType for ".hex" files
extension UTType {
    static var lospecHex: UTType {
        UTType(importedAs: "com.yourdomain.hexpalette")
    }
}

// MARK: - App Entry Point


struct PixlessCameraApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

// MARK: - ContentView (Main UI)
struct ContentView: View {
    @StateObject private var cameraManager = CameraManager()

    // Toggles + Palettes
    @State private var useDithering: Bool = false
    @State private var selectedPalette: [UIColor] = defaultPalette
    @State private var palettes: [[UIColor]] = [defaultPalette, altPalette]  // Built-in palettes

    // Gallery
    @State private var galleryImages: [UIImage] = []

    // Capture flow
    @State private var showImageDetail: Bool = false
    @State private var processedImage: UIImage? = nil

    // File import
    @State private var showFileImporter: Bool = false

    // Zoom slider range
    @State private var currentZoomFactor: CGFloat = 1.0

    // Aspect ratio/preset selection
    let sessionPresets: [AVCaptureSession.Preset] = [
        .photo,
        .high,
        .hd1920x1080,
        .hd1280x720,
        .vga640x480,
        .cif352x288
        // Add more presets if desired and supported by the device.
    ]
    @State private var selectedPreset: AVCaptureSession.Preset = .photo

    var body: some View {
        VStack {
            // Camera Preview with Aspect Ratio and Preset Selection
            ZStack(alignment: .top) {
                CameraPreviewView(session: cameraManager.session)
                    .onAppear {
                        cameraManager.configureSession(preset: selectedPreset)
                        currentZoomFactor = cameraManager.initialZoomFactor
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.black)
                    .overlay(
                        VStack {
                            // Aspect Ratio / Session Preset Menu
                            Menu {
                                ForEach(sessionPresets, id: \.self) { preset in
                                    Button(preset.rawValue) {
                                        selectedPreset = preset
                                        cameraManager.configureSession(preset: preset)
                                        // Reset zoom when changing preset
                                        currentZoomFactor = 1.0
                                        cameraManager.setZoomFactor(currentZoomFactor)
                                    }
                                }
                            } label: {
                                Label("Aspect Ratio", systemImage: "rectangle.split.3x1")
                                    .padding(8)
                                    .background(Color.black.opacity(0.5))
                                    .foregroundColor(.white)
                                    .cornerRadius(8)
                            }
                            .padding([.leading, .top], 16)

                            Spacer()
                        },
                        alignment: .topLeading
                    )
                    .overlay(
                        // Toggle Dithering
                        VStack {
                            Toggle("Dither?", isOn: $useDithering)
                                .toggleStyle(SwitchToggleStyle(tint: .green))
                                .padding()
                                .background(Color.black.opacity(0.5))
                                .foregroundColor(.white)
                                .cornerRadius(8)
                                .padding([.trailing, .top], 16)

                            Spacer()
                        },
                        alignment: .topTrailing
                    )
            }
            .frame(height: 400)

            // Zoom Slider
            VStack {
                HStack {
                    Text("Zoom: \(String(format: "%.1fx", currentZoomFactor))")
                        .foregroundColor(.primary)

                    Slider(value: $currentZoomFactor,
                           in: 1.0...cameraManager.maxZoomFactor,
                           step: 0.1,
                           onEditingChanged: { _ in
                               cameraManager.setZoomFactor(currentZoomFactor)
                           })
                }
                .padding([.horizontal, .top])
            }

            // Palette Selection and Import
            HStack {
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
                .padding()
                .background(Color.gray.opacity(0.2))
                .cornerRadius(8)
                
                Text("Total Palettes: \(palettes.count)")
                    .font(.caption)
                    .foregroundColor(.gray)
            }
            .padding([.horizontal, .top])
            .fileImporter(
                isPresented: $showFileImporter,
                allowedContentTypes: [.json, .lospecHex, .plainText],
                allowsMultipleSelection: false
            ) { result in
                handleFileImporter(result: result)
            }
            
            // Capture and Save Buttons
            HStack(spacing: 40) {
                // Capture Button
                Button(action: {
                    cameraManager.capturePhoto { capturedImage in
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
                                
                                DispatchQueue.main.async {
                                    self.processedImage = finalImage
                                    self.showImageDetail = true
                                    if let finalImage = finalImage {
                                        self.galleryImages.insert(finalImage, at: 0)
                                    }
                                }
                            }
                        }
                    }
                }) {
                    ZStack {
                        Circle()
                            .fill(Color.red)
                            .frame(width: 70, height: 70)
                        Circle()
                            .stroke(Color.white, lineWidth: 4)
                            .frame(width: 80, height: 80)
                    }
                }
                .shadow(radius: 5)
                
                // Save Button
                Button(action: {
                    if let finalImage = processedImage {
                        savePNGToPhotoLibrary(image: finalImage)
                    }
                }) {
                    Image(systemName: "square.and.arrow.down")
                        .font(.title)
                        .foregroundColor(.green)
                        .padding()
                        .background(Color.gray.opacity(0.2))
                        .clipShape(Circle())
                }
                .shadow(radius: 5)
            }
            .padding(.top, 20)
            
            // Gallery View
            if !galleryImages.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack {
                        ForEach(galleryImages, id: \.self) { img in
                            Image(uiImage: img)
                                .resizable()
                                .scaledToFill()
                                .frame(width: 100, height: 100)
                                .clipped()
                                .cornerRadius(8)
                                .shadow(radius: 2)
                                .onTapGesture {
                                    processedImage = img
                                    showImageDetail = true
                                }
                        }
                    }
                    .padding()
                }
                .frame(height: 120)
            }
            
            Spacer()
        }
        .navigationBarHidden(true)
        .sheet(isPresented: $showImageDetail) {
            if let processedImage = processedImage {
                CapturedImageView(
                    image: processedImage,
                    onClose: { showImageDetail = false },
                    onShare: { shareImage(processedImage) },
                    onSave: { savePNGToPhotoLibrary(image: processedImage) }
                )
            }
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
        do {
            let data = try Data(contentsOf: fileURL)
            let decoded = try JSONDecoder().decode(LospecPalette.self, from: data)
            let newColors = decoded.colors.compactMap { colorFromHex($0) }
            if !newColors.isEmpty {
                palettes.append(newColors)
                selectedPalette = newColors
                print("Imported JSON palette with \(newColors.count) colors.")
            } else {
                print("No valid colors found in JSON palette.")
            }
        } catch {
            print("Failed to import JSON palette: \(error.localizedDescription)")
        }
    }
    
    // MARK: - HEX Parsing
    func importLospecPaletteHEX(from fileURL: URL) {
        do {
            let data = try Data(contentsOf: fileURL)
            guard let contentString = String(data: data, encoding: .utf8) else {
                print("Invalid string encoding for .hex/.txt file.")
                return
            }
            
            let lines = contentString.components(separatedBy: .newlines)
            let hexColors: [UIColor] = lines.compactMap { line in
                let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { return nil }
                return colorFromHex(trimmed)
            }
            
            if !hexColors.isEmpty {
                palettes.append(hexColors)
                selectedPalette = hexColors
                print("Imported HEX palette with \(hexColors.count) colors.")
            } else {
                print("No valid HEX colors found in file.")
            }
        } catch {
            print("Failed to import HEX palette: \(error.localizedDescription)")
        }
    }
}

// MARK: - CapturedImageView (Improved UI)
struct CapturedImageView: View {
    let image: UIImage
    var onClose: () -> Void
    var onShare: () -> Void
    var onSave: () -> Void
    
    var body: some View {
        NavigationView {
            VStack {
                Spacer()
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .padding()
                Spacer()
                HStack(spacing: 50) {
                    Button(action: {
                        onShare()
                    }) {
                        VStack {
                            Image(systemName: "square.and.arrow.up")
                                .font(.title)
                            Text("Share")
                                .font(.caption)
                        }
                        .foregroundColor(.blue)
                    }
                    
                    Button(action: {
                        onSave()
                    }) {
                        VStack {
                            Image(systemName: "square.and.arrow.down")
                                .font(.title)
                            Text("Save")
                                .font(.caption)
                        }
                        .foregroundColor(.green)
                    }
                    
                    Button(action: {
                        onClose()
                    }) {
                        VStack {
                            Image(systemName: "xmark.circle")
                                .font(.title)
                            Text("Close")
                                .font(.caption)
                        }
                        .foregroundColor(.red)
                    }
                }
                .padding(.bottom, 30)
            }
            .navigationBarHidden(true)
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
    var initialZoomFactor: CGFloat = 1.0  // Default
    var maxZoomFactor: CGFloat = 5.0      // Fallback
    
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
            maxZoomFactor = min(device.maxAvailableVideoZoomFactor, 10.0)  // Limit max zoom to 10x
            device.unlockForConfiguration()
        } catch {
            print("Failed to configure zoom factor: \(error.localizedDescription)")
        }
        
        session.commitConfiguration()
        session.startRunning()
    }
    
    func setZoomFactor(_ zoom: CGFloat) {
        guard let device = currentDevice else { return }
        let newZoom = max(1.0, min(zoom, device.maxAvailableVideoZoomFactor))
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
    
    guard let context = CGContext(data: nil,
                                  width: width,
                                  height: height,
                                  bitsPerComponent: bitsPerComponent,
                                  bytesPerRow: bytesPerRow,
                                  space: colorSpace,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    else {
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
    
    guard let context = CGContext(data: nil,
                                  width: width,
                                  height: height,
                                  bitsPerComponent: bitsPerComponent,
                                  bytesPerRow: bytesPerRow,
                                  space: colorSpace,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    else {
        return image
    }
    context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
    guard let buffer = context.data else { return image }
    
    func pixelIndex(_ x: Int, _ y: Int) -> Int {
        return (y * width + x) * 4
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
            
            // Floyd–Steinberg distribution
            distributeError(toX: x+1, toY: y,   factor: 7.0/16.0)
            distributeError(toX: x-1, toY: y+1, factor: 3.0/16.0)
            distributeError(toX: x,   toY: y+1, factor: 5.0/16.0)
            distributeError(toX: x+1, toY: y+1, factor: 1.0/16.0)
        }
    }
    
    guard let newCGImage = context.makeImage() else { return image }
    return UIImage(cgImage: newCGImage)
}

// MARK: - Palette + JSON Models
struct LospecPalette: Codable {
    var title: String?
    var colors: [String]
}

// MARK: - Color Utilities
/// Convert a hex string (e.g., "FF00AA" or "b7b1ae") to UIColor.
/// Supports 3, 6, or 8-character hex codes without the '#' prefix.
func colorFromHex(_ hex: String) -> UIColor? {
    let cleanHex = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        .trimmingCharacters(in: CharacterSet(charactersIn: "#"))
    
    var hexValue: UInt64 = 0
    guard Scanner(string: cleanHex).scanHexInt64(&hexValue) else {
        return nil
    }
    
    switch cleanHex.count {
    case 3:
        // Short hex (RGB), e.g., "F0A" -> "FF00AA"
        let r = (hexValue & 0xF00) >> 8
        let g = (hexValue & 0x0F0) >> 4
        let b = hexValue & 0x00F
        return UIColor(
            red: CGFloat(r) / 15.0,
            green: CGFloat(g) / 15.0,
            blue: CGFloat(b) / 15.0,
            alpha: 1.0
        )
    case 6:
        // RRGGBB
        let r = (hexValue & 0xFF0000) >> 16
        let g = (hexValue & 0x00FF00) >> 8
        let b = hexValue & 0x0000FF
        return UIColor(
            red: CGFloat(r) / 255.0,
            green: CGFloat(g) / 255.0,
            blue: CGFloat(b) / 255.0,
            alpha: 1.0
        )
    case 8:
        // AARRGGBB
        let a = (hexValue & 0xFF000000) >> 24
        let r = (hexValue & 0x00FF0000) >> 16
        let g = (hexValue & 0x0000FF00) >> 8
        let b = hexValue & 0x000000FF
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
        
        let distance = (Int(rr) - Int(r)) * (Int(rr) - Int(r)) +
                       (Int(gg) - Int(g)) * (Int(gg) - Int(g)) +
                       (Int(bb) - Int(b)) * (Int(bb) - Int(b))
        
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

// MARK: - Palettes
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
