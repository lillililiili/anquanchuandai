from pathlib import Path
import shutil
r=Path(r'C:/Users/qiyue/Desktop/开发项目');base=r/'android代码/melhat_android-main';q=base/'lib/wear/queries'
gen=Path(r'C:/Users/qiyue/.codex/generated_images/01a0aceb-d898-7bc1-a9ed-56fd205e662f')
for src,name in [('exec-8fb8f7d0-d9ac-48b4-b8d6-c73af5239b32.png','task_reference_hero.png'),('exec-a7735763-8e4a-4718-9e92-029428b042ea.png','work_reference_scene.png')]:
    shutil.copy2(gen/src,base/'assets/field-brand/preview'/name)
    shutil.copy2(gen/src,r/'新版安卓端开发/UI素材/背景'/name)
p=q/'tasks.dart';s=p.read_text(encoding='utf-8');start=s.index('  @override\n  Widget build',s.index('class _TaskPageState'));end=s.index('  Widget _equipmentRow',start)
s=s[:start]+'''  void _back() {
    if (context.canPop()) { context.pop(); } else { context.go('/workbench'); }
  }

  void _exampleAction() {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
      content: Text('界面示例：未连接真实人员、事件或通话服务')));
  }

  Future<void> _showPreview() async {
    final task = await workReferencePreview();
    if (!mounted) return;
    setState(() {
      _preview = true;
      _task = task;
      _equipment = jsonList(task['equipmentCheck']);
      _events = jsonList(task['events']);
      _loading = false;
      _error = null;
    });
  }

  void _contactGuardian() {
    if (_preview) { _exampleAction(); return; }
    final id = idOf(_task?['guardianPersonId']);
    if (id.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('尚未关联监护人，无法发起联系')));
      return;
    }
    context.push(communicationUri(personId: id).toString());
  }

  @override
  Widget build(BuildContext context) {
    final task = _task;
    final unavailable = _error is WearApiException &&
        [404, 501].contains((_error as WearApiException).code);
    if (_loading || _error != null || task == null) {
      return QueryPage(title: '作业详情',body: Column(children: [
        Expanded(child: QueryStateView(loading: _loading,error: _error,empty: task == null,
          onRetry: _load,child: const SizedBox.shrink())),
        if (unavailable) TextButton(onPressed: _showPreview, child: const Text('查看界面示例')),
      ]));
    }
    return Scaffold(backgroundColor: const Color(0xFFEEF8FF),body: SafeArea(
      child: TaskReferenceView(
        task: task,equipment: _equipment,events: _events,
        owner: workOwnerLabel(task, _session!),guardian: workGuardianLabel(task),preview: _preview,
        onBack: _back,onRefresh: _preview ? _showPreview : _load,
        onPerson: (person) {
          if (_preview) { _exampleAction(); return; }
          final id=idOf(person['personId']);
          if(id.isNotEmpty) context.push('/people/$id');
        },
        onEvent: (event) {
          if (_preview) { _exampleAction(); return; }
          final id=idOf(event['id']);
          if(id.isNotEmpty) context.push(Uri(path:'/events',queryParameters:{'eventId':id}).toString());
        },
        onGuardian: _contactGuardian,
        details: Column(children: [
          DetailField(label: '状态',value: taskStatusLabel(task['status'])),
          DetailField(label: '作业类型',value: _workTypeLabel(task['workType'])),
          DetailField(label: '作业区域',value: textOf(task['spaceName'])),
          DetailField(label: '计划时间',value: '\${formatTime(task['plannedStart'])} 至 \${formatTime(task['plannedEnd'])}'),
          DetailField(label: '实际时间',value: '\${formatTime(task['actualStart'])} 至 \${formatTime(task['actualEnd'])}'),
          DetailField(label: '工作票',value: _ticketLabel(task)),
          if(task['demo']==true) const DetailField(label:'数据标识',value:'演示作业，不作为生产依据'),
          for(final person in jsonList(task['members'])) DetailField(label:textOf(person['name']),value:textOf(person['personCode'])),
        ]),
        equipmentDetails: Column(children: _equipment.isEmpty
          ? [const Padding(padding:EdgeInsets.all(12),child:Text('该任务没有装备检查项'))]
          : _equipment.map(_equipmentRow).toList()),
      ),
    ));
  }

'''+s[end:]
# Explicit example navigation stays local; it must never request example IDs.
s=s.replace('  Future<void> _load() async {\n    final session = _session;',"  Future<void> _load() async {\n    if (widget.id == 'ui-preview') { await _showPreview(); return; }\n    final session = _session;")
p.write_text(s,encoding='utf-8')

