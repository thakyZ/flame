const fs = require('fs').promises;
const path = require('path');

async function deleteDirectoryRecurse(dir) {
  return await fs.rm(dir, { recursive: true, force: true });
}

const badFolders = [
  'client/node_modules',
  'node_modules',
  'node-sqlite3/node_modules',
  'node-sqlite3/package-lock.json',
  'node-sqlite3/package-lock.json',
];

async function run() {
  console.log(__dirname);
  for await (const folder of badFolders) {
    await deleteDirectoryRecurse(path.join(__dirname, folder));
  }
}

(async function () {
  await run();
})();
