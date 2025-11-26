// LlmInferenceModel.swift
import Foundation
import UIKit

protocol LlmInferenceModelDelegate: AnyObject {
  func logging(_ model: LlmInferenceModel, message: String)
  func onPartialResponse(_ model: LlmInferenceModel, requestId: Int, response: String)
  func onErrorResponse(_ model: LlmInferenceModel, requestId: Int, error: String)
}

final class LlmInferenceModel {
  weak var delegate: LlmInferenceModelDelegate?

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

    delegate?.logging(self, message: "MLX not available - model loading disabled")
  }

  func generateResponse(
    prompt: String,
    requestId: Int,
    resolve: @escaping RCTPromiseResolveBlock,
    reject: @escaping RCTPromiseRejectBlock
  ) {
    reject("NOT_IMPLEMENTED", "MLX inference not available", nil)
  }

  func generateResponseWithImage(
    prompt: String,
    requestId: Int,
    imageBase64: String?,
    resolve: @escaping RCTPromiseResolveBlock,
    reject: @escaping RCTPromiseRejectBlock
  ) {
    reject("NOT_IMPLEMENTED", "MLX inference not available", nil)
  }

  func close() {
    // Nothing to clean up
  }
}