p=q/'workbench.dart';s=p.read_text(encoding='utf-8').replace("import 'query_widgets.dart';","import 'query_widgets.dart';\nimport 'work_reference.dart';")
s=s.replace('''                    _pageHeader(),
                    const SizedBox(height: 12),
                    _greeting(),
                    const SizedBox(height: 12),
                    _dutyActions(summary),
                    const SizedBox(height: 12),
                    _currentWorkCard(summary),''','''                    Container(
                      decoration: const BoxDecoration(image: DecorationImage(
                        image: AssetImage(WearArt.skyHeader),fit: BoxFit.cover,
                        opacity: .22,alignment: Alignment.topCenter)),
                      child: Column(children: [
                        _pageHeader(),
                        const SizedBox(height: 12),
                        _greeting(),
                        const SizedBox(height: 8),
                        _dutyActions(summary),
                        const SizedBox(height: 6),
                        _currentWorkCard(summary),
                      ]),
                    ),''')
start=s.index('  Widget _currentWorkCard');end=s.index('  Widget _metaLine',start)
s=s[:start]+'''  Widget _currentWorkCard(JsonMap summary) {
    final tasks=jsonList(summary['activeTasks']);
    final task=tasks.isEmpty ? null : tasks.first;
    final title=textOf(task?['title'],'暂无当前作业');
    final textScale=MediaQuery.textScalerOf(context).scale(1);
    final height=228+(textScale-1).clamp(0,2)*130;
    return Material(color: Colors.white,borderRadius: BorderRadius.circular(14),clipBehavior: Clip.antiAlias,
      child: Padding(padding: const EdgeInsets.all(8),child: SizedBox(height: height,child: Stack(children: [
        Positioned.fill(bottom: 40,child: ClipRRect(borderRadius: BorderRadius.circular(10),child: Image.asset(
          'assets/field-brand/preview/work_reference_scene.png',fit: BoxFit.cover,alignment: Alignment.centerRight))),
        Positioned(top: 1,left: 4,right: 2,child: Row(children: [
          Container(width: 5,height: 25,decoration: BoxDecoration(color: const Color(0xFF008BFF),borderRadius: BorderRadius.circular(3))),
          const SizedBox(width: 10),
          const Text('当前作业',style: TextStyle(fontSize: 21,fontWeight: FontWeight.w900,color: Color(0xFF101F43))),
        ])),
        Positioned(left: 5,top: 43,right: 118,bottom: 50,child: Column(crossAxisAlignment: CrossAxisAlignment.start,children: [
          Text(title,maxLines: 2,overflow: TextOverflow.ellipsis,style: const TextStyle(fontSize: 22,fontWeight: FontWeight.w900,color: Color(0xFF101F43))),
          const Spacer(),
          _metaLine(Icons.person_outline,'负责人',task==null?'未关联':workOwnerLabel(task,_session!)),
          const SizedBox(height: 5),
          _metaLine(Icons.person_outline,'监护人',task==null?'未关联':workGuardianLabel(task)),
          const SizedBox(height: 5),
          _metaLine(Icons.description_outlined,'',task==null?'暂无来源工作票':_ticketLine(task)),
        ])),
        Positioned(bottom: 0,left: 0,right: 0,child: FilledButton(
          key: const ValueKey('view-current-work'),
          style: FilledButton.styleFrom(backgroundColor:const Color(0xFF008BFF),minimumSize: const Size.fromHeight(44),
            shape: RoundedRectangleBorder(borderRadius:BorderRadius.circular(9))),
          onPressed: ()=>context.push(task==null?'/tasks':'/tasks/\${idOf(task['id'])}'),
          child: const Row(mainAxisAlignment:MainAxisAlignment.center,children:[Text('查看作业',style:TextStyle(fontSize:17,fontWeight:FontWeight.w700)),SizedBox(width:8),Icon(Icons.chevron_right,size:24)]),
        )),
      ]))),
    );
  }

'''+s[end:]
start=s.index('  Widget _dutyActions');end=s.index('  Widget _metric',start)
s=s[:start]+'''  Widget _dutyActions(JsonMap summary) {
    final hasUnclaimed=intOf(summary['unclaimed'])>0;
    return Align(alignment:Alignment.centerRight,child: Wrap(spacing:8,children:[
      TextButton(style:TextButton.styleFrom(visualDensity:VisualDensity.compact,minimumSize:const Size(48,32),padding:const EdgeInsets.symmetric(horizontal:5)),
        onPressed:()=>context.go(hasUnclaimed?'/events?status=open':'/events'),
        child:Text(hasUnclaimed?'查看待认领事件':'打开事件中心',style:const TextStyle(fontSize:11))),
      if(_session?.isDuty==true) TextButton(
        style:TextButton.styleFrom(visualDensity:VisualDensity.compact,minimumSize:const Size(48,32),padding:const EdgeInsets.symmetric(horizontal:5)),
        onPressed:_handoverBusy?null:_startHandover,child:Text(_handoverBusy?'正在提交…':'发起值班交接',style:const TextStyle(fontSize:11))),
    ]));
  }

'''+s[end:]
p.write_text(s,encoding='utf-8')
print('Applied task detail and red-box-only presentation changes.')
