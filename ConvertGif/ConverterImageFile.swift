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
    private let fps: Int32 = 30
    private var imageSize: CGSize = .zero
    
    func convertGifFile() {
        if let gifFile = Bundle.main.url(forResource: "my", withExtension: "gif") {
            if let imageSource = CGImageSourceCreateWithURL(gifFile as CFURL, nil) {
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
                
                let frames = frameArray(images, delays, totalDuration)
                let duration = TimeInterval(Double(totalDuration)/100.0)
                if let animatedImage = UIImage.animatedImage(with: frames, duration: duration) {
                    imageSize = CGSize(width: animatedImage.size.width * 2, height: animatedImage.size.height * 2)
                    createMP4file(animatedImage, filename: "convertedFile.mp4")
                }
            }
        }
    }
    
    func createMP4file(_ animatedImage: UIImage, filename: String) {
        guard let images = animatedImage.images else {
            return
        }
        
        let filePath = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Documents").appendingPathComponent(filename)
        
        let _ = try? FileManager.default.removeItem(at: filePath)
        
        let fps: Int32 = 30
        
        let assetWriter = try? AVAssetWriter(url: filePath, fileType: .mov)
        
        let assetWriterInput = AVAssetWriterInput(mediaType: .video, outputSettings: [AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: NSNumber(value: Int32(imageSize.width)), AVVideoHeightKey: NSNumber(value: Int32(imageSize.height))])
        
        let bufferAdaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: assetWriterInput, sourcePixelBufferAttributes: nil)
        
        let success = assetWriter?.canAdd(assetWriterInput)
        print(success ?? "")
        
        assetWriterInput.expectsMediaDataInRealTime = true
        
        assetWriter?.add(assetWriterInput)
        
        assetWriter?.startWriting()
        assetWriter?.startSession(atSourceTime: .zero)
        
        var buffer: CVPixelBuffer? = nil
        
        
        //convert uiimage to CGImage.
        var frameCount: Int = 0
        let numberOfSecondsPerFrame: Double = 0.1
        let frameDuration: Double = Double(fps) * numberOfSecondsPerFrame
        
        for img in images {
            buffer = pixelBuffer(from: img.cgImage)
            
            var append_ok = false
            var j: Int = 0
            while !append_ok && j < 30 {
                if bufferAdaptor.assetWriterInput.isReadyForMoreMediaData {
                    //print out status:
                    let value = Double(frameCount) * frameDuration
                    let frameTime: CMTime = CMTimeMake(value: Int64(value), timescale: fps)
                    if let buffer = buffer {
                        append_ok = bufferAdaptor.append(buffer, withPresentationTime: frameTime)
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
        
        assetWriterInput.markAsFinished()
        assetWriter?.finishWriting {
            
        }
    }
    
    func pixelBuffer(from image: CGImage?) -> CVPixelBuffer? {
        guard let image = image else {return nil}
        
        let options = [
            kCVPixelBufferCGImageCompatibilityKey : NSNumber(value: true),
            kCVPixelBufferCGBitmapContextCompatibilityKey : NSNumber(value: true)
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
        
        if let context = CGContext(data: pxdata, width: Int(imageSize.width), height: Int(imageSize.height), bitsPerComponent: 8, bytesPerRow: Int(4 * imageSize.width), space: rgbColorSpace, bitmapInfo: UInt32(bitmapInfo.rawValue)) {
            context.concatenate(CGAffineTransform(rotationAngle: 0))
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
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
