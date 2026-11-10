const test = require('node:test');
const assert = require('node:assert');
const { slugify } = require('../src/text/slug');
const old = require('../src/text/slug.old');

test('slugifies a title', () => {
  assert.strictEqual(slugify('Hello, World!'), 'hello-world');
});

test('the old version gives the same slug', () => {
  assert.strictEqual(old.slugify('Hello, World!'), 'hello-world');
});
