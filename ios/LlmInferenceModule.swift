//
//  LlmInferenceModule.swift
//  rnllm
//
//  Created by Charles Parker on 4/20/24.
//

import Foundation
import React

@objc(LlmInferenceModule)
class LlmInferenceModule: RCTEventEmitter {
  private var nextHandle = 1
  var modelMap = [Int: LlmInferenceModel]()

  override func supportedEvents() -> [String]! {
    return ["logging", "onPartialResponse", "onErrorResponse"]
  }

  override static func requiresMainQueueSetup() -> Bool {
    return true
  }

  @objc(
    createModel:withMaxTokens:withTopK:withTemperature:withRandomSeed:withEnableVisionModality:withPreferGpuBackend:resolver:rejecter:
  )
  func createModel(
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
    os_log("createModel IS CALLED")
    let modelHandle = nextHandle
    nextHandle += 1

    do {
      let model = try LlmInferenceModel(
        handle: modelHandle,
        modelPath: modelPath,
        maxTokens: maxTokens,
        topK: topK,
        temperature: temperature.floatValue,
        randomSeed: randomSeed,
        enableVisionModality: enableVisionModality,
        preferGpuBackend: preferGpuBackend
      )
      model.delegate = self
      modelMap[modelHandle] = model
      resolve(modelHandle)
    } catch let error as NSError {
      reject(error.domain, "Model Creation Failed: \(error.localizedDescription)", error)
    }
  }

  @objc(
    createModelFromAsset:withMaxTokens:withTopK:withTemperature:withRandomSeed:withEnableVisionModality:withPreferGpuBackend:resolver:rejecter:
  )
  func createModelFromAsset(
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
    os_log("createModelFromAsset IS CALLED")
    let modelHandle = nextHandle
    nextHandle += 1

    do {
      let fileURL = URL(fileURLWithPath: modelName)
      let basename = fileURL.deletingPathExtension().lastPathComponent
      let fileExtension = fileURL.pathExtension
      
      guard let modelPath = Bundle.main.path(forResource: basename, ofType: fileExtension) else {
        throw NSError(
          domain: "MODEL_NOT_FOUND",
          code: 0,
          userInfo: [NSLocalizedDescriptionKey: "Model \(modelName) not found"]
        )
      }
      
      let model = try LlmInferenceModel(
        handle: modelHandle,
        modelPath: modelPath,
        maxTokens: maxTokens,
        topK: topK,
        temperature: temperature.floatValue,
        randomSeed: randomSeed,
        enableVisionModality: enableVisionModality,
        preferGpuBackend: preferGpuBackend
      )
      model.delegate = self
      modelMap[modelHandle] = model
      resolve(modelHandle)
    } catch let error as NSError {
      reject(error.domain, "Model Creation Failed: \(error.localizedDescription)", error)
    }
  }

  @objc(releaseModel:resolver:rejecter:)
  func releaseModel(
    _ handle: Int,
    resolve: @escaping RCTPromiseResolveBlock,
    reject: @escaping RCTPromiseRejectBlock
  ) {
    if let model = modelMap.removeValue(forKey: handle) {
      model.close()
      resolve(true)
    } else {
      reject("INVALID_HANDLE", "No model found for handle \(handle)", nil)
    }
  }

  @objc(
    generateResponse:withRequestId:withPrompt:resolver:rejecter:
  )
  func generateResponse(
    _ handle: Int,
    requestId: Int,
    prompt: String,
    resolve: @escaping RCTPromiseResolveBlock,
    reject: @escaping RCTPromiseRejectBlock
  ) {
    os_log("generateResponse IS CALLED")
    if let model = modelMap[handle] {
      model.generateResponse(
        prompt: prompt,
        requestId: requestId,
        resolve: resolve,
        reject: reject
      )
    } else {
      reject("INVALID_HANDLE", "No model found for handle \(handle)", nil)
    }
  }

  @objc(
    generateResponseWithImage:withRequestId:withPrompt:withImageBase64:resolver:rejecter:
  )
  func generateResponseWithImage(
    _ handle: Int,
    requestId: Int,
    prompt: String,
    imageBase64: String?,
    resolve: @escaping RCTPromiseResolveBlock,
    reject: @escaping RCTPromiseRejectBlock
  ) {
    os_log("generateResponseWithImage IS CALLED")
    if let model = modelMap[handle] {
      model.generateResponseWithImage(
        prompt: prompt,
        requestId: requestId,
        imageBase64: imageBase64,
        resolve: resolve,
        reject: reject
      )
    } else {
      reject("INVALID_HANDLE", "No model found for handle \(handle)", nil)
    }
  }

