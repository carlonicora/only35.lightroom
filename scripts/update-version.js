#!/usr/bin/env node

const fs = require('fs');
const path = require('path');

const version = process.argv[2];
if (!version) {
  console.error('Usage: update-version.js <version>');
  process.exit(1);
}

const [major, minor, patch] = version.split('.').map(Number);

const infoPath = path.join(__dirname, '..', 'only35.lrplugin', 'Info.lua');
let content = fs.readFileSync(infoPath, 'utf8');

// Update VERSION table
content = content.replace(/major = \d+/, `major = ${major}`);
content = content.replace(/minor = \d+/, `minor = ${minor}`);
content = content.replace(/revision = \d+/, `revision = ${patch}`);
content = content.replace(/display = "[^"]+"/, `display = "${version}"`);

fs.writeFileSync(infoPath, content);
console.log(`Updated Info.lua to version ${version}`);
