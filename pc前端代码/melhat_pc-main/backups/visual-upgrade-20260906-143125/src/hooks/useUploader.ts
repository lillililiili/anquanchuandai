import { computed, onUnmounted, ref, shallowRef, unref } from "vue";
import { hookResult } from "./bindResult";
import { getToken } from "@/utils/auth";
import { UploadFile, UploadRawFile, UploadRequestOptions } from "element-plus";
import { UploadAjaxError } from "element-plus/es/components/upload/src/ajax";
import request from "@/utils/request";

export interface UploaderProps {
  url: string | (() => string);
  beforeUpload?: () => any;
  onError?: (e: Error) => void;
  onSuccess?: (e: any) => void;
  setData?: (data: FormData) => FormData;
}

export function useUploader(props: UploaderProps) {
  // @ts-ignore
  // const baseUrl = import.meta.env.VITE_APP_BASE_API

  const { url, beforeUpload, onError, onSuccess, setData } = props;

  const action = computed(() => {
    if (typeof url === "string") {
      return url;
    }
    return url();
  });

  const headers = { Authorization: "Bearer " + getToken() };

  const uploaderRef = shallowRef<any>(null);

  const fileList = shallowRef([]);

  function setRef(el: any) {
    uploaderRef.value = el;
  }

  onUnmounted(() => {
    uploaderRef.value = null;
  });

  function returnVerifyRef(method: (instance: any) => Promise<any>) {
    if (uploaderRef.value) {
      return method(uploaderRef.value);
    } else {
      return Promise.reject(new Error("上传组件uploaderRef为null"));
    }
  }

  function abort(file: UploadFile) {
    return returnVerifyRef((uploader) => {
      return uploader.abort(file);
    });
  }

  const waitSuccessCb = ref();

  const waitFailCb = ref();

  /* 不稳定
    1. 当待上传文件数为0时，调用submit会等不到相应的onSuccess回调
  */
  function submit() {
    return returnVerifyRef((uploader) => {
      return new Promise((resolve, reject) => {
        const hasReady = fileList.value.some(
          (file: UploadFile) => file.status === "ready"
        );
        if (hasReady) {
          waitSuccessCb.value = resolve;
          waitFailCb.value = reject;
        } else {
          reject(new Error("待上传文件数为0"));
        }
        uploader.submit();
      });
    });
  }

  function clearFiles(
    status?: Array<"ready" | "uploading" | "success" | "fail">
  ) {
    return returnVerifyRef((uploader) => {
      return uploader.clearFiles(status);
    });
  }

  function handleStart(rawFile: UploadRawFile) {
    return returnVerifyRef((uploader) => {
      return uploader.handleStart(rawFile);
    });
  }

  function handleRemove(
    file: UploadFile | UploadRawFile,
    rawFile?: UploadRawFile
  ) {
    return returnVerifyRef((uploader) => {
      return uploader.handleRemove(file, rawFile);
    });
  }

  function onUploadSuccess(e) {
    // console.log('onSuccess', e)

    if (waitSuccessCb.value) {
      waitSuccessCb.value(e);
      waitSuccessCb.value = null;
    }
    onSuccess && onSuccess(e);
  }

  function onUploadError(e) {
    console.error("onError", e);

    if (waitFailCb.value) {
      waitFailCb.value(e);
      waitFailCb.value = null;
    }
    if (onError) {
      onError(e);
    }
  }

  function onFileListChange(e) {
    // console.log('onFileListChange', e)
    fileList.value = unref(e);
  }

  function httpRequest(options: UploadRequestOptions) {
    console.log("httpRequest", options);
    const data = new FormData();
    data.append("file", options.file);
    setData(data);

    request({
      url: options.action,
      method: "post",
      headers: { Authorization: "Bearer " + getToken() },
      data,
      onUploadProgress: (e) => {
        // console.log('onUploadProgress', e)
        // @ts-ignore
        options.onProgress({
          percent: (e.loaded / e.total) * 100,
          total: e.total,
          loaded: e.loaded,
          target: e.target,
          lengthComputable: e.lengthComputable,
        });
      },
    })
      .then((res) => {
        console.log("res", res);
        // @ts-ignore
        if (res.code === 200) {
          options.onSuccess(res);
        } else {
          // @ts-ignore
          options.onError(
            // @ts-ignore
            new UploadAjaxError("上传失败", res.code, res.msg, res)
          );
        }
      })
      .catch((err) => {
        options.onError(err);
      });
  }

  return hookResult(
    {
      abort,
      submit,
      clearFiles,
      handleStart,
      handleRemove,
    },
    {
      ref: setRef,
      action: action,
      beforeUpload,
      headers: headers,
      onSuccess: onUploadSuccess,
      onError: onUploadError,
      "onUpdate:fileList": onFileListChange,
      httpRequest,
    }
  );
}
