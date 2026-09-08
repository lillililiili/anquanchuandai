class FieldDraft {
  String inquiry = '', measure = '', result = '';
  bool get complete =>
      inquiry.trim().isNotEmpty &&
      measure.trim().isNotEmpty &&
      result.trim().isNotEmpty;
  String get description =>
      '核查情况：${inquiry.trim()}\n处置措施：${measure.trim()}\n处理结果：${result.trim()}';
}

/// Only navigation state and unsent drafts. Business records remain on the server.
class FieldSession {
  static final instance = FieldSession();
  String _owner = '';
  String group = '',
      search = '',
      source = '',
      status = '0',
      type = '',
      start = '',
      end = '';
  String selectedKey = '';
  final Map<String, FieldDraft> drafts = {};
  void scope(String userId) {
    if (_owner != userId) {
      clear();
      _owner = userId;
    }
  }

  FieldDraft draft(String key) => drafts.putIfAbsent(key, FieldDraft.new);
  void clearFilters() {
    group = '';
    search = '';
    source = '';
    status = '';
    type = '';
    start = '';
    end = '';
  }

  void clear() {
    clearFilters();
    status = '0';
    selectedKey = '';
    drafts.clear();
    _owner = '';
  }
}
