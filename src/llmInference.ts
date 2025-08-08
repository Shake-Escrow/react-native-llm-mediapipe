import React from 'react';
import { NativeEventEmitter, NativeModules } from 'react-native';

const { LlmInferenceModule } = NativeModules;

const eventEmitter = new NativeEventEmitter(LlmInferenceModule);

interface LlmInference {
  createModel: (
    modelPath: string,
    maxTokens: number,
    topK: number,
    temperature: number,
    randomSeed: number,
    enableVisionModality: boolean
  ) => Promise<number>;
  createModelFromAsset: (
    modelName: string,
    maxTokens: number,
    topK: number,
    temperature: number,
    randomSeed: number,
    enableVisionModality: boolean
  ) => Promise<number>;
  releaseModel: (handle: number) => Promise<boolean>;
  generateResponse: (
    handle: number,
    requestId: number,
    prompt: string
  ) => Promise<string>;
  generateResponseWithImage: (
    handle: number,
    requestId: number,
    prompt: string,
    imageBase64: string | null
  ) => Promise<string>;
}

function getLlmInference(): LlmInference {
  return LlmInferenceModule as LlmInference;
}

export interface LlmInferenceEvent {
  logging: (handle: number, message: string) => void;
  onPartialResponse: (ev: {
    handle: number;
    requestId: number;
    response: string;
  }) => void;
  onErrorResponse: (ev: {
    handle: number;
    requestId: number;
    error: string;
  }) => void;
}

eventEmitter.addListener(
  'logging',
  (ev: { handle: number; message: string }) => {
    console.log(`[${ev.handle}] ${ev.message}`);
  }
);

type LlmModelLocation =
  | { storageType: 'asset'; modelName: string }
  | { storageType: 'file'; modelPath: string };
export type LlmInferenceConfig = LlmModelLocation & {
  maxTokens?: number;
  topK?: number;
  temperature?: number;
  randomSeed?: number;
  enableVisionModality?: boolean;
};

function getConfigStorageKey(config: LlmInferenceConfig): string {
  if (config.storageType === 'asset') {
    return `${config.modelName}`;
  }
  return `${config.modelPath}`;
}

export function useLlmInference(config: LlmInferenceConfig) {
  const [modelHandle, setModelHandle] = React.useState<number | undefined>();
  const configStorageKey = getConfigStorageKey(config);
  React.useEffect(() => {
    // Skip model creation if configStorageKey is empty
    if (configStorageKey.length === 0) {
      console.warn(
        'No valid model path or name provided. Skipping model creation.'
      );
      return;
    }
    let newHandle: number | undefined;
    const modelCreatePromise =
      config.storageType === 'asset'
        ? getLlmInference().createModelFromAsset(
            configStorageKey,
            config.maxTokens ?? 512,
            config.topK ?? 40,
            config.temperature ?? 0.8,
            config.randomSeed ?? 0,
            config.enableVisionModality ?? false
          )
        : getLlmInference().createModel(
            configStorageKey,
            config.maxTokens ?? 512,
            config.topK ?? 40,
            config.temperature ?? 0.8,
            config.randomSeed ?? 0,
            config.enableVisionModality ?? false
          );

    modelCreatePromise
      .then((handle) => {
        console.log(`Created model with handle ${handle}`);
        setModelHandle(handle);
        newHandle = handle;
      })
      .catch((error) => {
        console.error('createModel', error);
      });

    return () => {
      if (newHandle !== undefined) {
        getLlmInference()
          .releaseModel(newHandle)
          .then(() => {
            console.log(`Released model with handle ${newHandle}`);
          })
          .catch(() => {
            console.error('releaseModel');
          });
      }
    };
  }, [
    config.maxTokens,
    config.storageType,
    config.randomSeed,
    config.temperature,
    config.topK,
    config.enableVisionModality,
    configStorageKey,
  ]);

  const nextRequestIdRef = React.useRef(0);

  const generateResponse = React.useCallback(
    async (
      prompt: string,
      onPartial?: (partial: string, requestId: number | undefined) => void,
      onError?: (message: string, requestId: number | undefined) => void,
      abortSignal?: AbortSignal
    ): Promise<string> => {
      if (modelHandle === undefined) {
        throw new Error('Model handle is not defined');
      }
      const requestId = nextRequestIdRef.current++;
      const partialSub = eventEmitter.addListener(
        'onPartialResponse',
        (ev: { handle: number; requestId: number; response: string }) => {
          console.log(JSON.stringify(ev));
          if (
            onPartial &&
            requestId === ev.requestId &&
            !(abortSignal?.aborted ?? false)
          ) {
            onPartial(ev.response, ev.requestId);
          }
        }
      );
      const errorSub = eventEmitter.addListener(
        'onErrorResponse',
        (ev: { handle: number; requestId: number; error: string }) => {
          console.log(`[${ev.handle}] error ${ev.requestId}: ${ev.error}`);
          if (
            onError &&
            requestId === ev.requestId &&
            !(abortSignal?.aborted ?? false)
          ) {
            onError(ev.error, ev.requestId);
          }
        }
      );

      try {
        return await getLlmInference().generateResponse(
          modelHandle,
          requestId,
          prompt
        );
      } catch (e) {
        console.error(e);
        throw e;
      } finally {
        console.log('finally: removing listeners');
        partialSub.remove();
        errorSub.remove();
      }
    },
    [modelHandle]
  );

  const generateResponseWithImage = React.useCallback(
    async (
      prompt: string,
      imageBase64: string,
      onPartial?: (partial: string, requestId: number | undefined) => void,
      onError?: (message: string, requestId: number | undefined) => void,
      abortSignal?: AbortSignal
    ): Promise<string> => {
      if (modelHandle === undefined) {
        throw new Error('Model handle is not defined');
      }
      const requestId = nextRequestIdRef.current++;
      const partialSub = eventEmitter.addListener(
        'onPartialResponse',
        (ev: { handle: number; requestId: number; response: string }) => {
          console.log(JSON.stringify(ev));
          if (
            onPartial &&
            requestId === ev.requestId &&
            !(abortSignal?.aborted ?? false)
          ) {
            onPartial(ev.response, ev.requestId);
          }
        }
      );
      const errorSub = eventEmitter.addListener(
        'onErrorResponse',
        (ev: { handle: number; requestId: number; error: string }) => {
          console.log(`[${ev.handle}] error ${ev.requestId}: ${ev.error}`);
          if (
            onError &&
            requestId === ev.requestId &&
            !(abortSignal?.aborted ?? false)
          ) {
            onError(ev.error, ev.requestId);
          }
        }
      );

      try {
        return await getLlmInference().generateResponseWithImage(
          modelHandle,
          requestId,
          prompt,
          imageBase64
        );
      } catch (e) {
        console.error(e);
        throw e;
      } finally {
        console.log('finally: removing listeners');
        partialSub.remove();
        errorSub.remove();
      }
    },
    [modelHandle]
  );

  return React.useMemo(
    () => ({ 
      generateResponse, 
      generateResponseWithImage,
      isLoaded: modelHandle !== undefined 
    }),
    [generateResponse, generateResponseWithImage, modelHandle]
  );
}