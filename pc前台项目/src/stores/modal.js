import { reactive, shallowRef } from "vue";
import { restoreDialogFocus } from "@ui-spec/dialog";

export const modal = reactive({
  open: false,
  title: "",
  wide: false,
  size: undefined,
  layout: "content",
  tone: "",
});

export const modalView = shallowRef(null);
export const modalProps = shallowRef({});
export const modalFooter = shallowRef(null);

let returnFocus = null;

export function openModal({ title, wide = false, size, layout = "content", tone = "", view, props = {}, footer = null }) {
  if (!modal.open) returnFocus = document.activeElement;
  modal.title = title;
  modal.wide = !!wide;
  modal.size = size;
  modal.layout = layout;
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
  restoreDialogFocus(returnFocus);
  returnFocus = null;
}
