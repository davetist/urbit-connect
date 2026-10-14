from targets import TARGETS
"""Open the owner UI in the dedicated Firefox profile with test-only certificate trust."""
import subprocess
import argparse
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
SOURCE="""import { firefox } from 'playwright';
const context = await firefox.launchPersistentContext(process.argv[1], { headless: false, viewport: { width: 1360, height: 900 } });
const page = await context.newPage(); await page.goto(process.argv[5] + '/apps/connect/');
if (process.argv[2] === 'check') {
  await page.getByRole('heading', { name: /^(Documents|Open your Connect|Your apps[.] Your ship[.])$/ }).waitFor();
  await page.screenshot({ path: process.argv[3], fullPage: true });
  await context.close();
  process.stdout.write('PASS: documented owner UI opens in the dedicated trusted Firefox profile\\n');
} else await new Promise(resolve => context.on('close', resolve));
"""
if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('--check',action='store_true');args=parser.parse_args()
    screenshot=ROOT/'artifacts/alpha/browser/owner-quickstart.png';screenshot.parent.mkdir(parents=True,exist_ok=True)
    subprocess.run(['node','--input-type=module','-e',SOURCE,str(ROOT/'.work/alpha/firefox-profile'),'check'if args.check else'interactive',str(screenshot),TARGETS.origin()],cwd=ROOT/'web',check=True)
