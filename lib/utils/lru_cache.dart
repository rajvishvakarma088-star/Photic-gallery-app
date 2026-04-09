import 'dart:collection';

class LruMap<K, V> {
  LruMap(this.maxEntries, {this.onEvict}) : assert(maxEntries > 0);

  final int maxEntries;
  final void Function(V value)? onEvict;
  final LinkedHashMap<K, V> _items = LinkedHashMap<K, V>();

  int get length => _items.length;

  void clear() => _items.clear();

  bool containsKey(K key) {
    if (!_items.containsKey(key)) return false;
    _touch(key);
    return true;
  }

  V? operator [](K key) {
    final value = _items[key];
    if (value == null) return null;
    _touch(key);
    return value;
  }

  V putIfAbsent(K key, V Function() create) {
    final existing = _items[key];
    if (existing != null) {
      _touch(key);
      return existing;
    }
    final value = create();
    _items[key] = value;
    _evictIfNeeded();
    return value;
  }

  void _touch(K key) {
    final value = _items.remove(key);
    if (value == null) return;
    _items[key] = value;
  }

  void _evictIfNeeded() {
    while (_items.length > maxEntries) {
      final oldestKey = _items.keys.first;
      final removed = _items.remove(oldestKey);
      if (removed != null) {
        onEvict?.call(removed);
      }
    }
  }
}

class LruSet<T> {
  LruSet(this.maxEntries) : assert(maxEntries > 0);

  final int maxEntries;
  final LinkedHashSet<T> _items = LinkedHashSet<T>();

  int get length => _items.length;

  void clear() => _items.clear();

  bool contains(T value) {
    if (!_items.contains(value)) return false;
    _touch(value);
    return true;
  }

  void add(T value) {
    _items.remove(value);
    _items.add(value);
    _evictIfNeeded();
  }

  void _touch(T value) {
    _items.remove(value);
    _items.add(value);
  }

  void _evictIfNeeded() {
    while (_items.length > maxEntries) {
      _items.remove(_items.first);
    }
  }
}
