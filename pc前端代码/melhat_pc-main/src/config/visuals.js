const definitions = {
  group: ['群组管理', '组织作业班组，让人员与设备协同有序。'],
  live: ['实时监控', '连接现场视角，及时掌握作业动态。'],
  hat: ['安全帽管理', '设备状态、人员绑定与现场资料，一目了然。'],
  fence: ['电子围栏', '明确作业边界，关注人员进出与区域安全。'],
  track: ['轨迹回放', '沿时间追溯作业足迹，回看现场记录。'],
  intercom: ['实时对讲', '连接一线人员，让现场沟通更直接。'],
  tts: ['语音广播', '统一传达作业信息，协调现场行动。'],
  sos: ['告警中心', '汇集安全事件，及时关注与处理告警。'],
  file: ['文件管理', '归集现场影像与录音，便捷查阅作业资料。'],
  system: ['系统管理', '维护组织、账号与权限，保障平台有序运行。']
}

export const moduleVisuals = Object.fromEntries(Object.entries(definitions).map(([key, [title, description]]) => [key, {
  title, description, image: `${import.meta.env.BASE_URL}visuals/${key}.webp`
}]))
