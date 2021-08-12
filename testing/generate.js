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
import * as fs from 'fs'

const resultsDir = 'results'

async function globalSetup() {
  const browser = await chromium.launch({args:['--disable-dev-shm-usage']})
  const page = await browser.newPage()
  await page.goto('http://${HOSTNAME}:3000/auth/login')
  await page.fill('#email', '${email}')
  await page.fill('#password', '${password}')
  await page.click('.auth-button')
  await page.waitForSelector('.app-browser', {timeout: 180000}) // Wait three minutes for apps to sync
  await page.context().storageState({ path: 'state.json' })
  await browser.close()

  fs.mkdirSync(resultsDir)
}

export default globalSetup
`
}

function globalTeardown() {
  return `// global-teardown.ts
import * as fs from 'fs'

const resultsDir = 'results'

async function globalTeardown() {
  fs.rmdirSync(resultsDir, {recursive: true})
}

export default globalTeardown
`
}

function playwrightConfig() {
  return `import { PlaywrightTestConfig } from '@playwright/test'

const config: PlaywrightTestConfig = {
  testDir: 'tests',
  globalSetup: 'global-setup.ts',
  globalTeardown: 'global-teardown.ts',
  reporter: 'list',
  workers: 1,
  use: {
    launchOptions: {
      args: ['--disable-dev-shm-usage'],
    },
    // Browser options
    // headless: false,
    // slowMo: 50,
  },
}

export default config
`
}

function playwrightTest(appName, testNames, folderName) {
  const encodedAppName = encodeURIComponent(appName);
  const encodedFolderName = encodeURIComponent(folderName);
  const testAppName = appName.replace("'", "");

  const beforeEachHook =
`  test.beforeEach(async ({ page }) => {
    if (!fs.existsSync(resultsPath)) {
      const app = new RetoolApplication(page, "${encodedAppName}", "${folderName ? encodedFolderName : ''}")
      const results = await app.test()

      fs.writeFileSync(resultsPath, results)
    }
  })`

  const individualTests = testNames.map(test =>
`  test('${test}', async () => {
    if (!fs.existsSync(resultsPath)) {
      throw new Error(resultsPath + " does not exist")
    }

    const rawResults = fs.readFileSync(resultsPath)
    const results = JSON.parse(rawResults.toString())

    // only checking for result if test actually had a body and executed
    if (results['${test}']) {
      expect(results['${test}']).toBe(true)
    }
  })`).join('\n\n')

  return `import { test, expect } from '@playwright/test'
import * as fs from 'fs'
import * as path from 'path'

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
    await this.page.click('[data-testid="run-all-tests"]', {timeout: 60000})
  }

  async assertResults(): Promise<string> {
    const actual = {}
    const rawResults = await this.page.getAttribute('[data-testid="all-tests-complete"]', 'data-testResults', {timeout: 60000})
    const results = JSON.parse(rawResults)

    if (results['tests']) {
      results['tests'].forEach(function (test) {
        const testName = test['name']
        actual[testName] = test['passed']
      })
    }

    await this.closePage(this.page)

    return JSON.stringify(actual)
  }

  async test(): Promise<string> {
    await this.openEditor()
    await this.runAllTests()
    return await this.assertResults()
  }

  async closePage(page) {
    try {
      if (page && !page.isClosed()) {
        await page.close();
      }
    } catch (e) {}
  }
}

test.use({ storageState: 'state.json' })

const folderName = '${folderName ? folderName.replace("'", "") + '-' : ''}'
const appName = '${testAppName}'
const resultsDir = 'results'
const resultsPath = path.join(resultsDir, folderName +  appName + '-test-results.json')

test.describe('${folderName ? folderName.replace("'", "") + '/' : ''}${testAppName}', () => {\n${beforeEachHook}\n\n${individualTests}
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
  fs.writeFileSync(path.join(workingDir, 'global-teardown.ts'), globalTeardown());

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
      const testNames = doc.appTemplate.testEntities.array.map(test => test.object.name)
      // TODO: Ensure file names are unique

      if (parsed.dir !== path.join(basePath, 'apps')) {
        const dirName = path.basename(parsed.dir);
        const fileName = slugify(`${dirName}-${parsed.name}`, {lower: true});
        const testPath = path.join(workingDir, 'tests', `${fileName}.spec.ts`);
        fs.writeFileSync(testPath, playwrightTest(parsed.name, testNames, dirName));
      } else {
        const fileName = slugify(parsed.name, {lower: true});
        const testPath = path.join(workingDir, 'tests', `${fileName}.spec.ts`);
        fs.writeFileSync(testPath, playwrightTest(parsed.name, testNames));
      }
    } catch (e) {
      console.error(e);
    }
  }
}

main();
