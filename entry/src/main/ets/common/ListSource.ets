// Minimal IDataSource for LazyForEach: only visible rows are built, and changes are
// reported as add/delete/reload instead of re-diffing the whole array.
// Every change goes through onDatasetChange: ArkUI throws (401) if one listener receives
// both onDatasetChange and the older onDataReloaded/onDataAdd style calls.
export class ListSource<T> implements IDataSource {
  private items: T[] = [];
  private listeners: DataChangeListener[] = [];

  totalCount(): number {
    return this.items.length;
  }

  getData(index: number): T {
    return this.items[index];
  }

  registerDataChangeListener(listener: DataChangeListener): void {
    if (!this.listeners.includes(listener)) {
      this.listeners.push(listener);
    }
  }

  unregisterDataChangeListener(listener: DataChangeListener): void {
    const i = this.listeners.indexOf(listener);
    if (i >= 0) {
      this.listeners.splice(i, 1);
    }
  }

  // Replaces everything; use when most rows change at once.
  setAll(items: T[]): void {
    this.items = items;
    this.notify([{ type: DataOperationType.RELOAD }]);
  }

  // Appends rows, then drops the oldest ones beyond max.
  append(rows: T[], max: number): void {
    if (rows.length === 0) {
      return;
    }
    const start = this.items.length;
    this.items.push(...rows);
    this.notify([{ type: DataOperationType.ADD, index: start, count: rows.length }]);
    const extra = this.items.length - max;
    if (extra > 0) {
      this.items.splice(0, extra);
      this.notify([{ type: DataOperationType.DELETE, index: 0, count: extra }]);
    }
  }

  private notify(ops: DataOperation[]): void {
    this.listeners.forEach((l: DataChangeListener) => { l.onDatasetChange(ops); });
  }

  clear(): void {
    this.setAll([]);
  }
}
