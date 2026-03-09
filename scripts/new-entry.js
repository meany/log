const fs = require('node:fs/promises');
const path = require('node:path');
const readline = require('node:readline/promises');
const { stdin, stdout } = require('node:process');

const ENTRIES_DIR = path.join(process.cwd(), 'content', 'entries');

function formatDate(date = new Date()) {
  const year = date.getFullYear();
  const month = String(date.getMonth() + 1).padStart(2, '0');
  const day = String(date.getDate()).padStart(2, '0');
  return `${year}-${month}-${day}`;
}

function slugify(value) {
  return value
    .toLowerCase()
    .replace(/\[[^\]]*\]/g, ' ')
    .replace(/[^a-z0-9]+/g, '-')
    .replace(/^-+|-+$/g, '')
    .replace(/-{2,}/g, '-');
}

function yamlEscape(value) {
  return String(value).replace(/"/g, '\\"');
}

async function main() {
  const rl = readline.createInterface({ input: stdin, output: stdout });

  try {
    const titleInput = (await rl.question('title: ')).trim();
    if (!titleInput) {
      throw new Error('title is required.');
    }

    const tagsInput = (await rl.question('tags (comma-separated): ')).trim();
    const authorInput = (await rl.question('author [meany]: ')).trim();

    const author = authorInput || 'meany';
    const tags = tagsInput
      .split(',')
      .map((tag) => tag.trim())
      .filter(Boolean);

    const date = formatDate(new Date());
    const baseSlug = slugify(titleInput) || 'new-entry';
    const slug = `${date}-${baseSlug}`;
    const fileName = `${slug}.md`;
    const filePath = path.join(ENTRIES_DIR, fileName);

    const tagYaml =
      tags.length > 0
        ? tags.map((tag) => `  - ${tag}`).join('\n')
        : '  - web';

    const content = `---
date: ${date}
title: "${yamlEscape(titleInput)}"
tags:\n${tagYaml}
author: "${yamlEscape(author)}"
slug: "${slug}"
summary: "TODO: add summary"
featured_image: "/entries/${slug}/og.png"
ai_note: false
draft: true
---
## Notes

TODO: write entry content.
`;

    await fs.writeFile(filePath, content, { flag: 'wx' });

    stdout.write(`Created ${path.relative(process.cwd(), filePath)}\n`);
  } finally {
    rl.close();
  }
}

main().catch((error) => {
  console.error(error.message);
  process.exitCode = 1;
});
