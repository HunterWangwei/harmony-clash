import * as fs from 'fs';
import * as path from 'path';
import { hvigor } from '@ohos/hvigor';
import { appTasks, OhosAppContext, OhosPluginId } from '@ohos/hvigor-ohos-plugin';

// Signing material (certificate paths and encrypted passwords) is machine-specific, so it
// lives in the git-ignored signing.local.json5 and is injected here instead of being
// committed in build-profile.json5. Without the file the build produces an unsigned HAP.
const SIGNING_FILE = path.join(__dirname, 'signing.local.json5');

hvigor.nodesEvaluated(() => {
  if (!fs.existsSync(SIGNING_FILE)) {
    return;
  }
  // The file is a JSON array with one leading // comment line.
  const text = fs.readFileSync(SIGNING_FILE, 'utf-8').replace(/^\s*\/\/.*$/gm, '');
  const ctx = hvigor.getRootNode().getContext(OhosPluginId.OHOS_APP_PLUGIN) as OhosAppContext;
  const opt = ctx.getBuildProfileOpt();
  opt.app.signingConfigs = JSON.parse(text);
  ctx.setBuildProfileOpt(opt);
});

export default {
  system: appTasks,
  plugins: []
};
