// LlmInferenceModule.swift
import Foundation
import React

@objc(LlmInferenceModule)
class LlmInferenceModule: RCTEventEmitter {
  private var nextHandle = 1
  private var modelMap = [Int: LlmInferenceModel]()

  override func supportedEvents() -> [String]! {
    return ["logging", "onPartialResponse", "onErrorResponse"]
  }

  override static func requiresMainQueueSetup() -> Bool { true }

  @objc func createModel(
    _ modelPath: String,
    maxTokens: Int,
    topK: Int,
    temperature: NSNumber,
    randomSeed: Int,
    enableVisionModality: Bool,
    preferGpuBackend: Bool,
    resolve: @escaping RCTPromiseResolveBlock,
    reject: @escaping RCTPromiseRejectBlock
  ) {
    let handle = nextHandle
    nextHandle += 1

    do {
      let model = try LlmInferenceModel(
        handle: handle,
        modelPath: modelPath,
        maxTokens: maxTokens,
        topK: topK,
        temperature: temperature.floatValue,
        randomSeed: randomSeed,
        enableVisionModality: enableVisionModality,
        preferGpuBackend: preferGpuBackend
      )
      model.delegate = self
      modelMap[handle] = model
      resolve(handle)
    } catch {
      reject("CREATE_FAILED", "Failed to load model: \(error.localizedDescription)", error)
    }
  }

  @objc func createModelFromAsset(
    _ modelName: String,
    maxTokens: Int,
    topK: Int,
    temperature: NSNumber,
    randomSeed: Int,
    enableVisionModality: Bool,
    preferGpuBackend: Bool,
    resolve: @escaping RCTPromiseResolveBlock,
    reject: @escaping RCTPromiseRejectBlock
  ) {
    let fileURL = URL(fileURLWithPath: modelName)
    let basename = fileURL.deletingPathExtension().lastPathComponent
    let fileExtension = fileURL.pathExtension

    guard let path = Bundle.main.path(forResource: basename, ofType: fileExtension) ??
      Bundle.main.path(forResource: modelName, ofType: nil)
    else {
      reject("ASSET_NOT_FOUND", "Model asset not found: \(modelName)", nil)
      return
    }
    createModel(path, maxTokens: maxTokens, topK: topK, temperature: temperature, randomSeed: randomSeed,
                enableVisionModality: enableVisionModality, preferGpuBackend: preferGpuBackend,
                resolve: resolve, reject: reject)
  }

  @objc func releaseModel(_ handle: Int, resolve: RCTPromiseResolveBlock, reject: RCTPromiseRejectBlock) {
    if let model = modelMap.removeValue(forKey: handle) {
      model.close()
      resolve(true)
    } else {
      reject("INVALID_HANDLE", "No model with handle \(handle)", nil)
    }
  }

  @objc func generateResponse(_ handle: Int, requestId: Int, prompt: String,
                              resolve: @escaping RCTPromiseResolveBlock, reject: @escaping RCTPromiseRejectBlock) {
    guard let model = modelMap[handle] else {
      reject("INVALID_HANDLE", "No model", nil); return
    }
    model.generateResponse(prompt: prompt, requestId: requestId, resolve: resolve, reject: reject)
  }

  @objc func generateResponseWithImage(_ handle: Int, requestId: Int, prompt: String, imageBase64: String?,
                                       resolve: @escaping RCTPromiseResolveBlock, reject: @escaping RCTPromiseRejectBlock) {
    guard let model = modelMap[handle] else {
      reject("INVALID_HANDLE", "No model", nil); return
    }
    model.generateResponseWithImage(prompt: prompt, requestId: requestId, imageBase64: imageBase64, resolve: resolve, reject: reject)
  }

  @objc func getMemoryStats(resolve: RCTPromiseResolveBlock, reject: RCTPromiseRejectBlock) {
    var info = mach_task_basic_info()
    var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size)/4
    let kerr: kern_return_t = withUnsafeMutablePointer(to: &info) {
      $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
        task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
      }
    }
    
    if kerr == KERN_SUCCESS {
      let usedMB = Double(info.resident_size) / 1024.0 / 1024.0
      resolve([
        "availSysRamMB": 0,
        "totalSysRamMB": 0,
        "heapMaxMB": 0,
        "heapAllocatedMB": usedMB,
        "heapFreeMB": 0,
        "lowMemory": false
      ])
    } else {
      reject("MEMORY_ERROR", "Failed to get memory stats", nil)
    }
  }
}

extension LlmInferenceModule: LlmInferenceModelDelegate {
  func logging(_ model: LlmInferenceModel, message: String) {
    sendEvent(withName: "logging", body: ["handle": model.handle, "message": message])
  }
  func onPartialResponse(_ model: LlmInferenceModel, requestId: Int, response: String) {
    sendEvent(withName: "onPartialResponse", body: ["handle": model.handle, "requestId": requestId, "response": response])
  }
  func onErrorResponse(_ model: LlmInferenceModel, requestId: Int, error: String) {
    sendEvent(withName: "onErrorResponse", body: ["handle": model.handle, "requestId": requestId, "error": error])
  }
}