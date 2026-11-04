export function maintenancePresentation(status) {
  if (!status) return { title: '状态未读取', message: '读取维护状态后才能操作。' }
  if (!status.paused) return { title: '正常运行', message: '业务写入正常开放。' }
  if (Number(status.unknown) > 0) return { title: '已暂停 · 结果待核对', message: `有 ${status.unknown} 项执行结果未确认，尚未排空。请核对原操作，不能据此停机或导入。` }
  if (!status.quiescent) return { title: '已暂停 · 正在排空', message: `仍有 ${status.activeWrites || 0} 项已接收操作处理中，请等待状态刷新。` }
  return { title: '已暂停 · 已排空', message: '当前业务操作已完成；设备原始上报继续保存，恢复后处理。' }
}
