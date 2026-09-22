import ConfirmText from "@/components/ui/ConfirmText.vue";
import ConfirmActions from "@/components/ui/ConfirmActions.vue";
import CsvPreview from "@/components/ui/CsvPreview.vue";
import CsvActions from "@/components/ui/CsvActions.vue";
import { csvContent, download } from "./files";
import { openModal } from "@/stores/modal";
import { toast } from "@/stores/notify";

export function confirm(title, text, onConfirm) {
  openModal({
    title,
    view: ConfirmText,
    props: { text, onConfirm },
    footer: ConfirmActions,
  });
}

export function previewCsv(filename, headers, rows) {
  const content = csvContent(headers, rows);
  download(filename, content, "text/csv;charset=utf-8");
  openModal({
    title: "导出预览 · " + filename,
    wide: true,
    view: CsvPreview,
    props: { filename, headers, rows, content },
    footer: CsvActions,
  });
  toast("已生成当前筛选结果，请查看导出预览");
}
