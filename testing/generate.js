const fs = require('fs');
const glob = require('glob');
const path = require('path');
const slugify = require('slugify');
const yaml = require('js-yaml');

const HOSTNAME = 'api';
// const HOSTNAME = 'localhost';

function globalSetup() {
  const email = process.env.RETOOL_TEST_ACCOUNT || 'retool-test@example.com'
  const password = process.env.RETOOL_TEST_PASSWORD || 'password'
  return `// global-setup.ts
import { chromium } from '@playwright/test'

async function globalSetup() {
  const browser = await chromium.launch()
  const page = await browser.newPage()
  await page.goto('http://${HOSTNAME}:3000/auth/login')
  await page.fill('#email', '${email}')
  await page.fill('#password', '${password}')
  await page.click('.auth-button')
  await page.waitForSelector('.app-browser', {timeout: 180000}) // Wait three minutes for apps to sync
  await page.context().storageState({ path: 'state.json' })
  await browser.close()
}

export default globalSetup
`
}

function playwrightConfig() {
  return `import { PlaywrightTestConfig } from '@playwright/test'

const config: PlaywrightTestConfig = {
  testDir: 'tests',
  globalSetup: 'global-setup.ts',
  reporter: 'list',
  workers: 4,
  use: {
    // Browser options
    // headless: false,
    // slowMo: 50,
  },
}

export default config
`
}

function playwrightTest(appName, folderName) {
  const encodedAppName = encodeURIComponent(appName);
  const encodedFolderName = encodeURIComponent(folderName);
  const testAppName = appName.replace("'", "");
	
  return `import { test, expect } from '@playwright/test'

export class RetoolApplication {
  page: any
  name: string
  folder?: string

  constructor(page, name: string, folder?: string) {
    this.page = page
    this.name = name
    this.folder = folder
  }

  async openEditor() {
    let url = ''
    if (this.folder) {
      url = 'http://${HOSTNAME}:3000/editor/'+this.folder+'/'+this.name
    } else {
      url = 'http://${HOSTNAME}:3000/editor/'+this.name
    }
    await this.page.goto(url)
    expect(this.page.url()).toBe(url)
  }

  async runAllTests() {
    // Click [data-testid="overflow-menu"]
    await this.page.click('[data-testid="overflow-menu"]')

    // Click [data-testid="open-tests-modal"]
    await this.page.click('[data-testid="open-tests-modal"]')

    // Click [data-testid="run-all-tests"]
    await this.page.click('[data-testid="run-all-tests"]')

    await this.page.waitForSelector('[data-testid="all-tests-complete"]')
  }

  async assertResults() {
    // TODO: Figure out a stable interface for the tests results
    const actual = {}
    const expected = {}
    const testResults = await this.page.$$('[data-testid="test-success-row"]')
    for (const result of testResults) {
      const text = await result.textContent()
      if (text && text.startsWith('FAIL')) {
        expected[text.replace('FAIL', '')] = true
        actual[text.replace('FAIL', '')] = false
      }
      if (text && text.startsWith('SUCCESS')) {
        expected[text.replace('SUCCESS', '')] = true
        actual[text.replace('SUCCESS', '')] = true
      }
    }

    expect(actual).toMatchObject(expected)
  }

  async test() {
    await this.openEditor()
    await this.runAllTests()
    await this.assertResults()
  }
}

test.use({ storageState: 'state.json' })

test('${folderName ? folderName.replace("'", "") + '/' : ''}${testAppName}', async ({ page }) => {
  const app = new RetoolApplication(page, "${encodedAppName}", "${encodedFolderName || ''}")
  await app.test()
})
`
}

function main() {
  const basePath = '/usr/local/retool-git-repo';
  const workingDir = '/ms-playwright';

  // const basePath = '../seedrepo';
  // const workingDir = '.';

  fs.writeFileSync(path.join(workingDir, 'global-setup.ts'), globalSetup());
  fs.writeFileSync(path.join(workingDir, 'playwright.config.ts'), playwrightConfig());

  try {
    fs.mkdirSync(path.join(workingDir, 'tests'));
  } catch (e) {
    // console.log('error creating directory');
  }
  
  // TODO: Support protected applications
  const protectedPath = path.join(basePath, '.retool', 'protected-apps.yaml');
  if (fs.existsSync(path)) {
    console.log('Testing Protected Applications in CI is currently not supported');
    process.exit(1);
  }

  const apps = glob.sync(path.join(basePath, 'apps', '**', '*.yml'));

  for (const file of apps) {
    try {
      const doc = yaml.load(fs.readFileSync(file, 'utf8'));
      if (!doc.appTemplate) {
        continue
      }
      if (!doc.appTemplate.testEntities) {
        continue
      }
      if (!doc.appTemplate.testEntities.array) {
        continue
      }
      if (doc.appTemplate.testEntities.array.length === 0) {
        continue
      }
      const parsed = path.parse(file);
      // TODO: Ensure file names are unique
      if (parsed.dir !== path.join(basePath, 'apps')) {
        const dirName = path.basename(parsed.dir);
        const fileName = slugify(`${dirName}-${parsed.name}`, {lower: true});
        const testPath = path.join(workingDir, 'tests', `${fileName}.spec.ts`);
        fs.writeFileSync(testPath, playwrightTest(parsed.name, dirName));
      } else {
        const fileName = slugify(parsed.name, {lower: true});
        const testPath = path.join(workingDir, 'tests', `${fileName}.spec.ts`);
        fs.writeFileSync(testPath, playwrightTest(parsed.name));
      }
    } catch (e) {
      console.error(e);
    }
  }
}

main();
