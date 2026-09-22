import { ref } from "vue";

export const toasts = ref([]);
let sequence = 0;

export function toast(text, error = false) {
  const id = ++sequence;
  toasts.value = [...toasts.value, { id, text, error: !!error }];
  setTimeout(() => {
    toasts.value = toasts.value.filter((item) => item.id !== id);
  }, 4200);
}
