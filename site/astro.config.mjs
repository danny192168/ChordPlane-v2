import { defineConfig } from 'astro/config';
import sitemap from '@astrojs/sitemap';

// The marketing site and the auth landing page. The Flutter web viewer is
// built separately into /viewer/ and reached through the /s/* rewrite that
// lives in the Chordplane-Web vercel.json.
export default defineConfig({
  site: 'https://chordplane.citcs.site',
  integrations: [
    sitemap({
      // The filter receives full URLs, so inspect the pathname. Utility pages
      // exist for link previews and auth callbacks; they must never appear in
      // search results.
      filter: (page) => {
        const path = new URL(page).pathname;
        return (
          !path.startsWith('/og') &&
          !path.startsWith('/auth/') &&
          !path.startsWith('/404')
        );
      },
    }),
  ],
  build: {
    format: 'directory',
  },
  devToolbar: {
    enabled: false,
  },
});
