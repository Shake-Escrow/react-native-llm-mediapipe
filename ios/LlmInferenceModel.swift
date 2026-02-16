// LlmInferenceModel.swift
// iOS implementation using MLX Swift for on-device LLM inference
// This provides a platform-specific implementation that matches the Android MediaPipe interface

import Foundation
import UIKit
import MLX
import MLXLM // MLX Language Model utilities
import MLXRandom

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
  private let preferGpuBackend: Bool
  
  // MLX components - using MLX-LM's built-in model loading
  private var modelContainer: MLXLM.ModelContainer?
  private let modelPath: String
  
  // Queue for inference operations
  private let inferenceQueue = DispatchQueue(label: "com.llmmediapipe.inference", qos: .userInitiated)
  
  // Track current generation for cancellation
  private var currentGenerationTask: Task<Void, Never>?

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

    delegate?.logging(self, message: "Initializing MLX model from path: \(modelPath)")
    
    // Vision modality not yet supported in this implementation
    if enableVisionModality {
      delegate?.logging(self, message: "Warning: Vision modality not yet implemented for iOS/MLX")
    }
    
    // Metal/GPU is the default backend for MLX on Apple Silicon
    if preferGpuBackend {
      delegate?.logging(self, message: "Using Metal GPU backend (MLX default)")
    } else {
      delegate?.logging(self, message: "Note: MLX always uses Metal when available")
    }
    
    // Load the model
    try loadModel()
  }
  
  private func loadModel() throws {
    // Check if path exists
    let fileManager = FileManager.default
    guard fileManager.fileExists(atPath: modelPath) else {
      throw NSError(
        domain: "LlmInferenceModel",
        code: 404,
        userInfo: [NSLocalizedDescriptionKey: "Model directory not found at path: \(modelPath)"]
      )
    }
    
    delegate?.logging(self, message: "Loading MLX model from: \(modelPath)")
    
    do {
      let modelURL = URL(fileURLWithPath: modelPath)
      
      // Use MLXLM's built-in model loading
      // This handles model detection, tokenizer loading, and weight loading automatically
      let configuration = MLXLM.ModelConfiguration(
        modelDirectory: modelURL,
        computeUnits: preferGpuBackend ? .all : .cpuOnly
      )
      
      modelContainer = try MLXLM.ModelContainer.load(configuration: configuration)
      
      delegate?.logging(self, message: "MLX model loaded successfully")
      delegate?.logging(self, message: "Model type: \(modelContainer?.modelType ?? "unknown")")
      
    } catch {
      delegate?.logging(self, message: "Failed to load model: \(error.localizedDescription)")
      throw NSError(
        domain: "LlmInferenceModel",
        code: 500,
        userInfo: [NSLocalizedDescriptionKey: "Model loading failed: \(error.localizedDescription)"]
      )
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
    guard let modelContainer = modelContainer else {
      reject("MODEL_NOT_LOADED", "Model not loaded", nil)
      return
    }
    
    if imageBase64 != nil && !enableVisionModality {
      reject("VISION_NOT_ENABLED", "Vision modality not enabled for this model", nil)
      return
    }
    
    if imageBase64 != nil {
      reject("VISION_NOT_IMPLEMENTED", "Vision modality not yet implemented for iOS/MLX", nil)
      return
    }
    
    // Cancel any existing generation
    currentGenerationTask?.cancel()
    
    // Create generation configuration
    let generateParameters = MLXLM.GenerateParameters(
      temperature: temperature,
      topK: topK,
      maxTokens: maxTokens,
      randomSeed: randomSeed > 0 ? UInt64(randomSeed) : nil
    )
    
    delegate?.logging(self, message: "Starting generation for request \(requestId)")
    
    // Run generation asynchronously
    currentGenerationTask = Task { [weak self] in
      guard let self = self else { return }
      
      var accumulatedText = ""
      
      do {
        // Use MLX-LM's streaming generation
        for try await token in modelContainer.generate(
          prompt: prompt,
          parameters: generateParameters
        ) {
          // Check for cancellation
          if Task.isCancelled {
            self.delegate?.logging(self, message: "Generation cancelled for request \(requestId)")
            break
          }
          
          accumulatedText += token.text
          
          // Send partial response to React Native
          DispatchQueue.main.async {
            self.delegate?.onPartialResponse(self, requestId: requestId, response: accumulatedText)
          }
        }
        
        self.delegate?.logging(self, message: "Generation completed for request \(requestId)")
        
        // Resolve with final text
        DispatchQueue.main.async {
          resolve(accumulatedText)
        }
        
      } catch {
        let errorMessage = "Generation failed: \(error.localizedDescription)"
        self.delegate?.logging(self, message: errorMessage)
        
        DispatchQueue.main.async {
          self.delegate?.onErrorResponse(self, requestId: requestId, error: errorMessage)
          reject("GENERATION_ERROR", errorMessage, error)
        }
      }
    }
  }

  func close() {
    delegate?.logging(self, message: "Closing model handle \(handle)")
    
    // Cancel any running generation
    currentGenerationTask?.cancel()
    currentGenerationTask = nil
    
    // Release model resources
    modelContainer = nil
  }
}
