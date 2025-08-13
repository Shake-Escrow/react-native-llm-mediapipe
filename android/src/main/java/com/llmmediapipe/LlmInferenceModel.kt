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
import com.google.mediapipe.tasks.genai.llminference.GraphOptions
import com.google.mediapipe.tasks.genai.llminference.ProgressListener
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
        val preferGpuBackend: Boolean = false,
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
                .setMaxTopK(topK)

        if (enableVisionModality) {
            optionsBuilder.setMaxNumImages(1)
            inferenceListener?.logging(this, "Vision modality enabled with CPU backend")
        }

        // Explicitly set CPU backend regardless of preferGpuBackend when vision is enabled
        if (enableVisionModality) {
            try {
                optionsBuilder.setPreferredBackend(LlmInference.Backend.CPU)
                inferenceListener?.logging(this, "Explicitly set CPU backend for vision modality")
            } catch (e: Exception) {
                inferenceListener?.logging(this, "Error setting CPU backend: ${e.message}")
            }
        } else if (preferGpuBackend) {
            try {
                optionsBuilder.setPreferredBackend(LlmInference.Backend.GPU)
                inferenceListener?.logging(this, "GPU backend requested for text-only model")
            } catch (e: Exception) {
                inferenceListener?.logging(this, "GPU backend not available, falling back to CPU: ${e.message}")
            }
        }

        try {
            val options = optionsBuilder.build()
            llmInference = LlmInference.createFromOptions(context, options)
            inferenceListener?.logging(this, "LlmInference created successfully")
        } catch (e: Exception) {
            inferenceListener?.logging(this, "Failed to create LlmInference: ${e.message}")
            throw e
        }
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

            // Create session options with more conservative settings for vision
            val sessionOptionsBuilder = LlmInferenceSession.LlmInferenceSessionOptions.builder()
                    .setTopK(topK)
                    .setTemperature(temperature)

            if (enableVisionModality) {
                // Use minimal graph options for vision to avoid delegate conflicts
                val graphOptionsBuilder = GraphOptions.builder()
                        .setEnableVisionModality(true)
                
                try {
                    sessionOptionsBuilder.setGraphOptions(graphOptionsBuilder.build())
                    inferenceListener?.logging(this, "Creating vision session with minimal options")
                } catch (e: Exception) {
                    inferenceListener?.logging(this, "Error setting graph options: ${e.message}")
                    // Try without explicit graph options as fallback
                    inferenceListener?.logging(this, "Attempting session creation without explicit graph options")
                }
            }

            val sessionOptions = sessionOptionsBuilder.build()

            // Create new session with error handling
            try {
                currentSession = LlmInferenceSession.createFromOptions(llmInference, sessionOptions)
                inferenceListener?.logging(this, "Session created successfully")
            } catch (e: Exception) {
                inferenceListener?.logging(this, "Failed to create session: ${e.message}")
                throw Exception("Failed to initialize session: ${e.message}")
            }

            // Add text prompt
            currentSession?.addQueryChunk(prompt)

            // Add image if provided with better error handling
            if (imageBase64 != null && enableVisionModality) {
                try {
                    val image = base64ToMPImage(imageBase64)
                    currentSession?.addImage(image)
                    inferenceListener?.logging(this, "Image added to session successfully")
                } catch (e: Exception) {
                    inferenceListener?.logging(this, "Failed to add image: ${e.message}")
                    throw Exception("Failed to process image: ${e.message}")
                }
            }

            // Create progress listener for partial results
            val progressListener = ProgressListener<String> { partialResult, done ->
                try {
                    // Accumulate the partial result
                    requestResult += partialResult
                    // Send the accumulated result to the listener
                    inferenceListener?.onResults(this, requestId, requestResult)
                } catch (e: Exception) {
                    inferenceListener?.logging(this, "Error in progress listener: ${e.message}")
                }
            }

            // Generate response with progress listener
            val future = currentSession?.generateResponseAsync(progressListener)
            
            // Handle the future result
            future?.let { responseFuture ->
                // Use a separate thread to handle the future completion
                Thread {
                    try {
                        val completeResult = responseFuture.get() // This blocks until complete
                        // Update requestResult to the complete result (in case there's any difference)
                        requestResult = completeResult
                        requestPromise?.resolve(completeResult)
                        currentSession?.close()
                        currentSession = null
                    } catch (e: Exception) {
                        val errorMessage = "Inference failed: ${e.message}"
                        inferenceListener?.logging(this, errorMessage)
                        inferenceListener?.onError(this, requestId, errorMessage)
                        requestPromise?.reject("INFERENCE_ERROR", errorMessage)
                        currentSession?.close()
                        currentSession = null
                    }
                }.start()
            } ?: run {
                val errorMessage = "Failed to create inference future"
                inferenceListener?.onError(this, requestId, errorMessage)
                requestPromise?.reject("INFERENCE_ERROR", errorMessage)
            }

        } catch (e: Exception) {
            val errorMessage = "Setup failed: ${e.message}"
            inferenceListener?.logging(this, errorMessage)
            inferenceListener?.onError(this, requestId, errorMessage)
            requestPromise?.reject("INFERENCE_ERROR", errorMessage)
            currentSession?.close()
            currentSession = null
        }
    }

    private fun base64ToMPImage(base64String: String): MPImage {
        try {
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

            inferenceListener?.logging(this, "Original image: ${bitmap.width}x${bitmap.height}")

            // Process the image: downsample and crop to 256x256
            val processedBitmap = processImage(bitmap)

            // Convert processed Bitmap to MPImage
            return BitmapImageBuilder(processedBitmap).build()
        } catch (e: Exception) {
            throw Exception("Image processing failed: ${e.message}")
        }
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

        try {
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
        } catch (e: Exception) {
            throw Exception("Image processing failed: ${e.message}")
        }
    }

    fun close() {
        try {
            currentSession?.close()
            currentSession = null
            llmInference.close()
        } catch (e: Exception) {
            inferenceListener?.logging(this, "Error closing model: ${e.message}")
        }
    }
}

interface InferenceListener {
    fun logging(model: LlmInferenceModel, message: String)
    fun onError(model: LlmInferenceModel, requestId: Int, error: String)
    fun onResults(model: LlmInferenceModel, requestId: Int, response: String)
}