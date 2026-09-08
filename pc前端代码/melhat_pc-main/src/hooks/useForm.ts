import { reactive, shallowRef, onUnmounted } from "vue";
import { hookResult } from "./bindResult";
import { FormItemRule } from "element-plus";

type RulesRecord<T> = {
  [key in keyof T]?: FormItemRule | FormItemRule[];
};

interface SimpleFormProps<T> {
  model: T;
  rules?: RulesRecord<T>;
  labelWidth?: string | number;
  validate?: (params: any) => void;
}

// 原生深拷贝实现（替代 lodash cloneDeep）
function deepClone<T>(obj: T): T {
  if (obj === null || typeof obj !== "object") return obj;
  if (obj instanceof Date) return new Date(obj.getTime()) as T;
  if (obj instanceof Array) return obj.map((item) => deepClone(item)) as T;
  if (obj instanceof Object) {
    const cloned: Record<string, any> = {};
    for (const key in obj) {
      if (Object.prototype.hasOwnProperty.call(obj, key)) {
        cloned[key] = deepClone((obj as Record<string, any>)[key]);
      }
    }
    return cloned as T;
  }
  return obj;
}

export function useForm<T extends object>(prop: SimpleFormProps<T>) {
  const { model, rules, labelWidth, validate } = prop;

  const initSnapshot = deepClone(model);

  const formModel = reactive<T>(model);

  const formRef = shallowRef<any>(null);

  function setFieldsValue(params: T[any]) {
    for (const key in params) {
      formModel[key] = params[key];
    }
  }

  function backToInit() {
    for (const key in model) {
      // @ts-ignore
      formModel[key] = initSnapshot[key];
    }
    clearValidate([Object.keys(formModel)]);
  }

  function returnVerifyRef(method: (instance: any) => Promise<any>) {
    if (formRef.value) {
      return method(formRef.value);
    } else {
      return Promise.reject(new Error("表单formRef为null"));
    }
  }

  function resetFields() {
    return returnVerifyRef((form) => {
      return form.resetFields();
    });
  }

  function clearValidate(...params: any[]) {
    return returnVerifyRef((form) => {
      return form.clearValidate(...params);
    });
  }

  /* 校验整个表单 */
  function validateForm(...params: any[]) {
    return returnVerifyRef((form) => {
      return form.validate(...params);
    });
  }

  /* 校验单个字段 */
  function validateField(...params: any[]) {
    return returnVerifyRef((form) => {
      return form.validate(...params);
    });
  }

  function scrollToField(...params: any[]) {
    return returnVerifyRef((form) => {
      return form.scrollToField(...params);
    });
  }

  function setRef(el: any) {
    formRef.value = el;
  }

  onUnmounted(() => {
    formRef.value = null;
  });

  return hookResult(
    {
      validate: validateForm,
      model: formModel,
      setFieldsValue,
      resetFields,
      clearValidate,
      scrollToField,
      validateField,
      backToInit,
    },
    {
      ref: setRef,
      model: formModel,
      rules,
      labelWidth: labelWidth,
      validate,
    }
  );
}
