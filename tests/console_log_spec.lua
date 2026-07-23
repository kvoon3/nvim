local expect = require('mini.test').expect
local console_log = require 'config.console-log'

describe('console snippets', function()
  it('labels expressions', function()
    expect.equality("console.log('user.name', user.name)", console_log.format('log', 'user.name'))
  end)

  it('prints simple string literals without a duplicate label', function()
    expect.equality("console.warn('it\\'s ready')", console_log.format('warn', '"it\'s ready"'))
  end)

  it('preserves template literals and escaped strings as expressions', function()
    expect.equality("console.log('`hello ${name}`', `hello ${name}`)", console_log.format('log', '`hello ${name}`'))
    expect.equality([[console.log('\'it\\\'s\'', 'it\'s')]], console_log.format('log', [['it\'s']]))
  end)

  it('uses console.table data as its first argument', function()
    expect.equality('console.table(users)', console_log.format('table', 'users'))
  end)
end)
