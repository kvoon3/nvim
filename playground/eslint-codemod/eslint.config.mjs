import command from 'eslint-plugin-command'

export default [
  {
    files: ['**/*.ts'],
    languageOptions: {
      parserOptions: {
        ecmaVersion: 'latest',
        sourceType: 'module',
      },
    },
    plugins: {
      command,
    },
    rules: {
      'command/command': 'error',
    },
  },
]
