// Supplemental lint for the new JS/Vue island. Does not replace the legacy lint.
module.exports = {
  root: true,
  env: { browser: true, node: true, es2022: true },
  extends: ['eslint:recommended', 'plugin:vue/vue3-essential'],
  parserOptions: { ecmaVersion: 2022, sourceType: 'module' },
  globals: { defineProps: 'readonly', defineEmits: 'readonly' },
  rules: { 'vue/multi-word-component-names': 'off', 'no-unused-vars': ['error', { argsIgnorePattern: '^_' }] }
}
