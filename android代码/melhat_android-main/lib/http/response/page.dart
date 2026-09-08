class DataPage<T> {
  int? current;
  int? pages;
  List<T>? records;
  bool? searchCount;
  int? size;
  int? total;

  DataPage({
    this.current,
    this.pages,
    this.records,
    this.searchCount,
    this.size,
    this.total,
  });

  DataPage.fromJson(
    Map<String, dynamic> json,
    T Function(Map<String, dynamic>) fromJsonT,
  ) {
    if (json["current"] is int) {
      current = json["current"];
    }
    if (json["pages"] is int) {
      pages = json["pages"];
    }
    if (json["records"] is List) {
      records = (json['records'] as List<dynamic>?)
          ?.map((e) => fromJsonT(e as Map<String, dynamic>))
          .toList();
    }
    if (json["searchCount"] is bool) {
      searchCount = json["searchCount"];
    }
    if (json["size"] is int) {
      size = json["size"];
    }
    if (json["total"] is int) {
      total = json["total"];
    }
  }

  Map<String, dynamic> toJson() {
    final Map<String, dynamic> data = <String, dynamic>{};
    data["current"] = current;
    data["pages"] = pages;
    data["records"] = records?.map((e) {
      if (e is Map<String, dynamic>) {
        return e;
      } else if (e is Object) {
        final dynamic dynamicItem = e;
        return dynamicItem.toJson();
      } else {
        return e;
      }
    }).toList();
    data["searchCount"] = searchCount;
    data["size"] = size;
    data["total"] = total;
    return data;
  }

  bool get isEmpty {
    if (records == null) {
      return true;
    }
    return records!.isEmpty;
  }
}
