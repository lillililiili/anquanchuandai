module.exports = {
  root: true,
  env: { browser: true, node: true, es2022: true },
  extends: ['eslint:recommended', 'plugin:vue/vue3-essential'],
  parserOptions: { ecmaVersion: 'latest', sourceType: 'module' },
  ignorePatterns: ['dist', 'dist-demo', 'dist-mock', 'node_modules', 'output', '.playwright-cli'],
  rules: { 'vue/multi-word-component-names': ['error', { ignores: ['App'] }] }
}
