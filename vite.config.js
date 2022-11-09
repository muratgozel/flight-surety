import { defineConfig } from 'vite'

export default defineConfig({
  root: './dapp',
  publicDir: './dapp/public',
  server: {
    port: 8000
  },
  build: {
    sourcemap: true,
    target: 'es2015'
  },
  plugins: []
})
