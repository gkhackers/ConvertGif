//
//  ConverterImageFile.swift
//  ConvertGif
//
//  Created by kyongjin on 26/02/2019.
//  Copyright © 2019 claire. All rights reserved.
//

import Foundation
import AVKit

class Converter {
    private let fps: Int32 = 600
    private var imageSize: CGSize = CGSize(width: 10, height: 10)
    private let fileURL = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Documents").appendingPathComponent("converted.mp4")
    
    private var assetWriter: AVAssetWriter?
    private var bufferAdaptor: AVAssetWriterInputPixelBufferAdaptor?
    
    //MARK: - Public methods
    
    func convertGifFile() {
        guard let gifFile = Bundle.main.url(forResource: "check", withExtension: "gif") else {
            print("No file at bundle.")
            return
        }
        
        guard let imageSource = CGImageSourceCreateWithURL(gifFile as CFURL, nil) else {
            print("Image Source is not available.")
            return
        }
        
        if let properties = CGImageSourceCopyPropertiesAtIndex(imageSource, 0, nil) {
            if let propertyDictionary = properties as? [String: AnyObject] {
                if let width = propertyDictionary[kCGImagePropertyPixelWidth as String] {
                    imageSize.width = width as! CGFloat
                }
                if let height = propertyDictionary[kCGImagePropertyPixelHeight as String] {
                    imageSize.height = height as! CGFloat
                }
            }
        }
        
        setupControllers(fileURL, size: imageSize)
        
        guard let adaptor = bufferAdaptor else {
            return
        }

        let count = CGImageSourceGetCount(imageSource)
        var images: [CGImage] = [CGImage]()
        var delays: [Int] = [Int]()
        var totalDuration: Int = 0
        for i in 0 ..< count {
            if let image = CGImageSourceCreateImageAtIndex(imageSource, i, [:] as CFDictionary) {
                images.append(image)
                delays.append(delayCentisecondsForImageAtIndex(source: imageSource, i: Int(i)))
            }
            totalDuration += delays[i]
        }
        
        assetWriter?.startWriting()
        assetWriter?.startSession(atSourceTime: .zero)
        
        var frameCount: Int = 0
        var presentTime: CMTime = .zero
        
        for img in images {
            var append_ok = false
            var j: Int = 0
            while !append_ok && j < 30 {
                if adaptor.assetWriterInput.isReadyForMoreMediaData {
                    
                    let delay = Double(delays[frameCount]) / 100
                    let value = delay * Double(fps)
                    let frameTime: CMTime = CMTimeMake(value: Int64(value), timescale: fps)
                    presentTime = CMTimeAdd(presentTime, frameTime)
                    
                    if let buffer = pixelBuffer(from: img) {
                        append_ok = adaptor.append(buffer, withPresentationTime: presentTime)
                    }
                    if !append_ok {
                        if let error = assetWriter?.error {
                            print(error.localizedDescription)
                        }
                    }
                } else {
                    print("adaptor not ready \(frameCount), \(j)\n")
                    Thread.sleep(forTimeInterval: 0.1)
                }
                j += 1
            }
            if !append_ok {
                print("error appending image \(frameCount) times \(j)\n, with error.")
            }
            frameCount += 1
        }
        assetWriter?.inputs[0].markAsFinished()
        assetWriter?.finishWriting {}
    }
    
    //MARK: - Internal methods
    private func setupControllers(_ fileURL: URL, size: CGSize) {
        
        if FileManager.default.fileExists(atPath: fileURL.path) {
            do {
                try FileManager.default.removeItem(at: fileURL)
            } catch {
                print(error.localizedDescription)
                return
            }
        }
        
        let assetWriter = try? AVAssetWriter(url: fileURL, fileType: .mov)
        
        let assetWriterInput = AVAssetWriterInput(mediaType: .video,
                                                  outputSettings: [AVVideoCodecKey: AVVideoCodecType.h264,
                                                                   AVVideoWidthKey: NSNumber(value: Int32(size.width)),
                                                                   AVVideoHeightKey: NSNumber(value: Int32(size.height)),
                                                                   AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: Int(640000)]])
        
