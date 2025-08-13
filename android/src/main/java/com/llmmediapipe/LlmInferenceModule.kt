package com.llmmediapipe

import android.app.ActivityManager
import android.content.Context
import com.facebook.react.bridge.Arguments
import com.facebook.react.bridge.Promise
import com.facebook.react.bridge.ReactApplicationContext
import com.facebook.react.bridge.ReactContextBaseJavaModule
import com.facebook.react.bridge.ReactMethod
import com.facebook.react.bridge.WritableMap
import com.facebook.react.modules.core.DeviceEventManagerModule
import java.io.File
import java.io.FileOutputStream

class LlmInferenceModule(private val reactContext: ReactApplicationContext) :
  ReactContextBaseJavaModule(reactContext) {

  private var nextHandle = 1
  private val modelMap = mutableMapOf<Int, LlmInferenceModel>()

  override fun getName(): String {
    return "LlmInferenceModule"
  }

  private class InferenceModelListener(
    private val module: LlmInferenceModule,
    private val handle: Int
  ) : InferenceListener {
    override fun logging(model: LlmInferenceModel, message: String) {
      module.emitEvent(
        "logging",
        Arguments.createMap().apply {
          this.putInt("handle", this@InferenceModelListener.handle)
          this.putString("message", message)
        }
      )
    }

    override fun onError(model: LlmInferenceModel, requestId: Int, error: String) {
      module.emitEvent(
        "onErrorResponse",
        Arguments.createMap().apply {
          this.putInt("handle", this@InferenceModelListener.handle)
          this.putInt("requestId", requestId)
          this.putString("error", error)
        }
      )
    }

    override fun onResults(model: LlmInferenceModel, requestId: Int, response: String) {
      module.emitEvent(
        "onPartialResponse",
        Arguments.createMap().apply {
          this.putInt("handle", this@InferenceModelListener.handle)
          this.putInt("requestId", requestId)
          this.putString("response", response)
        }
      )
    }
  }

  @ReactMethod
  fun createModel(
    modelPath: String,
    maxTokens: Int,
    topK: Int,
    temperature: Double,
    randomSeed: Int,
    enableVisionModality: Boolean,
    preferGpuBackend: Boolean, // New parameter
    promise: Promise
  ) {
    try {
      val modelHandle = nextHandle++
      val model =
        LlmInferenceModel(
          this.reactContext,
          modelPath,
          maxTokens,
          topK,
          temperature.toFloat(),
          randomSeed,
          enableVisionModality,
          preferGpuBackend, // Pass the new parameter
          inferenceListener = InferenceModelListener(this, modelHandle)
        )
      modelMap[modelHandle] = model
      promise.resolve(modelHandle)
    } catch (e: Exception) {
      promise.reject("Model Creation Failed", e.localizedMessage)
    }
  }

  @ReactMethod
  fun createModelFromAsset(
    modelName: String,
    maxTokens: Int,
    topK: Int,
    temperature: Double,
    randomSeed: Int,
    enableVisionModality: Boolean,
    preferGpuBackend: Boolean, // New parameter
    promise: Promise
  ) {
    try {
      val modelPath = copyFileToInternalStorageIfNeeded(modelName, this.reactContext).path

      val modelHandle = nextHandle++
      val model =
        LlmInferenceModel(
          this.reactContext,
          modelPath,
          maxTokens,
          topK,
          temperature.toFloat(),
          randomSeed,
          enableVisionModality,
          preferGpuBackend, // Pass the new parameter
          inferenceListener = InferenceModelListener(this, modelHandle)
        )
      modelMap[modelHandle] = model
      promise.resolve(modelHandle)
    } catch (e: Exception) {
      promise.reject("Model Creation Failed", e.localizedMessage)
    }
  }

  @ReactMethod
  fun releaseModel(handle: Int, promise: Promise) {
    modelMap[handle]?.let { 
      it.close() // Clean up any open sessions
      modelMap.remove(handle)
      promise.resolve(true) 
    } ?: promise.reject("INVALID_HANDLE", "No model found for handle $handle")
  }

  @ReactMethod
  fun generateResponse(handle: Int, requestId: Int, prompt: String, promise: Promise) {
    modelMap[handle]?.let { it.generateResponseAsync(requestId, prompt, promise) }
      ?: promise.reject("INVALID_HANDLE", "No model found for handle $handle")
  }

  @ReactMethod
  fun generateResponseWithImage(handle: Int, requestId: Int, prompt: String, imageBase64: String?, promise: Promise) {
    modelMap[handle]?.let { it.generateResponseWithImageAsync(requestId, prompt, imageBase64, promise) }
      ?: promise.reject("INVALID_HANDLE", "No model found for handle $handle")
  }

  @ReactMethod
  fun getMemoryStats(promise: Promise) {
    try {
      val activityManager = reactContext.getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
      val memoryInfo = ActivityManager.MemoryInfo()
      activityManager.getMemoryInfo(memoryInfo)

      // System memory stats
      val totalSysRamMB = (memoryInfo.totalMem / (1024 * 1024)).toInt()
      val availSysRamMB = (memoryInfo.availMem / (1024 * 1024)).toInt()
      val lowMemory = memoryInfo.lowMemory

      // Runtime (heap) memory stats
      val runtime = Runtime.getRuntime()
      val maxHeapBytes = runtime.maxMemory()
      val totalHeapBytes = runtime.totalMemory()
      val freeHeapBytes = runtime.freeMemory()
      val usedHeapBytes = totalHeapBytes - freeHeapBytes

      val heapMaxMB = (maxHeapBytes / (1024 * 1024)).toInt()
      val heapAllocatedMB = (usedHeapBytes / (1024 * 1024)).toInt()
      val heapFreeMB = ((maxHeapBytes - usedHeapBytes) / (1024 * 1024)).toInt()

      val stats = Arguments.createMap().apply {
        putInt("availSysRamMB", availSysRamMB)
        putInt("totalSysRamMB", totalSysRamMB)
        putInt("heapMaxMB", heapMaxMB)
        putInt("heapAllocatedMB", heapAllocatedMB)
        putInt("heapFreeMB", heapFreeMB)
        putBoolean("lowMemory", lowMemory)
      }

      promise.resolve(stats)
    } catch (e: Exception) {
      promise.reject("MEMORY_STATS_ERROR", "Failed to get memory stats: ${e.localizedMessage}")
    }
  }

  @ReactMethod
  fun addListener(eventName: String?) {
    /* Required for RN built-in Event Emitter Calls. */
  }

  @ReactMethod
  fun removeListeners(count: Int?) {
    /* Required for RN built-in Event Emitter Calls. */
  }

  private fun copyFileToInternalStorageIfNeeded(modelName: String, context: Context): File {
    val outputFile = File(context.filesDir, modelName)

    // Check if the file already exists
    if (outputFile.exists()) {
      // The file already exists, no need to copy again
      return outputFile
    }

    val assetList =
      context.assets.list(
        ""
      ) // List all files in the assets root (""), adjust if your file is in a subfolder
    if (modelName !in assetList.orEmpty()) {
      throw IllegalArgumentException("Asset file ${modelName} does not exist.")
    }
    // File doesn't exist, proceed with copying
    context.assets.open(modelName).use { inputStream ->
      FileOutputStream(outputFile).use { outputStream -> inputStream.copyTo(outputStream) }
    }

    return outputFile
  }

  private fun emitEvent(eventName: String, eventData: WritableMap) {
    reactContext
      .getJSModule(DeviceEventManagerModule.RCTDeviceEventEmitter::class.java)
      .emit(eventName, eventData)
  }
}