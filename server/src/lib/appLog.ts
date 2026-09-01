type LogLevel = "info" | "warn" | "error";

interface AppLogEntry {
  ts: string;
  level: LogLevel;
  message: string;
}

const MAX_LOGS = 500;
const logs: AppLogEntry[] = [];

export function appLog(level: LogLevel, message: string): void {
  logs.push({ ts: new Date().toISOString(), level, message });
  if (logs.length > MAX_LOGS) logs.shift();
}

export function recentAppLogs(limit = 100): AppLogEntry[] {
  return logs.slice(-limit).reverse();
}
