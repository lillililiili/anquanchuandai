<script setup>
import { nextTick, onMounted, onUnmounted, ref, watch } from "vue";
import AppButton from "./AppButton.vue";
import { closeModal } from "@/stores/modal";

const props = defineProps({
  title: { type: String, default: "" },
  wide: Boolean,
  tone: { type: String, default: "" },
});

const dialog = ref(null);

function focusable() {
  if (!dialog.value) return [];
  return [...dialog.value.querySelectorAll("button,a,input,select,textarea,[tabindex='0']")].filter(
    (element) => !element.disabled && element.offsetParent !== null,
  );
}

function onKeydown(event) {
  if (event.key === "Escape") {
    event.preventDefault();
    closeModal();
    return;
  }
  if (event.key !== "Tab") return;
  const items = focusable();
  const first = items[0];
  const last = items.at(-1);
  if (!first) return;
  if (event.shiftKey && document.activeElement === first) {
    last?.focus();
    event.preventDefault();
  } else if (!event.shiftKey && document.activeElement === last) {
    first.focus();
    event.preventDefault();
  }
}

async function focusFirst() {
  await nextTick();
  focusable()[0]?.focus();
}

onMounted(() => {
  window.addEventListener("keydown", onKeydown);
  focusFirst();
});

onUnmounted(() => window.removeEventListener("keydown", onKeydown));

watch(() => props.title, focusFirst);
</script>

<template>
  <div class="modal-backdrop" @click.self="closeModal">
    <section ref="dialog" :class="['modal', wide ? 'wide' : '', tone]" role="dialog" aria-modal="true" :aria-label="title">
      <header>
        <h2>{{ title }}</h2>
        <AppButton tone="icon-only" icon="close-line" aria-label="关闭弹窗" @click="closeModal" />
      </header>
      <div class="modal-body"><slot /></div>
      <footer v-if="$slots.footer"><slot name="footer" /></footer>
    </section>
  </div>
</template>
