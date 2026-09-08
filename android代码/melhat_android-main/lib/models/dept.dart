class DeptTree {
  String id;
  String label;
  List<dynamic>? children;

  DeptTree({required this.id, required this.label, this.children});

  DeptTree.fromJson(Map<String, dynamic> json)
      : id = json['id'] ?? '',
        label = json['label'] ?? '',
        children = json['children'] is List
            ? (json['children'] as List)
                .whereType<Map<String, dynamic>>()
                .map((e) => DeptTree.fromJson(e))
                .toList()
            : null;

  static List<DeptTree> fromList(List<Map<String, dynamic>> list) {
    return list.map((e) => DeptTree.fromJson(e)).toList();
  }

  Map<String, dynamic> toJson() {
    final Map<String, dynamic> _data = <String, dynamic>{};
    _data['id'] = id;
    _data['label'] = label;
    if (children != null) {
      _data['children'] = children!
          .map((child) {
            if (child is DeptTree) {
              return child.toJson();
            }
            return child;
          })
          .toList();
    }
    return _data;
  }
}
