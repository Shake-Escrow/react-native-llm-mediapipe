// LlmInferenceModel.swift
import Foundation
import MLX
import MLXLLM
import MLXVision
import UIKit

protocol LlmInferenceModelDelegate: AnyObject {
  func logging(_ model: LlmInferenceModel, message: String)
  func onPartialResponse(_ model: LlmInferenceModel, requestId: Int, response: String)
  func onErrorResponse(_ model: LlmInferenceModel, requestId: Int, error: String)
}

final class LlmInferenceModel {
  weak var delegate: LlmInferenceModelDelegate?

  private var generator: LLMLocalModel?
  private var visionProcessor: VisionProcessor?

  let handle: Int
  private let maxTokens: Int
  private let topK: Int
  private let temperature: Float
  private let randomSeed: Int
  private let enableVisionModality: Bool

  init(
    handle: Int,
    modelPath: String,
    maxTokens: Int,
    topK: Int,
    temperature: Float,
    randomSeed: Int,
    enableVisionModality: Bool
  ) throws {
    self.handle = handle
    self.maxTokens = maxTokens
    self.topK = topK
    self.temperature = temperature
    self.randomSeed = randomSeed
    self.enableVisionModality = enableVisionModality

    try loadModel(from: modelPath)
  }

  private func loadModel(from path: String) throws {
    delegate?.logging(self, message: "Loading MLX model from: \(path)")

    let config = try LLMModelConfiguration.from(yamlAt: URL(fileURLWithPath: path + "/config.yaml"))
    
    let generator = try LLMLocalModel(
      configuration: config,
      weightsAt: URL(fileURLWithPath: path),
      load: { progress in
        self.delegate?.logging(self, message: "Loading weights: \(Int(progress * 100))%")
      }
    )

    if enableVisionModality {
      visionProcessor = try VisionProcessor(model: generator)
      delegate?.logging(self, message: "Vision modality enabled (MLX-Vision)")
    }

    self.generator = generator
    delegate?.logging(self, message: "MLX model loaded successfully")
  }

  func generateResponse(
    prompt: String,
    requestId: Int,
    resolve: @escaping RCTPromiseResolveBlock,
    reject: @escaping RCTPromiseRejectBlock
  ) {
    generateResponseWithImage(prompt: prompt, requestId: requestId, imageBase64: nil, resolve: resolve, reject: reject)
  }

  func generateResponseWithImage(
    prompt: String,
    requestId: Int,
    imageBase64: String?,
    resolve: @escaping RCTPromiseResolveBlock,
    reject: @escaping RCTPromiseRejectBlock
  ) {
    guard let generator = self.generator else {
      reject("MODEL_NOT_LOADED", "MLX model not loaded", nil)
      return
    }

    Task {
      do {
        var fullResponse = ""

        let generateParams = GenerateParameters(
          temperature: self.temperature,
          topK: self.topK,
          maxTokens: self.maxTokens,
          seed: UInt64(self.randomSeed)
        )

        var image: MLX.Array? = nil
        if let imageBase64 = imageBase64, enableVisionModality, let visionProcessor = visionProcessor {
          image = try await processImage(base64: imageBase64, using: visionProcessor)
        }

        let stream = try await generator.generate(
          prompt: prompt,
          image: image,
          parameters: generateParams
        ) { token in
          fullResponse += token
          await MainActor.run {
            self.delegate?.onPartialResponse(self, requestId: requestId, response: fullResponse)
          }
          return .continue
        }

        var finalResponse = ""
        for try await token in stream {
          finalResponse += token
        }

        await MainActor.run {
          resolve(finalResponse)
        }
      } catch {
        let msg = error.localizedDescription
        await MainActor.run {
          self.delegate?.onErrorResponse(self, requestId: requestId, error: msg)
          reject("GENERATE_ERROR", msg, error)
        }
      }
    }
  }

  private func processImage(base64: String, using processor: VisionProcessor) async throws -> MLX.Array {
    let data = Data(base64Encoded: base64.contains(",") ? String(base64.split(separator: ",")[1]) : base64)!
    guard let uiImage = UIImage(data: data) else {
      throw NSError(domain: "IMAGE_ERROR", code: 0, userInfo: [NSLocalizedDescriptionKey: "Invalid image"])
    }
    return try await processor.encode(uiImage)
  }

  func close() {
    generator = nil
    visionProcessor = nil
  }
}