  @objc(getMemoryStats:rejecter:)
  func getMemoryStats(
    resolve: @escaping RCTPromiseResolveBlock,
    reject: @escaping RCTPromiseRejectBlock
  ) {
    do {
      var stats: [String: Any] = [:]

      // System memory stats
      var vmStats = vm_statistics64()
      var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)
      
      let result = withUnsafeMutablePointer(to: &vmStats) {
        $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
          host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
        }
      }
      
      if result == KERN_SUCCESS {
        let pageSize = vm_kernel_page_size
        let totalMemory = ProcessInfo.processInfo.physicalMemory
        let freeMemory = UInt64(vmStats.free_count) * UInt64(pageSize)
        let activeMemory = UInt64(vmStats.active_count) * UInt64(pageSize)
        let inactiveMemory = UInt64(vmStats.inactive_count) * UInt64(pageSize)
        let wiredMemory = UInt64(vmStats.wire_count) * UInt64(pageSize)
        
        let availableMemory = freeMemory + inactiveMemory
        let usedMemory = activeMemory + wiredMemory
        
        let totalSysRamMB = Int(totalMemory / (1024 * 1024))
        let availSysRamMB = Int(availableMemory / (1024 * 1024))
        
        // Determine low memory condition (less than 10% available)
        let lowMemory = availSysRamMB < (totalSysRamMB / 10)
        
        stats["totalSysRamMB"] = totalSysRamMB
        stats["availSysRamMB"] = availSysRamMB
        stats["lowMemory"] = lowMemory
      }

      // App memory stats (heap equivalent)
      var taskInfo = mach_task_basic_info()
      var taskInfoCount = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size / MemoryLayout<natural_t>.size)
      
      let taskResult = withUnsafeMutablePointer(to: &taskInfo) {
        $0.withMemoryRebound(to: integer_t.self, capacity: Int(taskInfoCount)) {
          task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &taskInfoCount)
        }
      }
      
      if taskResult == KERN_SUCCESS {
        let residentSize = taskInfo.resident_size
        let heapAllocatedMB = Int(residentSize / (1024 * 1024))
        
        // iOS doesn't have direct heap max/free equivalents like JVM
        // We'll use app memory limit as a proxy for max heap
        let appMemoryLimit = ProcessInfo.processInfo.physicalMemory / 6 // Rough estimate: 1/6 of physical memory
        let heapMaxMB = Int(appMemoryLimit / (1024 * 1024))
        let heapFreeMB = heapMaxMB - heapAllocatedMB
        
        stats["heapMaxMB"] = heapMaxMB
        stats["heapAllocatedMB"] = heapAllocatedMB
        stats["heapFreeMB"] = max(0, heapFreeMB)
      }

      resolve(stats)
    } catch {
      reject("MEMORY_STATS_ERROR", "Failed to get memory stats: \(error.localizedDescription)", error)
    }
  }

  // Required for RN built-in Event Emitter Calls
  @objc override func addListener(_ eventName: String!) {
    super.addListener(eventName)
  }

  @objc override func removeListeners(_ count: Double) {
    super.removeListeners(count)
  }

  private func sendLoggingEvent(handle: Int, message: String) {
    self.sendEvent(withName: "logging", body: ["handle": handle, "message": message])
  }
  
  private func sendPartialResponseEvent(handle: Int, requestId: Int, response: String) {
    self.sendEvent(
      withName: "onPartialResponse",
      body: ["handle": handle, "requestId": requestId, "response": response]
    )
  }
  
  private func sendErrorResponseEvent(handle: Int, requestId: Int, error: String) {
    self.sendEvent(
      withName: "onErrorResponse",
      body: ["handle": handle, "requestId": requestId, "error": error]
    )
  }
}

extension LlmInferenceModule: LlmInferenceModelDelegate {
  func logging(_ model: LlmInferenceModel, message: String) {
    self.sendLoggingEvent(handle: model.handle, message: message)
  }
  
  func onPartialResponse(_ model: LlmInferenceModel, requestId: Int, response: String) {
    self.sendPartialResponseEvent(handle: model.handle, requestId: requestId, response: response)
  }
  
  func onErrorResponse(_ model: LlmInferenceModel, requestId: Int, error: String) {
    self.sendErrorResponseEvent(handle: model.handle, requestId: requestId, error: error)
  }
}