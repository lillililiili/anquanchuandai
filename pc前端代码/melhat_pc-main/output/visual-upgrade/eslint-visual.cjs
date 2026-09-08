module.exports = {
  root: true,
  env: { browser: true, es2022: true },
  parser: 'vue-eslint-parser',
  parserOptions: { parser: 'espree', ecmaVersion: 2022, sourceType: 'module' },
  plugins: ['vue'],
  extends: ['plugin:vue/vue3-essential'],
  rules: { 'vue/multi-word-component-names': 'off', 'vue/no-mutating-props': 'off', 'vue/no-side-effects-in-computed-properties':'off' }
}
