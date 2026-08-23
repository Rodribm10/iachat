import { defineConfig } from 'vite';
import ruby from 'vite-plugin-ruby';
import vue from '@vitejs/plugin-vue';
import { aliases, vueOptions } from './vite.shared';
import yaml from '@rollup/plugin-yaml';

export default defineConfig({
  plugins: [ruby(), vue(vueOptions), yaml()],
  css: {
    preprocessorOptions: {
      scss: {
        api: 'modern-compiler',
      },
    },
  },
  resolve: { alias: aliases },
  // Proxy do fork: o dev server do Vite encaminha /rails pro Rails local.
  server: {
    proxy: {
      '/rails': {
        target: 'http://127.0.0.1:3000',
        changeOrigin: true,
      },
    },
  },
});