        let bufferAdaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: assetWriterInput, sourcePixelBufferAttributes: nil)
        
        let _ = assetWriter?.canAdd(assetWriterInput)
        
        assetWriterInput.expectsMediaDataInRealTime = true
        
        assetWriter?.add(assetWriterInput)
        
        self.assetWriter = assetWriter
        self.bufferAdaptor = bufferAdaptor
    }

    private func pixelBuffer(from image: CGImage?) -> CVPixelBuffer? {
        guard let image = image else {return nil}
        
        let options = [
            kCVPixelBufferCGImageCompatibilityKey : kCFBooleanTrue,
            kCVPixelBufferCGBitmapContextCompatibilityKey : kCFBooleanTrue,
            
            ] as CFDictionary
        
        var pxbuffer: CVPixelBuffer? = nil
        
        let status = CVPixelBufferCreate(kCFAllocatorDefault, Int(imageSize.width), Int(imageSize.height), kCVPixelFormatType_32ARGB, options, &pxbuffer)
        if status != kCVReturnSuccess {
            print("Failed to create pixel buffer")
        }
        
        guard let pixelBuffer = pxbuffer else {
            return nil
        }
        
        CVPixelBufferLockBaseAddress(pixelBuffer, [])
        let pxdata = CVPixelBufferGetBaseAddress(pixelBuffer)
        
        let rgbColorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue)
        
        if let context = CGContext(data: pxdata, width: Int(imageSize.width),
                                   height: Int(imageSize.height),
                                   bitsPerComponent: 8,
                                   bytesPerRow: CVPixelBufferGetBytesPerRow(pixelBuffer),
                                   space: rgbColorSpace,
                                   bitmapInfo: UInt32(bitmapInfo.rawValue)) {
            context.concatenate(CGAffineTransform(rotationAngle: 0))
            context.draw(image, in: CGRect(x: 0, y: 0, width: Int(imageSize.width), height: Int(imageSize.height)))
        }
        
        CVPixelBufferUnlockBaseAddress(pixelBuffer, [])
        
        return pxbuffer
    }
    
    private func delayCentisecondsForImageAtIndex(source: CGImageSource, i: Int) -> Int {
        var delayCentiseconds: Int = 1
        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, i, nil) else {
            return delayCentiseconds
        }
        
        let gifProperty = unsafeBitCast(kCGImagePropertyGIFDictionary, to: UnsafeRawPointer.self)
        let gifProperties: CFDictionary = unsafeBitCast(CFDictionaryGetValue(properties, gifProperty), to: CFDictionary.self)
        
        let delayTimeProperty = unsafeBitCast(kCGImagePropertyGIFUnclampedDelayTime, to: UnsafeRawPointer.self)
        var number = unsafeBitCast(CFDictionaryGetValue(gifProperties, delayTimeProperty), to: NSNumber.self)
        if number.doubleValue == 0 {
            let delayTimeProperty = unsafeBitCast(kCGImagePropertyGIFDelayTime, to: UnsafeRawPointer.self)
            number = unsafeBitCast(CFDictionaryGetValue(gifProperties, delayTimeProperty), to: NSNumber.self)
        }
        
        if number.doubleValue > 0 {
            // Even though the GIF stores the delay as an integer number of centiseconds, ImageIO “helpfully” converts that to seconds for us.
            delayCentiseconds = Int(lrint(number.doubleValue * 100))
        }
        return delayCentiseconds
    }
    
    private func frameArray(_ images: [CGImage], _ delays: [Int], _ totalDuration: Int) -> [UIImage] {
        let delayGCD = gcd(values: delays)
        
        var frames = [UIImage]()
        frames.reserveCapacity(images.count)
        
        for i in 0 ..< images.count {
            let frame = UIImage(cgImage: images[i], scale: UIScreen.main.scale, orientation: .up)
            for _ in 0 ..< delays[i]/delayGCD {
                frames.append(frame)
            }
        }
        
        return frames;
    }
    
    private func gcd(values: Array<Int>) -> Int {
        if values.count == 0 {
            return 1;
        }
        
        var currentGCD = values[0]
        
        for i in 0 ..< values.count {
            currentGCD = gcd(currentGCD, values[i])
        }
        
        return currentGCD;
    }
    
    private func gcd(_ aNumber: Int, _ anotherNumber: Int) -> Int {
        var a = aNumber
        var b = anotherNumber
        while true {
            let r = a % b
            if r == 0 {
                return b
            }
            a = b
            b = r
        }
    }
}
