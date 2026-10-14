export const start: (homeDir: string, configFile: string, controller: string, secret: string,
  tunFd?: number) => Promise<void>;
export const stop: () => void;
export const isRunning: () => boolean;
export const version: () => string;
export const parseGroups: (configFile: string) => Promise<string>;
