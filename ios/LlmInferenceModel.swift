import Foundation
import MediaPipeTasksGenAI
import React
import UIKit

protocol LlmInferenceModelDelegate: AnyObject {
  func logging(_ model: LlmInferenceModel, message: String)
  func onPartialResponse(_ model: LlmInferenceModel, requestId: Int, response: String)
  func onErrorResponse(_ model: LlmInferenceModel, requestId: Int, error: String)
}

final class LlmInferenceModel {
  weak var delegate: LlmInferenceModelDelegate?

  private var inference: LlmInference?
  private var currentSession: LlmInferenceSession?

  let handle: Int
  private let modelPath: String
  private let maxTokens: Int
  private let topK: Int
  private let temperature: Float
  private let randomSeed: Int
  private let enableVisionModality: Bool
  private let preferGpuBackend: Bool

  init(
    handle: Int,
    modelPath: String,
    maxTokens: Int,
    topK: Int,
    temperature: Float,
    randomSeed: Int,
    enableVisionModality: Bool,
    preferGpuBackend: Bool
  ) throws {
    self.handle = handle
    self.modelPath = modelPath
    self.maxTokens = maxTokens
    self.topK = topK
    self.temperature = temperature
    self.randomSeed = randomSeed
    self.enableVisionModality = enableVisionModality
    self.preferGpuBackend = preferGpuBackend

    try initializeInference()
  }

  private func initializeInference() throws {
    let llmOptions = LlmInference.Options(modelPath: self.modelPath)
    llmOptions.maxTokens = self.maxTokens
    llmOptions.topk = self.topK
    llmOptions.temperature = self.temperature
    llmOptions.randomSeed = self.randomSeed

    if enableVisionModality {
      llmOptions.supportedLoraRanks = []
      delegate?.logging(self, message: "Vision modality enabled with CPU backend")
    }

    if enableVisionModality {
      delegate?.logging(self, message: "Explicitly set CPU backend for vision modality")
    } else if preferGpuBackend {
      delegate?.logging(self, message: "GPU backend requested for text-only model")
    }

    do {
      self.inference = try LlmInference(options: llmOptions)
      delegate?.logging(self, message: "LlmInference created successfully")
    } catch {
      delegate?.logging(self, message: "Failed to create LlmInference: \(error.localizedDescription)")
      throw error
    }
  }

  func generateResponse(
    prompt: String,
    requestId: Int,
    resolve: @escaping RCTPromiseResolveBlock,
    reject: @escaping RCTPromiseRejectBlock
  ) {
    generateResponseWithImage(
      prompt: prompt,
      requestId: requestId,
      imageBase64: nil,
      resolve: resolve,
      reject: reject
    )
  }

  func generateResponseWithImage(
    prompt: String,
    requestId: Int,
    imageBase64: String?,
    resolve: @escaping RCTPromiseResolveBlock,
    reject: @escaping RCTPromiseRejectBlock
  ) {
    guard let inference = self.inference else {
      reject("INFERENCE_ERROR", "LlmInference not initialized", nil)
      return
    }

    var result = ""

    do {
      currentSession = nil

      let sessionOptions = LlmInferenceSession.Options()
      sessionOptions.topk = self.topK
      sessionOptions.temperature = self.temperature

      do {
        currentSession = try LlmInferenceSession(llmInference: inference, options: sessionOptions)
        delegate?.logging(self, message: "Session created successfully")
      } catch {
        delegate?.logging(self, message: "Failed to create session: \(error.localizedDescription)")
        throw NSError(
          domain: "INFERENCE_ERROR",
          code: 0,
          userInfo: [NSLocalizedDescriptionKey: "Failed to initialize session: \(error.localizedDescription)"]
        )
      }

      currentSession?.addQueryChunk(prompt)

      if let imageBase64 = imageBase64, enableVisionModality {
        do {
          let image = try base64ToImage(imageBase64)
          currentSession?.addImage(image)
          delegate?.logging(self, message: "Image added to session successfully")
        } catch {
          delegate?.logging(self, message: "Failed to add image: \(error.localizedDescription)")
          throw NSError(
            domain: "INFERENCE_ERROR",
            code: 0,
            userInfo: [NSLocalizedDescriptionKey: "Failed to process image: \(error.localizedDescription)"]
          )
        }
      }

      try currentSession?.generateResponseAsync(
        progress: { [weak self] partialResponse, error in
          guard let self = self else { return }

          if let error = error {
            let errorMessage = "Error generating response: \(error.localizedDescription)"
            self.delegate?.onErrorResponse(self, requestId: requestId, error: errorMessage)
            reject("GENERATE_RESPONSE_ERROR", errorMessage, error)
            self.currentSession = nil
          } else if let partialResponse = partialResponse {
            result += partialResponse
            self.delegate?.onPartialResponse(self, requestId: requestId, response: result)
          }
        },
        completion: { [weak self] in
          guard let self = self else { return }
          resolve(result)
          self.currentSession = nil
        })
    } catch {
      let errorMessage = "Setup failed: \(error.localizedDescription)"
      delegate?.logging(self, message: errorMessage)
      delegate?.onErrorResponse(self, requestId: requestId, error: errorMessage)
      reject("INIT_GENERATE_RESPONSE_ERROR", errorMessage, error)
      currentSession = nil
    }
  }

