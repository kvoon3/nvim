#!/usr/bin/env node
// Headless ESLint worker for eslint-codemod nvim plugin.
// Reads JSON payload from stdin: { cwd, filePath, code }
// Flags: --check <name>      -> { fixable, error }
//        --result <name>     -> { fixable, diff, message, fix, error }
//        --check-all n1,n2   -> { results: { [name]: { fixable, error? } } }

import { basename } from 'node:path'
import { pathToFileURL } from 'node:url'
import { createRequire } from 'node:module'
import process from 'node:process'

const args = process.argv.slice(2)
const mode = args[0] // --check | --result | --check-all
const commandName = args[1]

let stdin = ''
for await (const chunk of process.stdin) stdin += chunk

let payload
try {
  payload = JSON.parse(stdin || '{}')
} catch {
  console.error('invalid payload')
  process.exit(1)
}

const cwd = payload.cwd || process.cwd()
const filePath = payload.filePath || 'untitled.ts'
const code = payload.code || ''

try {
  process.chdir(cwd)
} catch {}

function resolveEslint() {
  try {
    const require = createRequire(pathToFileURL(cwd + '/package.json').href)
    const modPath = require.resolve('eslint')
    return import(pathToFileURL(modPath).href)
  } catch {}
  try {
    return import('eslint')
  } catch (e) {
    throw new Error('Cannot find eslint module: ' + e.message)
  }
}

async function buildDiff(beforeText, afterText, file) {
  try {
    const require = createRequire(pathToFileURL(cwd + '/package.json').href)
    const diffPath = require.resolve('diff')
    const { createPatch } = await import(pathToFileURL(diffPath).href)
    return createPatch(basename(file), beforeText.trim(), afterText.trim(), 'old', `new (${commandName})`, {
      ignoreWhitespace: true,
    })
  } catch {
    if (beforeText === afterText) return ''
    return `--- ${basename(file)}\n+++ new (${commandName})\n@@\n-${beforeText.trim()}\n+${afterText.trim()}\n`
  }
}

// Insert the command name into the first `///` comment line.
function appendCommand(codeText, name) {
  return codeText
    .split('\n')
    .map((line) => (/^\s*\/\/\//.test(line) ? line.replace(/^(\s*\/\/\/\s*).*/, `$1${name}`) : line))
    .join('\n')
}

async function run() {
  const eslintMod = await resolveEslint()
  const { ESLint } = eslintMod
  const eslint = new ESLint({ cwd, fix: false, cache: false })
  const configPath = await eslint.findConfigFile().catch(() => null)
  if (!configPath) {
    throw new Error('Cannot find eslint config file')
  }

  const lintOne = async (text) => {
    const [result] = await eslint.lintText(text, { filePath, warnIgnored: true })
    return (result?.messages || []).filter((m) => m.ruleId === 'command/command')
  }

  if (mode === '--check') {
    const messages = await lintOne(appendCommand(code, commandName))
    const fixable = messages.find((m) => m.messageId === 'command-fix' && m.fix && m.endLine && m.endColumn)
    if (fixable) {
      console.log(JSON.stringify({ fixable: true }))
    } else {
      const errMsg =
        messages.find((m) => ['command-error', 'command-error-cause'].includes(m.messageId))?.message ||
        'Unfixable command'
      console.log(JSON.stringify({ fixable: false, error: errMsg }))
    }
    return
  }

  if (mode === '--check-all') {
    const names = (commandName || '').split(',').filter(Boolean)
    const results = {}
    for (const name of names) {
      try {
        const messages = await lintOne(appendCommand(code, name))
        const hasFix = messages.some((m) => m.messageId === 'command-fix' && m.fix && m.endLine && m.endColumn)
        if (hasFix) {
          results[name] = { fixable: true }
        } else {
          results[name] = {
            fixable: false,
            error:
              messages.find((m) => ['command-error', 'command-error-cause'].includes(m.messageId))?.message ||
              'Unfixable command',
          }
        }
      } catch (err) {
        results[name] = { fixable: false, error: err.message }
      }
    }
    console.log(JSON.stringify({ results }))
    return
  }

  // --result
  const injected = appendCommand(code, commandName)
  const messages = await lintOne(injected)
  const fixable = messages.find((m) => m.messageId === 'command-fix' && m.fix && m.endLine && m.endColumn)

  if (fixable) {
    const fix = fixable.fix
    let beforeText = ''
    if (fix.range && Array.isArray(fix.range)) {
      beforeText = injected.slice(fix.range[0], fix.range[1])
    }
    const diff = await buildDiff(beforeText, fix.text || '', filePath)
    console.log(
      JSON.stringify({
        fixable: true,
        fix,
        diff,
        message: fixable,
      }),
    )
  } else {
    const errMsg =
      messages.find((m) => ['command-error', 'command-error-cause'].includes(m.messageId))?.message ||
      'Unfixable command'
    console.log(JSON.stringify({ fixable: false, error: errMsg }))
  }
}

run().catch((err) => {
  // For check modes, still emit JSON so Lua can differentiate.
  if (mode === '--check-all') {
    const names = (commandName || '').split(',').filter(Boolean)
    const results = {}
    for (const n of names) results[n] = { fixable: true }
    console.log(JSON.stringify({ results, fallback: true, error: err.message }))
  } else {
    console.log(JSON.stringify({ fixable: true, fallback: true, error: err.message }))
  }
  process.exit(0)
})
