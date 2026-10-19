import { defineConfig } from 'vite';
export default defineConfig({ base: '/apps/connect/', publicDir: false, build: { sourcemap: false, target: 'es2022' } });
