/**
 * Sample React Native App with Image Support
 * https://github.com/facebook/react-native
 *
 * @format
 */

import React from 'react';
import {
  ActivityIndicator,
  Alert,
  Image,
  Keyboard,
  KeyboardAvoidingView,
  Platform,
  Pressable,
  SafeAreaView,
  ScrollView,
  Text,
  TextInput,
  TouchableWithoutFeedback,
  View,
} from 'react-native';
import { launchImageLibrary, MediaType } from 'react-native-image-picker';
import { colors, styles } from './styles';
import { type Message } from './types';
import { useLlmInference } from 'react-native-llm-mediapipe';

const samplePrompts = [
  "Explain the difference between 'affect' and 'effect' and use both words correctly in a complex sentence.",
  'If all Roses are flowers and some flowers fade quickly, can it be concluded that some roses fade quickly? Explain your answer.',
  'A shop sells apples for $2 each and bananas for $1 each. If I buy 3 apples and 2 bananas, how much change will I get from a $10 bill?',
  "Describe the process of photosynthesis and explain why it's crucial for life on Earth.",
  'Who was the president of the United States during World War I, and what were the major contributions of his administration during that period?',
  'Discuss the significance of Diwali in Indian culture and how it is celebrated across different regions of India.',
  'Should self-driving cars be programmed to prioritize the lives of pedestrians over the occupants of the car in the event of an unavoidable accident? Discuss the ethical considerations.',
  'Imagine a world where water is more valuable than gold. Describe a day in the life of a trader dealing in water.',
  'Given that you learned about a new scientific discovery that overturns the previously understood mechanism of muscle growth, explain how this might impact current fitness training regimens.',
  'What are the potential benefits and risks of using AI in recruiting and hiring processes, and how can companies mitigate the risks?',
  // Image-related prompts
  'Describe what you see in this image in detail.',
  'What objects can you identify in this image?',
  'Analyze the composition and colors in this image.',
  'What is the mood or atmosphere conveyed by this image?',
  'Count the number of people/objects you can see in this image.',
];

let samplePromptIndex = 0;

interface MessageWithImage extends Message {
  imageUri?: string;
}

