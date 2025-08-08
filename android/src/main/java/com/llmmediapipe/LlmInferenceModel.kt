package com.llmmediapipe

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Matrix
import com.facebook.react.bridge.Promise
import com.google.mediapipe.framework.image.BitmapImageBuilder
import com.google.mediapipe.framework.image.MPImage
import com.google.mediapipe.tasks.genai.llminference.LlmInference
import com.google.mediapipe.tasks.genai.llminference.LlmInferenceSession
import com.google.mediapipe.tasks.core.GraphOptions
import java.io.File
import java.io.FileOutputStream
import java.io.InputStream
import android.util.Base64
import kotlin.math.min

class LlmInferenceModel(
        private var context: Context,
        private val modelPath: String,
        val maxTokens: Int,
        val topK: Int,
        val temperature: Float,
        val randomSeed: Int,
        val enableVisionModality: Boolean = false,
        val inferenceListener: InferenceListener? = null,
) {
    private var llmInference: LlmInference
    private var currentSession: LlmInferenceSession? = null

    private val modelExists: Boolean
        get() = modelPath != null && File(modelPath).exists()

    // so we cannot have concurrent requests
    private var requestId: Int = 0
    private var requestResult: String = ""
    private var requestPromise: Promise? = null

    init {
        val optionsBuilder = LlmInference.LlmInferenceOptions.builder()
                .setModelPath(modelPath)
                .setMaxTokens(maxTokens)
                .setTopK(topK)
                .setTemperature(temperature)
                .setRandomSeed(randomSeed)

        if (enableVisionModality) {
            optionsBuilder.setMaxNumImages(1)
        }

        val options = optionsBuilder.build()

        llmInference = LlmInference.createFromOptions(context, options)
    }

    fun generateResponseAsync(requestId: Int, prompt: String, promise: Promise) {
        generateResponseWithImageAsync(requestId, prompt, null, promise)
    }

    fun generateResponseWithImageAsync(requestId: Int, prompt: String, imageBase64: String?, promise: Promise) {
        this.requestId = requestId
        this.requestResult = ""
        this.requestPromise = promise

        try {
            // Close previous session if exists
            currentSession?.close()

            // Create session options
            val sessionOptionsBuilder = LlmInferenceSession.LlmInferenceSessionOptions.builder()
                    .setTopK(topK)
                    .setTemperature(temperature)

            if (enableVisionModality) {
                sessionOptionsBuilder.setGraphOptions(
                    GraphOptions.builder().setEnableVisionModality(true).build()
                )
            }

            val sessionOptions = sessionOptionsBuilder.build()

            // Create new session
            currentSession = LlmInferenceSession.createFromOptions(llmInference, sessionOptions)

            // Set up result listener for the session
            currentSession?.setResultListener { partialResult, done ->
                inferenceListener?.onResults(this, requestId, partialResult)
                requestResult += partialResult
                if (done) {
                    requestPromise?.resolve(requestResult)
                    currentSession?.close()
                    currentSession = null
                }
            }

            currentSession?.setErrorListener { ex ->
                inferenceListener?.onError(this, requestId, ex.message ?: "")
                requestPromise?.reject("INFERENCE_ERROR", ex.message ?: "Unknown error")
                currentSession?.close()
                currentSession = null
            }

            // Add text prompt
            currentSession?.addQueryChunk(prompt)

            // Add image if provided
            if (imageBase64 != null && enableVisionModality) {
                val image = base64ToMPImage(imageBase64)
                currentSession?.addImage(image)
            }

            // Generate response
            currentSession?.generateResponseAsync()

        } catch (e: Exception) {
            inferenceListener?.onError(this, requestId, e.message ?: "")
            requestPromise?.reject("INFERENCE_ERROR", e.message ?: "Unknown error")
            currentSession?.close()
            currentSession = null
        }
    }

    private fun base64ToMPImage(base64String: String): MPImage {
        // Remove data URL prefix if present (e.g., "data:image/jpeg;base64,")
        val base64Data = if (base64String.contains(",")) {
            base64String.split(",")[1]
        } else {
            base64String
        }

        // Decode base64 to byte array
        val imageBytes = Base64.decode(base64Data, Base64.DEFAULT)
        
        // Convert to Bitmap
        val bitmap = BitmapFactory.decodeByteArray(imageBytes, 0, imageBytes.size)
            ?: throw IllegalArgumentException("Failed to decode image from base64")

        // Process the image: downsample and crop to 256x256
        val processedBitmap = processImage(bitmap)

        // Convert processed Bitmap to MPImage
        return BitmapImageBuilder(processedBitmap).build()
    }

    private fun processImage(originalBitmap: Bitmap): Bitmap {
        val targetSize = 256
        val originalWidth = originalBitmap.width
        val originalHeight = originalBitmap.height

        // Skip processing if either dimension is less than 256 pixels
        if (originalWidth < targetSize || originalHeight < targetSize) {
            inferenceListener?.logging(this, "Image dimensions (${originalWidth}x${originalHeight}) are smaller than target size (${targetSize}x${targetSize}). Skipping processing.")
            return originalBitmap
        }

        // Step 1: Downsample the image
        // Calculate the scale factor to make the smaller dimension equal to targetSize
        val scaleFactor = targetSize.toFloat() / min(originalWidth, originalHeight)
        val scaledWidth = (originalWidth * scaleFactor).toInt()
        val scaledHeight = (originalHeight * scaleFactor).toInt()

        val scaledBitmap = Bitmap.createScaledBitmap(originalBitmap, scaledWidth, scaledHeight, true)
        
        inferenceListener?.logging(this, "Downsampled image from ${originalWidth}x${originalHeight} to ${scaledWidth}x${scaledHeight}")

        // Step 2: Crop to 256x256 from the center
        val cropX = (scaledWidth - targetSize) / 2
        val cropY = (scaledHeight - targetSize) / 2

        val croppedBitmap = Bitmap.createBitmap(scaledBitmap, cropX, cropY, targetSize, targetSize)
        
        inferenceListener?.logging(this, "Cropped image to ${targetSize}x${targetSize} from center")

        // Clean up intermediate bitmap
        if (scaledBitmap != originalBitmap && scaledBitmap != croppedBitmap) {
            scaledBitmap.recycle()
        }

        return croppedBitmap
    }

    fun close() {
        currentSession?.close()
        currentSession = null
    }
}

interface InferenceListener {
    fun logging(model: LlmInferenceModel, message: String)
    fun onError(model: LlmInferenceModel, requestId: Int, error: String)
    fun onResults(model: LlmInferenceModel, requestId: Int, response: String)
}