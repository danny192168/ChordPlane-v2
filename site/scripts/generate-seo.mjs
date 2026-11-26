import { access, copyFile } from 'node:fs/promises';

// @astrojs/sitemap writes sitemap-index.xml + sitemap-0.xml. Search Console
// accepts an index, but our submitted URL has always been /sitemap.xml, so
// publish the index under that stable name too.
const index = new URL('../dist/sitemap-index.xml', import.meta.url);
const alias = new URL('../dist/sitemap.xml', import.meta.url);

await access(index);
await copyFile(index, alias);
console.log('Wrote dist/sitemap.xml');
