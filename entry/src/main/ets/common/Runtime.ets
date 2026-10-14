// Constants and file formats shared by the UI process and the VPN extension process.
export const CONTROLLER_HOST: string = '127.0.0.1';
export const CONTROLLER_PORT: number = 19090;
// Must match localMixedPort in core/bridge/main.go.
export const LOCAL_MIXED_PORT: number = 17890;
// Must match tunMTU in core/bridge/main.go.
export const TUN_MTU: number = 1500;
export const RUNTIME_FILE: string = 'runtime.json';
export const STATE_FILE: string = 'vpn_state.json';
export const VPN_ABILITY: string = 'ClashVpnAbility';
// AppStorage key: true while the UI ability is in the foreground.
export const FOREGROUND_KEY: string = 'appForeground';

// Written by the UI before starting the VPN; read by the VPN extension.
export interface RuntimeConfig {
  home: string;
  config: string;
  secret: string;
}

// Written by the VPN extension so the UI can surface startup failures.
export interface VpnState {
  state: string; // 'starting' | 'running' | 'error' | 'stopped'
  message: string;
  time: number;
}
