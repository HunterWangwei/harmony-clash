export function formatBytes(n: number): string {
  const units: string[] = ['B', 'KB', 'MB', 'GB', 'TB'];
  let v = n;
  let i = 0;
  while (v >= 1024 && i < units.length - 1) {
    v /= 1024;
    i++;
  }
  return `${v.toFixed(i === 0 ? 0 : 1)} ${units[i]}`;
}

export function formatSpeed(n: number): string {
  return `${formatBytes(n)}/s`;
}

export function delayColor(d: number | undefined): ResourceColor {
  if (d === undefined) {
    return '#9AA0A6';
  }
  if (d === 0) {
    return '#D93025';
  }
  return d < 300 ? '#188038' : (d < 800 ? '#E37400' : '#D93025');
}

function pad2(x: number): string {
  return x.toString().padStart(2, '0');
}

export function formatDate(ms: number): string {
  if (ms <= 0) {
    return '--';
  }
  const d = new Date(ms);
  return `${d.getFullYear()}-${pad2(d.getMonth() + 1)}-${pad2(d.getDate())} ${pad2(d.getHours())}:${pad2(d.getMinutes())}`;
}
