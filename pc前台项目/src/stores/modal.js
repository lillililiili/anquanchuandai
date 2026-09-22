import { reactive, shallowRef } from "vue";

export const modal = reactive({
  open: false,
  title: "",
  wide: false,
  tone: "",
});

export const modalView = shallowRef(null);
export const modalProps = shallowRef({});
export const modalFooter = shallowRef(null);

let returnFocus = null;

export function openModal({ title, wide = false, tone = "", view, props = {}, footer = null }) {
  returnFocus = document.activeElement;
  modal.title = title;
  modal.wide = !!wide;
  modal.tone = tone;
  modalView.value = view;
  modalProps.value = props;
  modalFooter.value = footer;
  modal.open = true;
}

export function closeModal() {
  modal.open = false;
  modal.tone = "";
  modalView.value = null;
  modalFooter.value = null;
  modalProps.value = {};
  returnFocus?.focus?.();
  returnFocus = null;
}
