import AppKit
import CoreGraphics
import ImageIO

extension NSImage {
    /// Descomprime y rasteriza completamente una imagen en memoria como mapa de bits RGBA sin compresión.
    ///
    /// Esto elimina por completo el deadlock en macOS/SwiftUI entre ImageIO (`AppleJPEGReadPlugin`
    /// en la cola `com.apple.SwiftUI.prepare-image`) y CoreAnimation (`CA_prepareRenderValue`
    /// en el hilo principal) que congelaba la app al interactuar con el notch o expandir la carátula.
    public static func decodedImage(from data: Data) -> NSImage? {
        guard !data.isEmpty else { return nil }
        
        let sourceOptions: [CFString: Any] = [
            kCGImageSourceShouldCache: true,
            kCGImageSourceShouldCacheImmediately: true
        ]
        
        guard let source = CGImageSourceCreateWithData(data as CFData, sourceOptions as CFDictionary) else {
            // Fallback directo a NSImage estándar si CGImageSource no puede interpretar los datos
            guard let fallback = NSImage(data: data) else { return nil }
            return fallback.rasterized()
        }
        
        let imageOptions: [CFString: Any] = [
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceCreateThumbnailFromImageAlways: false
        ]
        
        guard let cgImage = CGImageSourceCreateImageAtIndex(source, 0, imageOptions as CFDictionary) else {
            guard let fallback = NSImage(data: data) else { return nil }
            return fallback.rasterized()
        }
        
        let width = cgImage.width
        let height = cgImage.height
        guard width > 0, height > 0 else { return nil }
        
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
        
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ) else {
            let rep = NSBitmapImageRep(cgImage: cgImage)
            let image = NSImage(size: NSSize(width: width, height: height))
            image.addRepresentation(rep)
            return image
        }
        
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        
        guard let decodedCG = context.makeImage() else {
            let rep = NSBitmapImageRep(cgImage: cgImage)
            let image = NSImage(size: NSSize(width: width, height: height))
            image.addRepresentation(rep)
            return image
        }
        
        let rep = NSBitmapImageRep(cgImage: decodedCG)
        let image = NSImage(size: NSSize(width: width, height: height))
        image.addRepresentation(rep)
        return image
    }
    
    /// Convierte cualquier NSImage existente a una representación de mapa de bits descomprimida en memoria
    public func rasterized() -> NSImage {
        if let existingRep = self.representations.compactMap({ $0 as? NSBitmapImageRep }).first,
           existingRep.bitmapData != nil {
            return self
        }
        
        guard let tiff = self.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff) else {
            return self
        }
        let image = NSImage(size: self.size)
        image.addRepresentation(rep)
        return image
    }
}
