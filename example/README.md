# react-native-llm-mediapipe

`react-native-llm-mediapipe` enables developers to run large language models (LLMs) on iOS and Android devices using React Native. This package allows you to write JavaScript or TypeScript to handle LLM inference directly on mobile platforms, including support for multimodal (text + image) processing.

## Features

- **Run LLM Inference**: Perform natural language processing tasks directly on mobile devices.
- **Image Analysis**: Process and analyze images alongside text prompts using vision-enabled models.
- **React Native Integration**: Seamlessly integrates with your existing React Native projects.
- **JavaScript/TypeScript Support**: Use familiar technologies to control LLM functionality.
- **Streaming Responses**: Receive partial responses as they're generated for better user experience.

## Installation

To get started with `react-native-llm-mediapipe`, install the package using npm or yarn:

```bash
npm install react-native-llm-mediapipe
```

or

```bash
yarn add react-native-llm-mediapipe
```

For image functionality, you'll also need to install `react-native-image-picker`:

```bash
npm install react-native-image-picker
```

## Requirements

Before using this package, you must download or build the LLM model files necessary for its operation. Ensure these model files are properly configured and accessible by your mobile application. Some instructions can be found on [the MediaPipe page](https://developers.google.com/mediapipe/solutions/genai/llm_inference). Or, see below for running a script that will download and convert the model files, automating the process.

For image processing capabilities, use vision-enabled models like Gemma 3n which support multimodal input.

## Building Models

As of 4/22/2024, MediaPipe supports four models for use on-device: Gemma 2B, Falcon 1B, StableLM 3B, and Phi-2. For vision capabilities, use models like Gemma 3n that support multimodal processing. To download and convert the models, follow the instructions above or clone this (react-native-llm-mediapipe) repo, and follow [the instructions here](https://github.com/cdiddy77/react-native-llm-mediapipe/blob/main/models/README.md).

## Usage

### Basic Text Inference

The primary functionality of this package is accessed through the `useLlmInference()` hook. This hook provides a `generateResponse` function, which you can use to process text prompts. Here is a basic example of how to use it in a React Native app:

```tsx
import React, { useState } from 'react';
import { View, TextInput, Button, Text } from 'react-native';
import { useLlmInference } from 'react-native-llm-mediapipe';

const App = () => {
  const [prompt, setPrompt] = useState('');
  const llmInference = useLlmInference({
    storageType: 'asset',
    modelName: 'your-model-name.bin',
  });

  const handleGeneratePress = async () => {
    const response = await llmInference.generateResponse(prompt);
    alert(response); // Display the LLM's response
  };

  return (
    <View style={{ padding: 20 }}>
      <TextInput
        style={{
          height: 40,
          borderColor: 'gray',
          borderWidth: 1,
          marginBottom: 10,
        }}
        onChangeText={setPrompt}
        value={prompt}
        placeholder="Enter your prompt here"
      />
      <Button title="Generate Response" onPress={handleGeneratePress} />
    </View>
  );
};

export default App;
```

### Streaming Text Responses

You can access partial results by supplying callbacks to `generateResponse()`. Note that partial responses represent the accumulated output from the model:

```tsx
const [partialResponse, setPartialResponse] = useState('');

const response = await llmInference.generateResponse(
  prompt,
  (partial) => {
    // partial contains the accumulated response so far
    setPartialResponse(partial);
  },
  (error) => {
    console.error('Error:', error);
  }
);
```

### Image Inference

For multimodal processing with images, enable vision modality and use `generateResponseWithImage()`:

```tsx
import React, { useState, useCallback } from 'react';
import { View, TextInput, Button, Text, Image, Pressable } from 'react-native';
import { launchImageLibrary, MediaType } from 'react-native-image-picker';
import { useLlmInference } from 'react-native-llm-mediapipe';

const App = () => {
  const [prompt, setPrompt] = useState('');
  const [selectedImage, setSelectedImage] = useState(null);
  const [partialResponse, setPartialResponse] = useState('');
  const [isGenerating, setIsGenerating] = useState(false);

  // Enable vision modality for multimodal support
  const llmInference = useLlmInference({
    storageType: 'asset',
    modelName: 'gemma-3n-e2b-it-cpu-int4.bin', // Use a vision-enabled model
    enableVisionModality: true,
  });

  const selectImage = useCallback(() => {
    const options = {
      mediaType: 'photo' as MediaType,
      includeBase64: true,
      quality: 0.7,
    };

    launchImageLibrary(options, (response) => {
      if (response.didCancel || response.errorMessage) {
        return;
      }

      const asset = response.assets?.[0];
      if (asset?.uri && asset?.base64) {
        setSelectedImage({
          uri: asset.uri,
          base64: asset.base64,
        });
      }
    });
  }, []);

  const handleGenerateWithImage = async () => {
    if (!selectedImage || isGenerating) return;

    setIsGenerating(true);
    setPartialResponse('');

    try {
      const response = await llmInference.generateResponseWithImage(
        prompt,
        selectedImage.base64,
        (partial) => {
          // partial contains the accumulated response so far
          setPartialResponse(partial);
        },
        (error) => {
          console.error('Error:', error);
          setIsGenerating(false);
        }
      );
      
      console.log('Final response:', response);
    } catch (error) {
      console.error('Error generating response:', error);
    } finally {
      setIsGenerating(false);
    }
  };

  return (
    <View style={{ padding: 20 }}>
      <TextInput
        style={{
          height: 40,
          borderColor: 'gray',
          borderWidth: 1,
          marginBottom: 10,
        }}
        onChangeText={setPrompt}
        value={prompt}
        placeholder="Enter your prompt about the image"
        editable={!isGenerating}
      />
      
      <Button 
        title="Select Image" 
        onPress={selectImage}
        disabled={isGenerating}
      />
      
      {selectedImage && (
        <View style={{ marginVertical: 10 }}>
          <Image 
            source={{ uri: selectedImage.uri }} 
            style={{ width: 200, height: 200 }}
            resizeMode="contain"
          />
          <Button 
            title="Clear Image" 
            onPress={() => setSelectedImage(null)}
            disabled={isGenerating}
          />
        </View>
      )}
      
      <Button 
        title={isGenerating ? "Analyzing..." : "Analyze Image"}
        onPress={handleGenerateWithImage}
        disabled={!selectedImage || isGenerating}
      />
      
      {partialResponse && (
        <Text style={{ marginTop: 10 }}>{partialResponse}</Text>
      )}
    </View>
  );
};

export default App;
```

### Hook Configuration Options

The `useLlmInference` hook accepts the following configuration options:

```tsx
const llmInference = useLlmInference({
  storageType: 'asset', // 'asset' or 'file' - where the model files are stored
  modelName: 'your-model-name.bin', // Name of your model file (for asset storage)
  // or
  modelPath: '/path/to/model.bin', // Full path to model file (for file storage)
  
  // Optional parameters with defaults:
  maxTokens: 512, // Maximum tokens to generate
  topK: 40, // Top-k sampling parameter
  temperature: 0.8, // Temperature for response randomness
  randomSeed: 0, // Random seed for reproducible results
  enableVisionModality: false, // Enable image processing capabilities
});
```

### Best Practices

#### State Management
Always track the generation state to prevent concurrent requests:

```tsx
const [isGenerating, setIsGenerating] = useState(false);

const handleGenerate = async () => {
  if (isGenerating) return;
  
  setIsGenerating(true);
  try {
    // ... generation logic
  } finally {
    setIsGenerating(false);
  }
};
```

#### Error Handling
Implement proper error handling for both promise rejections and callback errors:

```tsx
const response = await llmInference.generateResponse(
  prompt,
  (partial) => {
    setPartialResponse(partial);
  },
  (error) => {
    // Handle streaming errors
    console.error('Streaming error:', error);
    setErrorMessage(error);
    setIsGenerating(false);
  }
).catch((error) => {
  // Handle promise rejection errors
  console.error('Generation error:', error);
  setErrorMessage(error.message);
  setIsGenerating(false);
});
```

### API Reference

#### `generateResponse(prompt, onPartial?, onError?)`

Generates a text response from a text prompt.

- `prompt` (string): The input text prompt
- `onPartial` (function, optional): `(partial: string, requestId?: number) => void` - Callback for streaming partial responses. The `partial` parameter contains the accumulated response text.
- `onError` (function, optional): `(error: string, requestId?: number) => void` - Error handling callback
- Returns: Promise<string> - The complete response

#### `generateResponseWithImage(prompt, imageBase64, onPartial?, onError?)`

Generates a response from both text and image input (requires vision-enabled model).

- `prompt` (string): The input text prompt about the image
- `imageBase64` (string): Base64-encoded image data
- `onPartial` (function, optional): `(partial: string, requestId?: number) => void` - Callback for streaming partial responses. The `partial` parameter contains the accumulated response text.
- `onError` (function, optional): `(error: string, requestId?: number) => void` - Error handling callback
- Returns: Promise<string> - The complete response

#### `isLoaded`

A boolean property that indicates whether the model has been successfully loaded and is ready for inference.

```tsx
const llmInference = useLlmInference(config);

if (llmInference.isLoaded) {
  // Model is ready for inference
}
```

## Important Notes

### Streaming Behavior
The streaming callbacks receive the **accumulated** response text, not individual chunks. This means:
- Each `onPartial` call contains the complete response generated so far
- You should replace (not append) the displayed text with each partial update
- The final promise resolution will contain the same complete text as the last partial update

### Image Processing
Images are automatically processed before being sent to the model:
- Images are downsampled to ensure the smaller dimension equals 256 pixels
- Images are then center-cropped to 256x256 pixels
- Images smaller than 256x256 are left unchanged
- This processing optimizes inference performance while maintaining image quality

### Concurrent Requests
The native implementation prevents concurrent requests per model instance. Always track generation state in your UI to prevent multiple simultaneous requests.

## Example Use Cases

### Image Analysis
```tsx
// Analyze image content
await llmInference.generateResponseWithImage(
  "Describe what you see in this image in detail.",
  imageBase64
);

// Count objects
await llmInference.generateResponseWithImage(
  "How many people are in this image?",
  imageBase64
);

// Identify objects
await llmInference.generateResponseWithImage(
  "List all the objects you can identify in this image.",
  imageBase64
);
```

## Contributing

Contributions are very welcome! If you would like to improve react-native-llm-mediapipe, please feel free to fork the repository, make changes, and submit a pull request. You can also open an issue if you find bugs or have feature requests.

## License

This project is licensed under the MIT License - see the LICENSE file for details.

## Support

For support, feature requests, or any other inquiries, please open an issue on the GitHub project page.