function App(): React.JSX.Element {
  const textInputRef = React.useRef<TextInput>(null);
  const [prompt, setPrompt] = React.useState('');
  const messagesScrollViewRef = React.useRef<ScrollView>(null);
  const [messages, setMessages] = React.useState<MessageWithImage[]>([]);
  const [partialResponse, setPartialResponse] = React.useState<MessageWithImage>();
  const [selectedImage, setSelectedImage] = React.useState<{
    uri: string;
    base64: string;
  } | null>(null);
  const [isGenerating, setIsGenerating] = React.useState(false);

  // Enable vision modality for multimodal support
  const llmInference = useLlmInference({
    storageType: 'asset',
    modelName: 'gemma-3n-e2b-it-cpu-int4.bin', // Use Gemma 3n for vision support
    enableVisionModality: true,
  });

  const selectImage = React.useCallback(() => {
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

  const clearImage = React.useCallback(() => {
    setSelectedImage(null);
  }, []);

  const onSendPrompt = React.useCallback(async () => {
    if (prompt.length === 0 || isGenerating) {
      return;
    }

    const messageContent: MessageWithImage = { 
      role: 'user', 
      content: prompt,
      imageUri: selectedImage?.uri
    };
    
    setMessages((prev) => [...prev, messageContent]);
    setPartialResponse({ role: 'assistant', content: '' });
    setPrompt('');
    setIsGenerating(true);

    try {
      let response: string;
      
      if (selectedImage) {
        // Generate response with image
        response = await llmInference.generateResponseWithImage(
          prompt,
          selectedImage.base64,
          (partial) => {
            setPartialResponse({ role: 'assistant', content: partial });
          },
          (error) => {
            console.error('Error in partial callback:', error);
            setMessages((prev) => [
              ...prev,
              { role: 'error', content: `Error: ${error}` },
            ]);
            setPartialResponse(undefined);
            setIsGenerating(false);
          }
        );
        // Clear the selected image after sending
        setSelectedImage(null);
      } else {
        // Generate text-only response
        response = await llmInference.generateResponse(
          prompt,
          (partial) => {
            setPartialResponse({ role: 'assistant', content: partial });
          },
          (error) => {
            console.error('Error in partial callback:', error);
            setMessages((prev) => [
              ...prev,
              { role: 'error', content: `Error: ${error}` },
            ]);
            setPartialResponse(undefined);
            setIsGenerating(false);
          }
        );
      }

      setPartialResponse(undefined);
      setMessages((prev) => [...prev, { role: 'assistant', content: response }]);
    } catch (error) {
      console.error('Error generating response:', error);
      setMessages((prev) => [
        ...prev,
        { role: 'error', content: `Error: ${error}` },
      ]);
      setPartialResponse(undefined);
    } finally {
      setIsGenerating(false);
    }
  }, [llmInference, prompt, selectedImage, isGenerating]);

  const onSamplePrompt = React.useCallback(() => {
    if (isGenerating) return;
    setPrompt(samplePrompts[samplePromptIndex++ % samplePrompts.length] ?? '');
    textInputRef.current?.focus();
  }, [isGenerating]);

  return (
    <SafeAreaView style={styles.root}>
      <KeyboardAvoidingView
        keyboardVerticalOffset={0}
        behavior={Platform.OS === 'ios' ? 'padding' : 'height'}
        style={styles.keyboardRoot}
      >
        <TouchableWithoutFeedback
          onPress={() => Keyboard.dismiss()}
          style={styles.promptInnerContainer}
        >
          <ScrollView
            ref={messagesScrollViewRef}
            style={styles.messagesScrollView}
            contentContainerStyle={styles.messagesContainer}
            onContentSizeChange={() =>
              messagesScrollViewRef.current?.scrollToEnd()
            }
          >
            {messages.map((m, index) => (
              <MessageView message={m} key={index} />
            ))}
            {partialResponse && <MessageView message={partialResponse} />}
          </ScrollView>
        </TouchableWithoutFeedback>

        {/* Selected Image Preview */}
        {selectedImage && (
          <View style={styles.imagePreviewContainer}>
            <Image 
              source={{ uri: selectedImage.uri }} 
              style={styles.imagePreview}
              resizeMode="contain"
            />
            <Pressable onPress={clearImage} style={styles.clearImageButton}>
              <Text style={styles.clearImageButtonText}>✕</Text>
            </Pressable>
          </View>
        )}

        <View style={styles.promptRow}>
          <Pressable
            onPress={onSamplePrompt}
            style={styles.samplePromptButton}
            disabled={isGenerating}
          >
            <Text style={styles.samplePromptButtonText}>⚡️</Text>
          </Pressable>

          <Pressable
            onPress={selectImage}
            style={styles.imageButton}
            disabled={isGenerating}
          >
            <Text style={styles.imageButtonText}>📷</Text>
          </Pressable>

          <TextInput
            ref={textInputRef}
            selectTextOnFocus={true}
            onChangeText={setPrompt}
            value={prompt}
            placeholder={'prompt...'}
            placeholderTextColor={colors.light}
            multiline={true}
            style={styles.promptInput}
            editable={!isGenerating}
          />
          
          <Pressable
            onPress={onSendPrompt}
            disabled={prompt.length === 0 || isGenerating}
            style={styles.sendButton}
          >
            {isGenerating ? (
              <ActivityIndicator />
            ) : (
              <Text style={styles.sendButtonText}>Send</Text>
            )}
          </Pressable>
        </View>
      </KeyboardAvoidingView>
    </SafeAreaView>
  );
}

const MessageView: React.FC<{ message: MessageWithImage }> = ({ message }) => {
  return (
    <View style={styles.message}>
      {message.imageUri && (
        <Image 
          source={{ uri: message.imageUri }} 
          style={styles.messageImage}
          resizeMode="contain"
        />
      )}
      <Text style={styles.messageText}>{message.content}</Text>
    </View>
  );
};

export default App;