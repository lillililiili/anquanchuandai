import { computed, ref, toValue, watch } from "vue";

export function pageCount(total, size = 10) {
  return Math.max(1, Math.ceil(Math.max(0, total) / Math.max(1, size)));
}

export function clampPage(page, total, size = 10) {
  return Math.min(pageCount(total, size), Math.max(1, Math.trunc(Number(page)) || 1));
}

export function pageNumbers(page, count) {
  if (count <= 5) return Array.from({ length: count }, (_, index) => index + 1);
  const middle = Math.max(3, Math.min(count - 2, page));
  return [...new Set([1, middle - 1, middle, middle + 1, count])].flatMap((value, index, values) =>
    index && value - values[index - 1] > 1 ? [`gap-${value}`, value] : [value],
  );
}

export function useTablePagination(rows, resetKey) {
  const page = ref(1);
  const pageSize = ref(10);
  const total = computed(() => toValue(rows).length);
  const currentPage = computed(() => clampPage(page.value, total.value, pageSize.value));
  const offset = computed(() => (currentPage.value - 1) * pageSize.value);
  const visibleRows = computed(() => toValue(rows).slice(offset.value, offset.value + pageSize.value));

  watch(() => JSON.stringify(toValue(resetKey)), () => { page.value = 1; });
  watch(pageSize, () => { page.value = 1; });
  // Polling can replace row objects. Keep the current page unless its data no longer exists.
  watch(total, () => { page.value = currentPage.value; });

  function changePage(value) {
    page.value = clampPage(value, total.value, pageSize.value);
  }

  function changePageSize(value) {
    pageSize.value = [10, 20, 50].includes(Number(value)) ? Number(value) : 10;
    page.value = 1;
  }

  return { page: currentPage, pageSize, total, offset, visibleRows, changePage, changePageSize };
}