  private func base64ToImage(_ base64String: String) throws -> UIImage {
    let base64Data: String
    if base64String.contains(",") {
      let components = base64String.split(separator: ",", maxSplits: 1)
      base64Data = components.count > 1 ? String(components[1]) : base64String
    } else {
      base64Data = base64String
    }

    guard let imageData = Data(base64Encoded: base64Data) else {
      throw NSError(
        domain: "IMAGE_PROCESSING_ERROR",
        code: 0,
        userInfo: [NSLocalizedDescriptionKey: "Failed to decode base64 string"]
      )
    }

    guard let originalImage = UIImage(data: imageData) else {
      throw NSError(
        domain: "IMAGE_PROCESSING_ERROR",
        code: 0,
        userInfo: [NSLocalizedDescriptionKey: "Failed to create image from data"]
      )
    }

    delegate?.logging(
      self,
      message: "Original image: \(Int(originalImage.size.width))x\(Int(originalImage.size.height))"
    )

    return try processImage(originalImage)
  }

  private func processImage(_ originalImage: UIImage) throws -> UIImage {
    let targetSize: CGFloat = 256
    let originalWidth = originalImage.size.width
    let originalHeight = originalImage.size.height

    if originalWidth < targetSize || originalHeight < targetSize {
      delegate?.logging(
        self,
        message: "Image dimensions (\(Int(originalWidth))x\(Int(originalHeight))) are smaller than target size (\(Int(targetSize))x\(Int(targetSize))). Skipping processing."
      )
      return originalImage
    }

    let scaleFactor = targetSize / min(originalWidth, originalHeight)
    let scaledWidth = originalWidth * scaleFactor
    let scaledHeight = originalHeight * scaleFactor
    let scaledSize = CGSize(width: scaledWidth, height: scaledHeight)

    UIGraphicsBeginImageContextWithOptions(scaledSize, false, 1.0)
    defer { UIGraphicsEndImageContext() }

    originalImage.draw(in: CGRect(origin: .zero, size: scaledSize))
    guard let scaledImage = UIGraphicsGetImageFromCurrentImageContext() else {
      throw NSError(
        domain: "IMAGE_PROCESSING_ERROR",
        code: 0,
        userInfo: [NSLocalizedDescriptionKey: "Failed to downsample image"]
      )
    }

    delegate?.logging(
      self,
      message: "Downsampled image from \(Int(originalWidth))x\(Int(originalHeight)) to \(Int(scaledWidth))x\(Int(scaledHeight))"
    )

    let cropX = (scaledWidth - targetSize) / 2
    let cropY = (scaledHeight - targetSize) / 2
    let cropRect = CGRect(x: cropX, y: cropY, width: targetSize, height: targetSize)

    guard let cgImage = scaledImage.cgImage?.cropping(to: cropRect) else {
      throw NSError(
        domain: "IMAGE_PROCESSING_ERROR",
        code: 0,
        userInfo: [NSLocalizedDescriptionKey: "Failed to crop image"]
      )
    }

    let croppedImage = UIImage(cgImage: cgImage)

    delegate?.logging(
      self,
      message: "Cropped image to \(Int(targetSize))x\(Int(targetSize)) from center"
    )

    return croppedImage
  }

  func close() {
    currentSession = nil
    inference = nil
  }
}