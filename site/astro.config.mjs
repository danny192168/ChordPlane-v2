import { defineConfig } from 'astro/config';

// The marketing site and the auth landing page. The Flutter web viewer is
// built separately into /viewer/ and reached through the /s/* rewrite that
// lives in the Chordplane-Web vercel.json.
export default defineConfig({
  site: 'https://chordplane.citcs.site',
  build: {
    format: 'directory',
  },
  devToolbar: {
    enabled: false,
  },
});
