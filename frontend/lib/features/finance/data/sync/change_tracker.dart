class SyncOp {
  const SyncOp(this.key, this.entity, this.id, this.data);
  final String key, entity, id;
  final Map<String, dynamic>? data;

  bool get isDelete => data == null;

  Map<String, dynamic> toJson() => {
        'entity': entity,
        'action': isDelete ? 'delete' : 'upsert',
        'id': id,
        if (data != null) 'data': data,
      };
}

// Hàng chờ các thay đổi chưa gửi lên máy chủ. Mỗi thay đổi có số thứ tự riêng,
// nên nếu người dùng sửa tiếp trong lúc đang gửi thì bản mới vẫn nằm lại để gửi lần sau.
class ChangeTracker {
  final Map<String, int> _versions = {};
  int _clock = 0;

  // Thêm ví, danh mục trước rồi mới tới giao dịch dùng chúng; khi xóa thì làm ngược lại.
  static const _upsertOrder = ['wallets', 'categories', 'people', 'recurring', 'entries', 'budgets'];
  static const _deleteFirst = ['budgets', 'entries', 'recurring'];
  static const _deleteLast = ['people', 'categories', 'wallets'];

  int get length => _versions.length;
  bool get isEmpty => _versions.isEmpty;
  List<String> get keys => _versions.keys.toList();

  void mark(String entity, String id) => _versions['$entity:$id'] = ++_clock;

  void restore(Iterable<Object?> keys) {
    _versions.clear();
    for (final key in keys) {
      _versions['$key'] = ++_clock;
    }
  }

  void clear() => _versions.clear();

  ({List<SyncOp> ops, Map<String, int> versions}) pending(
      Map<String, dynamic>? Function(String entity, String id) jsonOf) {
    final versions = Map.of(_versions);
    final upserts = <String, List<SyncOp>>{};
    final deletes = <String, List<SyncOp>>{};
    for (final key in versions.keys) {
      final i = key.indexOf(':');
      final entity = key.substring(0, i), id = key.substring(i + 1);
      final op = SyncOp(key, entity, id, jsonOf(entity, id));
      (op.isDelete ? deletes : upserts).putIfAbsent(entity, () => []).add(op);
    }
    return (
      ops: [
        for (final e in _deleteFirst) ...?deletes[e],
        for (final e in _upsertOrder) ...?upserts[e],
        for (final e in _deleteLast) ...?deletes[e],
      ],
      versions: versions,
    );
  }

  void acknowledge(Iterable<SyncOp> ops, Map<String, int> versions) {
    for (final op in ops) {
      if (_versions[op.key] == versions[op.key]) _versions.remove(op.key);
    }
  }
}
