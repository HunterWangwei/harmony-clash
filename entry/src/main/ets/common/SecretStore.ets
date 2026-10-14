import { asset } from '@kit.AssetStoreKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { util } from '@kit.ArkTS';
import { hilog } from '@kit.PerformanceAnalysisKit';

const TAG = 'ClashSecret';
const encoder = new util.TextEncoder();
const decoder = util.TextDecoder.create('utf-8');

// Secrets in the system Asset Store: encrypted at rest and excluded from backups,
// unlike the plain preferences file. Values are small UTF-8 strings keyed by alias.
export class SecretStore {
  private static query(alias: string): asset.AssetMap {
    const q: asset.AssetMap = new Map();
    q.set(asset.Tag.ALIAS, encoder.encodeInto(alias));
    return q;
  }

  // Returns undefined when the alias is absent or the store is unavailable.
  static get(alias: string): string | undefined {
    const q = SecretStore.query(alias);
    q.set(asset.Tag.RETURN_TYPE, asset.ReturnType.ALL);
    try {
      const found = asset.querySync(q);
      const secret = found.length > 0 ? found[0].get(asset.Tag.SECRET) as Uint8Array : undefined;
      return secret ? decoder.decodeToString(secret) : undefined;
    } catch (e) {
      if ((e as BusinessError).code !== asset.ErrorCode.NOT_FOUND) {
        hilog.error(0x0000, TAG, 'query %{public}s failed: %{public}s', alias, JSON.stringify(e));
      }
      return undefined;
    }
  }

  // An empty value removes the entry; the Asset Store rejects zero-length secrets.
  static set(alias: string, value: string): void {
    if (value.length === 0) {
      SecretStore.remove(alias);
      return;
    }
    const data = encoder.encodeInto(value);
    try {
      const attrs: asset.AssetMap = SecretStore.query(alias);
      attrs.set(asset.Tag.SECRET, data);
      // Readable once the device has been unlocked after boot, so the VPN can start
      // later while the screen is locked.
      attrs.set(asset.Tag.ACCESSIBILITY, asset.Accessibility.DEVICE_FIRST_UNLOCKED);
      asset.addSync(attrs);
    } catch (e) {
      if ((e as BusinessError).code !== asset.ErrorCode.DUPLICATED) {
        throw new Error(`保存密钥失败: ${(e as BusinessError).message}`);
      }
      const update: asset.AssetMap = new Map();
      update.set(asset.Tag.SECRET, data);
      asset.updateSync(SecretStore.query(alias), update);
    }
  }

  static remove(alias: string): void {
    try {
      asset.removeSync(SecretStore.query(alias));
    } catch (e) {
      // Already absent.
    }
  }
}
